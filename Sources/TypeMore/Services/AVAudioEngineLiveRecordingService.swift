import AVFoundation
import Foundation

final class AVAudioEngineLiveRecordingService: LiveAudioRecordingService {
    private let engine = AVAudioEngine()
    private let diagnosticsRecorder: DiagnosticsRecorder
    private let targetSampleRate: Double = 16_000
    private var targetFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var startDate: Date?
    private var samplesRecorded = 0
    private var didLogFirstBuffer = false
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    private var recordingError: Error?
    private var onSamples: (@Sendable ([Float], Double) -> Void)?

    init(diagnosticsRecorder: DiagnosticsRecorder = DiagnosticsRecorder()) {
        self.diagnosticsRecorder = diagnosticsRecorder
    }

    func startStreaming(
        keepDebugFile: Bool,
        onSamples: @escaping @Sendable ([Float], Double) -> Void
    ) throws {
        if engine.isRunning {
            diagnosticsRecorder.record(DiagnosticEvent(
                category: .audio,
                phase: "streaming_audio.stop_existing_engine",
                audio: audioSnapshot(engineWasRunning: true)
            ))
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        diagnosticsRecorder.record(DiagnosticEvent(
            category: .audio,
            phase: "streaming_audio.start_requested",
            audio: audioSnapshot(inputFormat: inputFormat, engineWasRunning: engine.isRunning),
            details: ["keepDebugFile": String(keepDebugFile)]
        ))
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw TypeMoreError.audioConversionUnavailable
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw TypeMoreError.audioConversionUnavailable
        }

        self.targetFormat = targetFormat
        self.converter = converter
        self.onSamples = onSamples
        samplesRecorded = 0
        didLogFirstBuffer = false
        recordingError = nil
        recordingURL = nil
        audioFile = nil

        if keepDebugFile {
            let url = try makeRecordingURL()
            audioFile = try AVAudioFile(forWriting: url, settings: targetFormat.settings)
            recordingURL = url
        }

        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            self?.handleIncomingBuffer(buffer)
        }

        engine.prepare()
        try engine.start()
        startDate = Date()
        diagnosticsRecorder.record(DiagnosticEvent(
            category: .audio,
            phase: "streaming_audio.started",
            audio: audioSnapshot(inputFormat: inputFormat, engineWasRunning: engine.isRunning),
            debugAudioPath: recordingURL?.path
        ))
    }

    func stopStreaming() throws -> LiveRecordingSummary {
        guard engine.isRunning, let startDate else {
            diagnosticsRecorder.record(DiagnosticEvent(
                category: .audio,
                phase: "streaming_audio.stop_failed",
                error: TypeMoreError.recordingNotActive.localizedDescription,
                audio: audioSnapshot(engineWasRunning: engine.isRunning),
                samplesRecorded: samplesRecorded,
                debugAudioPath: recordingURL?.path
            ))
            throw TypeMoreError.recordingNotActive
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioFile = nil
        converter = nil
        onSamples = nil

        if let recordingError {
            diagnosticsRecorder.record(DiagnosticEvent(
                category: .audio,
                phase: "streaming_audio.recording_error",
                error: recordingError.localizedDescription,
                samplesRecorded: samplesRecorded,
                debugAudioPath: recordingURL?.path
            ))
            throw recordingError
        }

        diagnosticsRecorder.record(DiagnosticEvent(
            category: .audio,
            phase: "streaming_audio.stopped",
            durationMs: Int(Date().timeIntervalSince(startDate) * 1000),
            samplesRecorded: samplesRecorded,
            debugAudioPath: recordingURL?.path
        ))

        return LiveRecordingSummary(
            fileURL: recordingURL,
            duration: Date().timeIntervalSince(startDate),
            sampleRate: targetSampleRate,
            samplesRecorded: samplesRecorded
        )
    }

    private func handleIncomingBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let converted = convert(buffer) else { return }
        samplesRecorded += Int(converted.frameLength)
        if !didLogFirstBuffer {
            didLogFirstBuffer = true
            diagnosticsRecorder.record(DiagnosticEvent(
                category: .audio,
                phase: "streaming_audio.first_buffer",
                audio: audioSnapshot(inputFormat: buffer.format, engineWasRunning: engine.isRunning),
                samplesRecorded: samplesRecorded,
                debugAudioPath: recordingURL?.path
            ))
        }

        if let audioFile {
            do {
                try audioFile.write(from: converted)
            } catch {
                recordingError = error
                diagnosticsRecorder.record(DiagnosticEvent(
                    category: .audio,
                    phase: "streaming_audio.write_failed",
                    error: error.localizedDescription,
                    samplesRecorded: samplesRecorded,
                    debugAudioPath: recordingURL?.path
                ))
            }
        }

        guard let channel = converted.floatChannelData?[0] else { return }
        let count = Int(converted.frameLength)
        guard count > 0 else { return }
        let samples = Array(UnsafeBufferPointer(start: channel, count: count))
        onSamples?(samples, targetSampleRate)
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter, let targetFormat else { return nil }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 512
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            return nil
        }

        var didProvideInput = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
            if didProvideInput {
                outStatus.pointee = .noDataNow
                return nil
            }
            didProvideInput = true
            outStatus.pointee = .haveData
            return buffer
        }

        if status == .error {
            recordingError = conversionError
            return nil
        }

        return output
    }

    private func makeRecordingURL() throws -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = baseURL.appendingPathComponent("TypeMore/Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("current-stream.wav")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func audioSnapshot(inputFormat: AVAudioFormat? = nil, engineWasRunning: Bool) -> DiagnosticAudioSnapshot {
        let device = AVCaptureDevice.default(for: .audio)
        let format = inputFormat ?? engine.inputNode.outputFormat(forBus: 0)
        return DiagnosticAudioSnapshot(
            inputName: device?.localizedName,
            inputUID: device?.uniqueID,
            sampleRate: format.sampleRate,
            channelCount: Int(format.channelCount),
            engineWasRunning: engineWasRunning
        )
    }
}
