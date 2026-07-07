import Foundation

func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    message: String,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            let nanoseconds = UInt64(max(0, seconds) * 1_000_000_000)
            try await Task.sleep(nanoseconds: nanoseconds)
            throw TypeMoreError.operationTimedOut(message)
        }

        guard let value = try await group.next() else {
            throw TypeMoreError.operationTimedOut(message)
        }
        group.cancelAll()
        return value
    }
}
