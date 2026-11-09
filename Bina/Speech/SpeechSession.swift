import Foundation
import Observation

/// Coordinates one explicit voice interaction; dialogue and memory retain their existing owners.
@MainActor @Observable final class SpeechSession: ConversationObserving {
    enum Phase: Equatable {
        case idle, permission, recording, transcribing, review, thinking, synthesizing, speaking

        var label: String {
            switch self {
            case .idle: return "等待交谈"
            case .permission: return "等待麦克风权限"
            case .recording: return "正在倾听"
            case .transcribing: return "正在识别"
            case .review: return "请检查识别结果"
            case .thinking: return "正在思考"
            case .synthesizing: return "正在准备语音"
            case .speaking: return "正在说话"
            }
        }

        var cue: CharacterConversationCue {
            switch self {
            case .recording: return .listening
            case .transcribing, .thinking, .synthesizing: return .thinking
            case .speaking: return .speaking
            default: return .idle
            }
        }
    }

    private(set) var phase = Phase.idle { didSet { publishPresentation() } }
    private(set) var voice: MiMoVoice
    private(set) var readTypedReplies: Bool
    private(set) var errorMessage: String?
    private(set) var subtitle = ""
    private(set) var playbackRoute: SpeechPlaybackRoute?
    var transcript = ""
    @ObservationIgnored private let conversation: ConversationModel
    @ObservationIgnored private let recorder: any SpeechRecording
    @ObservationIgnored private let service: any SpeechServing
    @ObservationIgnored private let player: any SpeechPlaying
    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private let present: @MainActor (CharacterConversationPresentation) -> Void
    @ObservationIgnored private let uptime: @MainActor () -> TimeInterval
    @ObservationIgnored private var expressionEnvelope = DialogueExpressionEnvelope()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var limitTask: Task<Void, Never>?
    @ObservationIgnored private var workID: UUID?
    @ObservationIgnored private var workRevision: UUID?
    @ObservationIgnored private var replyID: UUID?
    @ObservationIgnored private var audio: SpeechAudio?
    @ObservationIgnored private var recordingStart: TimeInterval?
    @ObservationIgnored private var spatialAvailable = false
    @ObservationIgnored private var spatialInteraction = false
    @ObservationIgnored private let recordingLimit: Duration

    init(
        conversation: ConversationModel, recorder: (any SpeechRecording)? = nil,
        service: (any SpeechServing)? = nil, player: (any SpeechPlaying)? = nil,
        audioSession: SpeechAudioSession? = nil,
        preferences: UserDefaults = .standard, recordingLimit: Duration = .seconds(30),
        uptime: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        present: @escaping @MainActor (CharacterConversationPresentation) -> Void = { _ in }
    ) {
        self.conversation = conversation
        let audioSession = audioSession ?? SpeechAudioSession()
        self.recorder = recorder ?? MicrophoneRecorder(session: audioSession)
        self.service = service ?? MiMoSpeechService()
        self.player = player ?? SpeechAudioPlayer(session: audioSession)
        self.preferences = preferences
        self.recordingLimit = recordingLimit
        self.present = present
        self.uptime = uptime
        voice = preferences.string(forKey: "speech.voice").flatMap(MiMoVoice.init(rawValue:)) ?? .bingtang
        readTypedReplies = preferences.bool(forKey: "speech.readTypedReplies")
        conversation.observer = self
    }

    var isActive: Bool { phase != .idle }
    var isCapturing: Bool { phase == .permission || phase == .recording }
    var recordedSeconds: Int {
        recordingStart.map { max(0, min(30, Int(ProcessInfo.processInfo.systemUptime - $0))) } ?? 0
    }

    func beginRecording() {
        stop()
        do { _ = try conversation.credentialForSpeech() }
        catch { errorMessage = SpeechFailure.message(error); return }
        let id = beginWork()
        spatialInteraction = spatialAvailable
        phase = .permission
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            guard isCurrent(id) else { return }
            let allowed = await recorder.requestPermission()
            guard isCurrent(id) else { return }
            guard allowed else { fail(SpeechFailure.permissionDenied, id: id); return }
            do {
                try await recorder.start()
                guard isCurrent(id) else { return }
                recordingStart = ProcessInfo.processInfo.systemUptime
                phase = .recording
                limitTask = Task { @MainActor [weak self] in
                    do {
                        try await Task.sleep(for: self?.recordingLimit ?? .seconds(30))
                        guard let self, self.isCurrent(id), self.phase == .recording else { return }
                        self.endRecording()
                    } catch is CancellationError { return }
                    catch { self?.fail(error, id: id) }
                }
            } catch { fail(error, id: id) }
        }
    }

    func endRecording() {
        if phase == .permission { stop(); return }
        guard phase == .recording, let id = workID else { return }
        limitTask?.cancel()
        limitTask = nil
        recordingStart = nil
        do {
            let data = try recorder.finish()
            let key = try conversation.credentialForSpeech()
            phase = .transcribing
            task = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let text = try await service.transcribe(data, apiKey: key)
                    guard isCurrent(id) else { return }
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { throw SpeechFailure.emptyTranscript }
                    guard trimmed.count <= ConversationPrompt.maximumUserCharacters else { throw SpeechFailure.tooLong }
                    transcript = trimmed
                    workID = nil
                    task = nil
                    phase = .review
                } catch { fail(error, id: id) }
            }
        } catch { fail(error, id: id) }
    }

    @discardableResult func sendText(_ text: String) -> Bool { send(text, aloud: readTypedReplies) }
    @discardableResult func sendReviewedTranscript() -> Bool {
        guard phase == .review else { return false }
        return send(transcript, aloud: true)
    }

    func stop() { conversation.cancel() }

    func setVoice(_ voice: MiMoVoice) {
        stop()
        self.voice = voice
        preferences.set(voice.rawValue, forKey: "speech.voice")
    }

    func setReadTypedReplies(_ enabled: Bool) {
        stop()
        readTypedReplies = enabled
        preferences.set(enabled, forKey: "speech.readTypedReplies")
    }

    func audition() {
        stop()
        spatialInteraction = spatialAvailable
        synthesize("你好。今天有什么想和我聊聊的吗？", turnID: nil)
    }

    func conversationDidInvalidate() {
        let played = player.currentTime
        workID = nil
        task?.cancel()
        task = nil
        limitTask?.cancel()
        limitTask = nil
        if let replyID { conversation.setSpeechDelivery(.interrupted, for: replyID, playedSeconds: played) }
        replyID = nil
        player.stop()
        errorMessage = nil
        do { try recorder.cancel() } catch { errorMessage = SpeechFailure.message(error) }
        audio = nil
        expressionEnvelope.clear()
        recordingStart = nil
        transcript = ""
        subtitle = ""
        playbackRoute = nil
        spatialInteraction = false
        phase = .idle
    }

    func conversationDidStartReply(_ id: UUID) { phase = .thinking }

    func conversationDidCompleteReply(_ turn: ConversationTurn) {
        guard replyID == turn.id else {
            expressionEnvelope.show(turn.expression, at: uptime())
            phase = .idle
            return
        }
        synthesize(turn.answer, turnID: turn.id, expression: turn.expression)
    }

    func conversationDidFailReply() {
        if let replyID { conversation.setSpeechDelivery(.failed, for: replyID) }
        replyID = nil
        expressionEnvelope.clear()
        phase = .idle
    }

    /// Called by the scene clock. This never advances audio or invents phoneme timing.
    func updatePresentation(available: Bool) {
        if available, isCapturing || phase == .review || replyID != nil || phase == .speaking {
            spatialInteraction = true
        }
        if spatialAvailable && !available && spatialInteraction { stop() }
        spatialAvailable = available
        publishPresentation(available: available)
    }

    func spaceDidDisappear() {
        if spatialInteraction { stop() }
        spatialAvailable = false
        expressionEnvelope.clear()
        present(.init())
    }

    private func send(_ text: String, aloud: Bool) -> Bool {
        guard let id = conversation.send(text) else { return false }
        if aloud {
            replyID = id
            spatialInteraction = spatialAvailable
            conversation.setSpeechDelivery(.preparing, for: id)
        }
        return true
    }

    private func synthesize(_ text: String, turnID: UUID?, expression: DialogueExpression = .calm) {
        let id = beginWork()
        replyID = turnID
        subtitle = text
        phase = .synthesizing
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let key = try conversation.credentialForSpeech()
                let audio = try await service.synthesize(text, voice: voice, affect: expression.affect, apiKey: key)
                guard isCurrent(id) else { return }
                self.audio = audio
                try await player.play(audio) { [weak self] success in
                    guard let self, self.isCurrent(id) else { return }
                    if let turnID {
                        self.conversation.setSpeechDelivery(success ? .played : .failed, for: turnID,
                            playedSeconds: success ? audio.duration : self.player.currentTime)
                    }
                    self.workID = nil
                    self.replyID = nil
                    self.audio = nil
                    if success { self.expressionEnvelope.release(at: self.uptime()) }
                    else { self.expressionEnvelope.clear() }
                    self.subtitle = ""
                    self.task = nil
                    self.phase = .idle
                    if !success { self.errorMessage = SpeechFailure.playback.userMessage }
                }
                guard isCurrent(id) else { return }
                playbackRoute = player.route
                if let turnID { conversation.setSpeechDelivery(.playing, for: turnID) }
                expressionEnvelope.show(expression, at: uptime(), speaking: true)
                phase = .speaking
            } catch { fail(error, id: id) }
        }
    }

    private func beginWork() -> UUID {
        errorMessage = nil
        let id = UUID()
        workID = id
        workRevision = conversation.memory.revision
        return id
    }

    private func publishPresentation(available: Bool = true) {
        guard available else { present(.init()); return }
        let mouth = phase == .speaking ? audio?.mouthOpenness(at: player.currentTime) ?? 0 : 0
        present(.init(cue: phase.cue, mouth: mouth, expression: expressionEnvelope.sample(at: uptime())))
    }

    private func isCurrent(_ id: UUID) -> Bool {
        workID == id && workRevision == conversation.memory.revision && !Task.isCancelled
    }

    private func fail(_ error: Error, id: UUID) {
        guard workID == id else { return }
        let turn = replyID
        let played = player.currentTime
        conversationDidInvalidate()
        if let turn { conversation.setSpeechDelivery(.failed, for: turn, playedSeconds: played) }
        if !(error is CancellationError) { errorMessage = SpeechFailure.message(error) }
    }
}
