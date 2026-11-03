import AVFAudio
import Darwin
import Foundation
import OSLog
import RealityKit

/// Spatial playback uses public scheduled host time; window playback uses AVAudioPlayer's clock.
@MainActor final class SpeechAudioPlayer: NSObject, SpeechPlaying, AVAudioPlayerDelegate {
    private let target: @MainActor () -> Entity?
    private let session: SpeechAudioSession
    private var activationRequested = false
    private var controller: AudioPlaybackController?
    private var windowPlayer: AVAudioPlayer?
    private var completion: (@MainActor (Bool) -> Void)?
    private var generation: UUID?
    private var startHostTime: UInt64?
    private let logger = Logger(subsystem: "Bina", category: "SpeechAudio")
    private(set) var route = SpeechPlaybackRoute.window

    init(session: SpeechAudioSession? = nil, target: @escaping @MainActor () -> Entity? = { nil }) {
        self.session = session ?? SpeechAudioSession()
        self.target = target
    }

    var currentTime: TimeInterval {
        if let windowPlayer { return windowPlayer.currentTime }
        guard let startHostTime, controller?.isPlaying == true else { return 0 }
        let now = mach_absolute_time()
        return now > startHostTime ? AVAudioTime.seconds(forHostTime: now - startHostTime) : 0
    }

    func play(_ audio: SpeechAudio, finished: @escaping @MainActor (Bool) -> Void) async throws {
        try Task.checkCancellation()
        stop()
        let id = UUID()
        generation = id
        do {
            activationRequested = true
            try await session.activate(recording: false)
            try Task.checkCancellation()
            guard generation == id else { throw CancellationError() }
            completion = finished
            if let entity = target(), entity.isActive {
                route = .character
                let resource = try await AudioFileResource(from: audio.data, configuration: .init(loadingStrategy: .preload))
                try Task.checkCancellation()
                guard generation == id, entity.isActive, target() === entity else { throw CancellationError() }
                let controller = entity.prepareAudio(resource)
                self.controller = controller
                controller.completionHandler = { [weak self] in
                    guard let self, self.generation == id else { return }
                    self.complete(true)
                }
                let time = mach_absolute_time() + AVAudioTime.hostTime(forSeconds: 0.1)
                startHostTime = time
                try controller.play(at: AVAudioTime(hostTime: time))
                // Do not present "speaking" while the resource is still preparing or scheduled.
                let deadline = ProcessInfo.processInfo.systemUptime + 2
                while mach_absolute_time() < time || !controller.isPlaying {
                    try Task.checkCancellation()
                    guard generation == id else { throw CancellationError() }
                    guard ProcessInfo.processInfo.systemUptime < deadline else { throw SpeechFailure.playback }
                    try await Task.sleep(for: .milliseconds(10))
                }
            } else {
                route = .window
                try await session.prepareWindowAudio(audio.data) { [weak self] player in
                    guard let self, self.generation == id else { throw CancellationError() }
                    player.delegate = self
                    self.windowPlayer = player
                    guard player.play() else { throw SpeechFailure.playback }
                }
            }
            try Task.checkCancellation()
            guard generation == id else { throw CancellationError() }
        } catch {
            // A cancelled preparation may finish after a newer play. Never stop that newer generation.
            if generation == id { stop() }
            if error is CancellationError { throw CancellationError() }
            logger.error("Speech playback failed: \(String(describing: error), privacy: .private)")
            throw SpeechFailure.playback
        }
    }

    func stop() {
        generation = nil
        completion = nil
        controller?.completionHandler = nil
        controller?.stop()
        controller = nil
        windowPlayer?.delegate = nil
        windowPlayer?.stop()
        windowPlayer = nil
        startHostTime = nil
        if activationRequested { session.deactivate(); activationRequested = false }
    }

    private func complete(_ success: Bool) {
        let callback = completion
        stop()
        callback?(success)
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self, player] in
            guard let self, self.windowPlayer === player else { return }
            self.complete(flag)
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        audioPlayerDidFinishPlaying(player, successfully: false)
    }
}
