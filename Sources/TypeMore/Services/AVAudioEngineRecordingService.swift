import AVFoundation
import Foundation

final class AVAudioEngineRecordingService: AudioRecordingService {
    private let engine = AVAudioEngine()
    private let audioStateQueue = DispatchQueue(label: "VoxForge.AVAudioEngineRecordingService.state")
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
        let newAudioFile = try AVAudioFile(forWriting: fileURL, settings: settings)
        audioStateQueue.sync {
            audioFile = newAudioFile
            recordingURL = fileURL
            recordingError = nil
            sampleRate = format.sampleRate
            samplesRecorded = 0
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.audioStateQueue.async { [weak self] in
                guard let self else { return }
                self.samplesRecorded += Int(buffer.frameLength)
                do {
                    try self.audioFile?.write(from: buffer)
                } catch {
                    self.recordingError = error
                }
            }
        }

        engine.prepare()
        try engine.start()
        let startedAt = Date()
        audioStateQueue.sync {
            startDate = startedAt
        }
    }

    func stopRecording() throws -> RecordedAudio {
        let currentStartDate = audioStateQueue.sync { startDate }
        guard engine.isRunning, let currentStartDate else {
            throw TypeMoreError.recordingNotActive
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        return try audioStateQueue.sync {
            let error = recordingError
            let url = recordingURL
            let summary = RecordedAudio(
                fileURL: url ?? URL(fileURLWithPath: ""),
                duration: Date().timeIntervalSince(currentStartDate),
                sampleRate: sampleRate,
                samplesRecorded: samplesRecorded
            )
            audioFile = nil
            if let error {
                throw error
            }
            guard url != nil else {
                throw TypeMoreError.recordingFileMissing
            }
            return summary
        }
    }

    private func makeRecordingURL() throws -> URL {
        let directory = AppDirectories.applicationSupport(appending: "TypeMore/Recordings")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("current.wav")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        return url
    }
}
