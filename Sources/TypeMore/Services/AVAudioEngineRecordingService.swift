import AVFoundation
import Foundation

final class AVAudioEngineRecordingService: AudioRecordingService {
    private let engine = AVAudioEngine()
    private var startDate: Date?
    private var sampleRate: Double = 0
    private var samplesRecorded = 0
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    private var recordingError: Error?

    func startRecording() throws {
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let fileURL = try makeRecordingURL()
        let settings = format.settings
        audioFile = try AVAudioFile(forWriting: fileURL, settings: settings)
        recordingURL = fileURL
        recordingError = nil
        sampleRate = format.sampleRate
        samplesRecorded = 0

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.samplesRecorded += Int(buffer.frameLength)
            do {
                try self.audioFile?.write(from: buffer)
            } catch {
                self.recordingError = error
            }
        }

        engine.prepare()
        try engine.start()
        startDate = Date()
    }

    func stopRecording() throws -> RecordedAudio {
        guard engine.isRunning, let startDate else {
            throw TypeMoreError.recordingNotActive
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioFile = nil

        if let recordingError {
            throw recordingError
        }

        guard let recordingURL else {
            throw TypeMoreError.recordingFileMissing
        }

        return RecordedAudio(
            fileURL: recordingURL,
            duration: Date().timeIntervalSince(startDate),
            sampleRate: sampleRate,
            samplesRecorded: samplesRecorded
        )
    }

    private func makeRecordingURL() throws -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = baseURL.appendingPathComponent("TypeMore/Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("current.wav")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        return url
    }
}
