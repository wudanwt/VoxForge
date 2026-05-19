import Carbon
import Foundation

final class CarbonHotkeyCoordinator: HotkeyCoordinator {
    private var toggleRef: EventHotKeyRef?
    private var returnRef: EventHotKeyRef?
    private var cancelRef: EventHotKeyRef?
    private var toggleAction: (() -> Void)?
    private var returnAction: (() -> Void)?
    private var cancelAction: (() -> Void)?
    private var eventHandler: EventHandlerRef?

    @MainActor
    func registerHotkeys(
        dictationHotkey: HotkeyDefinition,
        returnHotkey: HotkeyDefinition,
        cancelHotkey: HotkeyDefinition,
        onToggleDictation: @escaping () -> Void,
        onSendReturn: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> [HotkeyRegistrationResult] {
        toggleAction = onToggleDictation
        returnAction = onSendReturn
        cancelAction = onCancel
        installHandlerIfNeeded()

        var results = [
            registerHotkey(signature: "TYPM", id: 1, target: .dictation, hotkey: dictationHotkey, ref: &toggleRef),
            registerHotkey(signature: "TYPM", id: 2, target: .returnKey, hotkey: returnHotkey, ref: &returnRef)
        ]
        let cancelResult = registerHotkey(signature: "TYPM", id: 3, target: .cancel, hotkey: cancelHotkey, ref: &cancelRef)
        results.append(cancelResult)
        return results
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                let coordinator = Unmanaged<CarbonHotkeyCoordinator>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }

                DispatchQueue.main.async {
                    switch hotKeyID.id {
                    case 1:
                        coordinator.toggleAction?()
                    case 2:
                        coordinator.returnAction?()
                    case 3:
                        coordinator.cancelAction?()
                    default:
                        break
                    }
                }
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &eventHandler
        )
    }

    private func registerHotkey(signature: String, id: UInt32, target: HotkeyTarget, hotkey: HotkeyDefinition, ref: inout EventHotKeyRef?) -> HotkeyRegistrationResult {
        if let ref {
            UnregisterEventHotKey(ref)
        }

        let hotKeyID = EventHotKeyID(signature: signature.ostype, id: id)
        let status = RegisterEventHotKey(hotkey.keyCode, hotkey.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        return HotkeyRegistrationResult(target: target, hotkey: hotkey, status: status)
    }
}
