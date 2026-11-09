import Foundation

nonisolated enum MiMoVoice: String, CaseIterable, Identifiable, Sendable {
    case bingtang = "冰糖"
    case moli = "茉莉"
    var id: String { rawValue }
}

nonisolated enum SpeechDelivery: String {
    case notRequested, preparing, playing, played, interrupted, failed
}

enum SpeechFailure: Error, Equatable {
    case permissionDenied, recording, tooShort, tooLong, storage, invalidAudio, emptyTranscript, playback

    var userMessage: String {
        switch self {
        case .permissionDenied: return "未获得麦克风权限。你可以在系统设置中允许访问，或继续使用文字。"
        case .recording: return "无法启动或完成录音，请检查麦克风后重试。"
        case .tooShort: return "录音太短，请按住按钮说完一句话后松开。"
        case .tooLong: return "语音或文本超出首版长度限制，请缩短后重试。"
        case .storage: return "临时录音文件处理失败，请重试；若持续出现，请重新启动应用。"
        case .invalidAudio: return "收到的音频格式无效或超出限制，文字回答仍可阅读。"
        case .emptyTranscript: return "没有识别到有效文字，请重新录音或直接输入。"
        case .playback: return "语音播放失败，文字回答仍可阅读。"
        }
    }

    static func message(_ error: Error) -> String {
        (error as? Self)?.userMessage ?? ConversationFailure.sanitized(error).userMessage
    }
}

@MainActor protocol SpeechRecording {
    func requestPermission() async -> Bool
    func start() async throws
    func finish() throws -> Data
    func cancel() throws
}

@MainActor protocol SpeechServing {
    func transcribe(_ recording: Data, apiKey: String) async throws -> String
    func synthesize(_ text: String, voice: MiMoVoice, affect: DialogueAffect, apiKey: String) async throws -> SpeechAudio
}

enum SpeechPlaybackRoute: String { case character, window }

@MainActor protocol SpeechPlaying {
    var currentTime: TimeInterval { get }
    var route: SpeechPlaybackRoute { get }
    func play(_ audio: SpeechAudio, finished: @escaping @MainActor (Bool) -> Void) async throws
    func stop()
}

@MainActor protocol ConversationObserving: AnyObject {
    func conversationDidInvalidate()
    func conversationDidStartReply(_ id: UUID)
    func conversationDidCompleteReply(_ turn: ConversationTurn)
    func conversationDidFailReply()
}
