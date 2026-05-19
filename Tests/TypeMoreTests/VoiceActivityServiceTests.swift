import XCTest
@testable import TypeMore

final class VoiceActivityServiceTests: XCTestCase {
    func testSilenceDoesNotTriggerSpeech() {
        let service = SileroVoiceActivityService()
        let decision = service.accept(samples: Array(repeating: 0, count: 16_000), sampleRate: 16_000)

        XCTAssertFalse(decision.hasSpeech)
        XCTAssertFalse(decision.shouldFinalizeSegment)
        XCTAssertEqual(decision.speechDuration, 0, accuracy: 0.001)
    }

    func testSpeechThenConfiguredSilenceFinalizesSegment() {
        let service = SileroVoiceActivityService()
        _ = service.accept(samples: Array(repeating: 0.05, count: 8_000), sampleRate: 16_000)
        let decision = service.accept(samples: Array(repeating: 0, count: 11_200), sampleRate: 16_000)

        XCTAssertTrue(decision.hasSpeech)
        XCTAssertTrue(decision.shouldFinalizeSegment)
        XCTAssertEqual(decision.speechDuration, 0.5, accuracy: 0.001)
        XCTAssertEqual(decision.trailingSilenceDuration, 0.7, accuracy: 0.001)
    }

    func testShortSpeechDoesNotFinalizeEvenAfterSilence() {
        let service = SileroVoiceActivityService()
        _ = service.accept(samples: Array(repeating: 0.05, count: 4_000), sampleRate: 16_000)
        let decision = service.accept(samples: Array(repeating: 0, count: 16_000), sampleRate: 16_000)

        XCTAssertTrue(decision.hasSpeech)
        XCTAssertFalse(decision.shouldFinalizeSegment)
        XCTAssertEqual(decision.speechDuration, 0.25, accuracy: 0.001)
    }

    func testResetClearsSpeechState() {
        let service = SileroVoiceActivityService()
        _ = service.accept(samples: Array(repeating: 0.05, count: 8_000), sampleRate: 16_000)
        service.reset()

        let decision = service.accept(samples: Array(repeating: 0, count: 16_000), sampleRate: 16_000)
        XCTAssertFalse(decision.hasSpeech)
        XCTAssertFalse(decision.shouldFinalizeSegment)
    }
}
