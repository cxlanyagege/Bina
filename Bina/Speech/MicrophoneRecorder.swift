import AVFAudio
import Foundation
import OSLog

/// Owns only short-lived capture files. Permission is requested by an explicit recording action.
@MainActor final class MicrophoneRecorder: NSObject, SpeechRecording, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    private var file: URL?
    private var captureFailed = false
    private let session: SpeechAudioSession
    private var generation: UUID?
    private var activationRequested = false
    private let logger = Logger(subsystem: "Bina", category: "MicrophoneCapture")
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BinaVoiceCapture", isDirectory: true)

    init(session: SpeechAudioSession) { self.session = session }

    func requestPermission() async -> Bool { await AVAudioApplication.requestRecordPermission() }

    func start() async throws {
        try Task.checkCancellation()
        try cancel()
        let id = UUID()
        generation = id
        activationRequested = true
        do {
            try await session.activate(recording: true)
            try Task.checkCancellation()
            guard generation == id else { throw CancellationError() }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // Remove only this feature's abandoned recordings after an earlier process exit.
            for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                where url.pathExtension == "wav" { try FileManager.default.removeItem(at: url) }
            let file = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
            self.file = file
            let recorder = try AVAudioRecorder(url: file, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false
            ])
            captureFailed = false
            self.recorder = recorder
            recorder.delegate = self
            guard recorder.prepareToRecord(), recorder.record(forDuration: 30) else { throw SpeechFailure.recording }
        } catch {
            if generation == id { try cancel() }
            if error is CancellationError { throw CancellationError() }
            logger.error("Microphone capture failed: \(String(describing: error), privacy: .private)")
            throw SpeechFailure.recording
        }
    }

    func finish() throws -> Data {
        guard let recorder, let file else { throw SpeechFailure.recording }
        recorder.stop()
        self.recorder = nil
        let data: Data
        do { data = try Data(contentsOf: file) }
        catch { try cancel(); throw SpeechFailure.storage }
        try cancel()
        guard !captureFailed else { throw SpeechFailure.recording }
        return data
    }

    func cancel() throws {
        generation = nil
        recorder?.delegate = nil
        recorder?.stop()
        recorder = nil
        if activationRequested { session.deactivate(); activationRequested = false }
        if let file {
            do {
                if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
                self.file = nil
            } catch {
                logger.error("Capture cleanup failed: \(String(describing: error), privacy: .private)")
                throw SpeechFailure.storage
            }
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: (any Error)?) {
        let message = String(describing: error)
        Task { @MainActor [weak self, recorder] in
            if self?.recorder === recorder {
                self?.captureFailed = true
                self?.logger.error("Capture encoding failed: \(message, privacy: .private)")
            }
        }
    }
}
