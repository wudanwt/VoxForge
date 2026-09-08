import AppKit
import CoreGraphics
import AVFoundation
import Foundation
import IOKit.hid
import os

final class ExternalTriggerService: @unchecked Sendable {
    struct Configuration: Hashable {
        var enabled: Bool
        var vendorID: Int
        var productID: Int
        var suppressVolume: Bool
        var cancelModifier: ExternalTriggerCancelModifier
        var cancelModifierEnabled: Bool
    }

    var onDevicesChanged: (([ExternalTriggerDevice], ExternalTriggerStatus) -> Void)?
    var onEvent: ((ExternalTriggerLastEvent) -> Void)?
    var onPrimaryTrigger: (() -> Void)?
    var onCancelTrigger: (() -> Void)?

    private let logger = Logger(subsystem: "com.voxforge.app", category: "ExternalTrigger")
    private var configuration: Configuration
    private var discoveryManager: IOHIDManager?
    private var listeningManager: IOHIDManager?
    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?
    private var devices: [ExternalTriggerDevice] = []
    private var pendingVolumeIncrementAt: CFAbsoluteTime?
    private var didSeizeSelectedDevice = false
    private var started = false

    init(configuration: Configuration) {
        self.configuration = configuration
    }

    func update(configuration: Configuration) {
        self.configuration = configuration
        if started {
            configureListeningManager()
            refreshDevices()
            configureEventTap()
            publishStatus()
        }
    }

    func start() {
        guard !started else { return }
        started = true
        logger.info("Starting external trigger service")
        configureDiscoveryManager()
        configureListeningManager()
        configureEventTap()
        refreshDevices()
        publishStatus()
    }

    func stop() {
        started = false

        closeManager(&discoveryManager)
        closeManager(&listeningManager)
        didSeizeSelectedDevice = false

        if let eventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapRunLoopSource, .commonModes)
        }
        eventTapRunLoopSource = nil
        eventTap = nil
    }

    private func closeManager(_ manager: inout IOHIDManager?) {
        if let manager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil
    }

    func recheck() {
        refreshDevices()
        configureEventTap()
        publishStatus()
    }

    private func configureDiscoveryManager() {
        closeManager(&discoveryManager)
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [[String: Int]] = [
            [
                kIOHIDDeviceUsagePageKey: kHIDPage_Consumer,
                kIOHIDDeviceUsageKey: kHIDUsage_Csmr_ConsumerControl
            ]
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, _ in
            guard let context else { return }
            Task { @MainActor in
                Unmanaged<ExternalTriggerService>.fromOpaque(context).takeUnretainedValue().refreshDevices()
            }
        }, selfPointer)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, _ in
            guard let context else { return }
            Task { @MainActor in
                Unmanaged<ExternalTriggerService>.fromOpaque(context).takeUnretainedValue().refreshDevices()
            }
        }, selfPointer)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let status = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        discoveryManager = manager
        logger.info("HID discovery manager opened with status \(status)")
    }

    private func configureListeningManager() {
        closeManager(&listeningManager)
        didSeizeSelectedDevice = false
        guard configuration.enabled else { return }

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Int] = [
            kIOHIDVendorIDKey: configuration.vendorID,
            kIOHIDProductIDKey: configuration.productID,
            kIOHIDDeviceUsagePageKey: kHIDPage_Consumer,
            kIOHIDDeviceUsageKey: kHIDUsage_Csmr_ConsumerControl
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(manager, { context, _, _, value in
            guard let context else { return }
            Task { @MainActor in
                Unmanaged<ExternalTriggerService>.fromOpaque(context).takeUnretainedValue().handleHIDValue(value)
            }
        }, selfPointer)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        var options = configuration.suppressVolume ? IOOptionBits(kIOHIDOptionsTypeSeizeDevice) : IOOptionBits(kIOHIDOptionsTypeNone)
        var status = IOHIDManagerOpen(manager, options)
        if status == kIOReturnSuccess {
            didSeizeSelectedDevice = configuration.suppressVolume
        } else if configuration.suppressVolume {
            logger.error("Could not seize selected DJI HID device, status \(status). Falling back to non-exclusive listen + EventTap")
            options = IOOptionBits(kIOHIDOptionsTypeNone)
            status = IOHIDManagerOpen(manager, options)
            didSeizeSelectedDevice = false
        }

        listeningManager = manager
        logger.info("HID listening manager opened with status \(status), seized \(self.didSeizeSelectedDevice)")
    }

    private func configureEventTap() {
        if let eventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapRunLoopSource, .commonModes)
        }
        eventTapRunLoopSource = nil
        eventTap = nil

        guard configuration.enabled, configuration.suppressVolume else { return }

        let mask = CGEventMask(1 << 14)
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<ExternalTriggerService>.fromOpaque(userInfo).takeUnretainedValue()
                return service.handleEventTap(type: type, event: event)
            },
            userInfo: selfPointer
        ) else {
            logger.error("Could not create event tap")
            return
        }

        eventTap = tap
        eventTapRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let eventTapRunLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), eventTapRunLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        logger.info("Event tap enabled")
    }

    private func handleHIDValue(_ value: IOHIDValue) {
        guard configuration.enabled else { return }
        let element = IOHIDValueGetElement(value)
        guard isMatchedDevice(IOHIDElementGetDevice(element)) else { return }

        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let pressed = IOHIDValueGetIntegerValue(value) != 0
        guard usagePage == kHIDPage_Consumer, usage == kHIDUsage_Csmr_VolumeIncrement, pressed else { return }

        pendingVolumeIncrementAt = CFAbsoluteTimeGetCurrent()
        logger.info("DJI volume_increment received")
        let modifierPressed = configuration.cancelModifierEnabled
            && NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(configuration.cancelModifier.eventFlag)
        if modifierPressed {
            logger.info("DJI modifier click -> cancel")
            onEvent?(ExternalTriggerLastEvent(type: .modifierClickCancel, date: Date(), suppressed: didSeizeSelectedDevice))
            onCancelTrigger?()
        } else {
            onEvent?(ExternalTriggerLastEvent(type: .volumeIncrement, date: Date(), suppressed: didSeizeSelectedDevice))
            triggerPrimary()
        }
    }

    private nonisolated func handleEventTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type.rawValue == 14, isVolumeIncrementSystemEvent(event) else {
            return Unmanaged.passUnretained(event)
        }

        let shouldSuppress = DispatchQueue.main.sync {
            self.configuration.enabled && self.configuration.suppressVolume && self.shouldSuppressVolumeEvent()
        }
        if shouldSuppress {
            DispatchQueue.main.async {
                self.logger.info("Suppressed DJI volume_increment")
                self.onEvent?(ExternalTriggerLastEvent(type: .suppressedVolumeIncrement, date: Date(), suppressed: true))
            }
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    private nonisolated func isVolumeIncrementSystemEvent(_ event: CGEvent) -> Bool {
        guard let nsEvent = NSEvent(cgEvent: event),
              nsEvent.type == .systemDefined,
              nsEvent.subtype.rawValue == 8 else {
            return false
        }
        let data1 = Int64(nsEvent.data1)
        let keyCode = Int((data1 & 0xFFFF0000) >> 16)
        let keyFlags = Int(data1 & 0x0000FFFF)
        let keyState = (keyFlags & 0xFF00) >> 8
        return keyCode == 0 && keyState == 0x0A
    }

    private func shouldSuppressVolumeEvent() -> Bool {
        guard let pendingVolumeIncrementAt else { return false }
        let elapsed = CFAbsoluteTimeGetCurrent() - pendingVolumeIncrementAt
        if elapsed >= 0.0 && elapsed <= 0.15 {
            self.pendingVolumeIncrementAt = nil
            return true
        }
        return false
    }

    private func triggerPrimary() {
        logger.info("DJI single click -> primary dictation action")
        onEvent?(ExternalTriggerLastEvent(type: .singleClick, date: Date(), suppressed: didSeizeSelectedDevice))
        onPrimaryTrigger?()
    }

    private func refreshDevices() {
        var hidDevices: [ExternalTriggerDevice] = []
        if let deviceSet = discoveryManager.flatMap(IOHIDManagerCopyDevices) as? Set<IOHIDDevice> {
            hidDevices = deviceSet.map(deviceInfo).sorted { $0.name < $1.name }
        }
        devices = hidDevices + audioInputDevices()
        logger.info("Discovered \(self.devices.count) external trigger candidate devices")
        publishStatus()
    }

    private func publishStatus() {
        let hasMatchedDevice = devices.contains { $0.sourceType == .hid && $0.isMatched }
        let status: ExternalTriggerStatus
        if !configuration.enabled {
            status = .disabled
        } else if configuration.suppressVolume && !didSeizeSelectedDevice && eventTap == nil {
            status = .permissionMissing
        } else if hasMatchedDevice {
            status = .listening
        } else {
            status = .notDetected
        }
        onDevicesChanged?(devices, status)
    }

    private func isMatchedDevice(_ device: IOHIDDevice?) -> Bool {
        guard let device else { return false }
        let vendorID = integerProperty(kIOHIDVendorIDKey, from: device)
        let productID = integerProperty(kIOHIDProductIDKey, from: device)
        return vendorID == configuration.vendorID && productID == configuration.productID
    }

    private func deviceInfo(_ device: IOHIDDevice) -> ExternalTriggerDevice {
        let vendorID = integerProperty(kIOHIDVendorIDKey, from: device)
        let productID = integerProperty(kIOHIDProductIDKey, from: device)
        return ExternalTriggerDevice(
            name: stringProperty(kIOHIDProductKey, from: device) ?? "Unknown HID Device",
            vendorID: vendorID,
            productID: productID,
            transport: stringProperty(kIOHIDTransportKey, from: device) ?? "-",
            sourceType: .hid,
            isMatched: vendorID == configuration.vendorID && productID == configuration.productID
        )
    }

    private func integerProperty(_ key: String, from device: IOHIDDevice) -> Int? {
        let value = IOHIDDeviceGetProperty(device, key as CFString)
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }

    private func stringProperty(_ key: String, from device: IOHIDDevice) -> String? {
        IOHIDDeviceGetProperty(device, key as CFString) as? String
    }

    private func audioInputDevices() -> [ExternalTriggerDevice] {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        return session.devices.map { device in
            return ExternalTriggerDevice(
                name: device.localizedName,
                vendorID: nil,
                productID: nil,
                transport: device.modelID,
                sourceType: .audioInput,
                isMatched: false
            )
        }
    }
}
