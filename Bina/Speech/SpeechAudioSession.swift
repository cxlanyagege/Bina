import AVFAudio
import Foundation
import OSLog

/// Serializes asynchronous hardware transitions so an old deactivation cannot stop a new capture.
@MainActor final class SpeechAudioSession {
    private let activateOperation: @MainActor (Bool) async throws -> Void
    private let deactivateOperation: @MainActor () async throws -> Void
    private var transition: Task<Void, Error>?
    private let logger = Logger(subsystem: "Bina", category: "SpeechAudioSession")

    init(
        activate: (@MainActor (Bool) async throws -> Void)? = nil,
        deactivate: (@MainActor () async throws -> Void)? = nil
    ) {
        activateOperation = activate ?? { recording in
            // Category changes can also perform synchronous work inside the audio service.
            try await Task.detached {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(recording ? .record : .playback, mode: recording ? .measurement : .default)
                guard try await session.activate(options: []) else { throw SpeechFailure.playback }
            }.value
        }
        deactivateOperation = deactivate ?? {
            try await Task.detached {
                guard try await AVAudioSession.sharedInstance().deactivate(options: .notifyOthersOnDeactivation) else {
                    throw SpeechFailure.playback
                }
            }.value
        }
    }

    func activate(recording: Bool) async throws {
        let operation = activateOperation
        let next = enqueue { try await operation(recording) }
        // Drain activation even if its caller is cancelled. Stop has queued the matching deactivation.
        try await next.value
    }

    func deactivate() {
        let operation = deactivateOperation
        let logger = logger
        _ = enqueue {
            do { try await operation() }
            catch { logger.error("Audio-session deactivation failed: \(String(describing: error), privacy: .private)") }
        }
    }

    /// AVAudioPlayer preloading can activate audio internally. Keep that work off the UI actor
    /// and inside the hardware queue, including cancellation before handing off a prepared player.
    func prepareWindowAudio(_ data: Data, use: @escaping @MainActor (AVAudioPlayer) throws -> Void) async throws {
        let next = enqueue {
            try Task.checkCancellation()
            let player = try await Task.detached {
                let player = try AVAudioPlayer(data: data)
                guard player.prepareToPlay() else { throw SpeechFailure.playback }
                return player
            }.value
            do {
                try Task.checkCancellation()
                try use(player)
            } catch {
                player.stop()
                throw error
            }
        }
        try await withTaskCancellationHandler { try await next.value } onCancel: { next.cancel() }
    }

    private func enqueue(_ operation: @escaping @MainActor () async throws -> Void) -> Task<Void, Error> {
        let previous = transition
        let next = Task { @MainActor in
            // A prior failure is already reported to its caller; it must not poison later recovery.
            if let previous { do { try await previous.value } catch {} }
            try await operation()
        }
        transition = next
        return next
    }

    func waitUntilIdle() async {
        if let transition { do { try await transition.value } catch {} }
    }
}
