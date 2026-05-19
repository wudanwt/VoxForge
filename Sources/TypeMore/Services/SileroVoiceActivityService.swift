import Foundation

final class SileroVoiceActivityService: VoiceActivityService, @unchecked Sendable {
    let configuration: VoiceActivityConfiguration

    private let lock = NSLock()
    private var speechSamples = 0
    private var trailingSilenceSamples = 0
    private var hasDetectedSpeech = false
    private var lastSampleRate: Double = 16_000

    init(configuration: VoiceActivityConfiguration = VoiceActivityConfiguration()) {
        self.configuration = configuration
    }

    func reset() {
        lock.withLock {
            speechSamples = 0
            trailingSilenceSamples = 0
            hasDetectedSpeech = false
            lastSampleRate = 16_000
        }
    }

    func accept(samples: [Float], sampleRate: Double) -> VoiceActivityDecision {
        guard !samples.isEmpty else {
            return currentDecision(sampleRate: sampleRate, shouldFinalizeSegment: false)
        }

        let rms = rootMeanSquare(samples)
        let active = rms >= configuration.activationThreshold
        return lock.withLock {
            lastSampleRate = sampleRate
            if active {
                hasDetectedSpeech = true
                speechSamples += samples.count
                trailingSilenceSamples = 0
            } else if hasDetectedSpeech {
                trailingSilenceSamples += samples.count
            }

            let speechDuration = Double(speechSamples) / sampleRate
            let silenceDuration = Double(trailingSilenceSamples) / sampleRate
            let shouldFinalize = hasDetectedSpeech &&
                speechDuration >= configuration.minimumSpeechDuration &&
                (silenceDuration >= configuration.silenceEndDuration ||
                 speechDuration >= configuration.maximumSegmentDuration)

            return VoiceActivityDecision(
                hasSpeech: hasDetectedSpeech,
                shouldFinalizeSegment: shouldFinalize,
                speechDuration: speechDuration,
                trailingSilenceDuration: silenceDuration
            )
        }
    }

    private func currentDecision(sampleRate: Double, shouldFinalizeSegment: Bool) -> VoiceActivityDecision {
        lock.withLock {
            let rate = sampleRate > 0 ? sampleRate : lastSampleRate
            return VoiceActivityDecision(
                hasSpeech: hasDetectedSpeech,
                shouldFinalizeSegment: shouldFinalizeSegment,
                speechDuration: Double(speechSamples) / rate,
                trailingSilenceDuration: Double(trailingSilenceSamples) / rate
            )
        }
    }

    private func rootMeanSquare(_ samples: [Float]) -> Float {
        let meanSquare = samples.reduce(Float.zero) { partial, sample in
            partial + sample * sample
        } / Float(samples.count)
        return sqrt(meanSquare)
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
