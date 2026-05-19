import Foundation
import XCTest
@testable import TypeMore

final class SherpaModelManagerTests: XCTestCase {
    func testModelManagerReportsMissingModelUntilRequiredFilesExist() throws {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TypeMoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseURL) }

        let spec = SherpaModelSpec(
            directoryName: "model",
            archiveURL: URL(string: "https://example.com/model.tar.bz2")!,
            encoderName: "encoder.int8.onnx",
            decoderName: "decoder.int8.onnx",
            tokensName: "tokens.txt"
        )
        let manager = SherpaModelManager(spec: spec, baseDirectory: baseURL)

        XCTAssertEqual(manager.status(), .missingModel)
        XCTAssertNil(manager.pathsIfPresent())

        let modelDirectory = baseURL.appendingPathComponent("model", isDirectory: true)
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        try Data([0]).write(to: modelDirectory.appendingPathComponent("encoder.int8.onnx"))
        try Data([0]).write(to: modelDirectory.appendingPathComponent("decoder.int8.onnx"))
        try Data("a 1\n".utf8).write(to: modelDirectory.appendingPathComponent("tokens.txt"))

        XCTAssertEqual(manager.status(), .ready(""))
        XCTAssertNotNil(manager.pathsIfPresent())
    }
}
