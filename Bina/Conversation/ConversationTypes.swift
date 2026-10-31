import Foundation

enum MiMoModel: String, CaseIterable, Identifiable {
    case flash = "mimo-v2.6-flash"
    case pro = "mimo-v2.6-pro"

    var id: String { rawValue }
    var displayName: String { self == .flash ? "MiMo V2.6 Flash" : "MiMo V2.6 Pro" }
}

struct ChatMessage: Encodable, Equatable {
    enum Role: String, Encodable { case system, user, assistant }
    let role: Role
    let content: String
}

struct ConversationRequest {
    enum Purpose { case dialogue, memoryExtraction }
    let model: MiMoModel
    let messages: [ChatMessage]
    let purpose: Purpose
}

struct ConversationUsage: Equatable {
    let inputTokens: Int
    let outputTokens: Int
    let cachedInputTokens: Int
}

enum ConversationEvent {
    case text(String)
    case usage(ConversationUsage)
}

@MainActor
protocol ConversationServing {
    func stream(_ request: ConversationRequest, apiKey: String) -> AsyncThrowingStream<ConversationEvent, Error>
}

struct ConversationTurn: Identifiable {
    enum State: Equatable { case receiving, complete, interrupted, failed }
    let id: UUID
    let userText: String
    let createdAt: Date
    var answer = ""
    var state: State = .receiving
    var usage: ConversationUsage?
    var firstContentLatency: Double?
}

enum ConversationFailure: Error, Equatable {
    case invalidKey
    case authentication
    case accessDenied
    case balance
    case modelUnavailable
    case rateLimited
    case server
    case timeout
    case network
    case malformedResponse
    case incompleteResponse
    case emptyResponse
    case outputLimit
    case policyRejection
    case providerRejected
    case unsupportedOutput

    var userMessage: String {
        switch self {
        case .invalidKey: return "请输入普通按量 API 的有效 sk- 密钥，不能使用 Token Plan 密钥。"
        case .authentication: return "MiMo 未通过密钥验证，请检查设置中的 API Key。"
        case .accessDenied: return "MiMo 拒绝了这次访问，请检查账号和模型权限。"
        case .balance: return "MiMo 账户余额不足或计费不可用，请检查控制台。"
        case .modelUnavailable: return "所选 MiMo 模型暂不可用，请检查权限或切换模型。"
        case .rateLimited: return "MiMo 请求过于频繁，请稍后再试。"
        case .server: return "MiMo 服务暂时异常，请稍后再试。"
        case .timeout: return "等待 MiMo 响应超时，请检查网络后重试。"
        case .network: return "无法连接 MiMo，请检查网络后重试。"
        case .malformedResponse: return "MiMo 返回了无法解析的数据，本次结果未作为完整对话使用。"
        case .incompleteResponse: return "连接提前结束，回答尚未完成。"
        case .emptyResponse: return "MiMo 没有返回可显示的回答，请重试。"
        case .outputLimit: return "回答达到长度限制，当前内容不完整。请缩短问题后重试。"
        case .policyRejection: return "MiMo 未能处理这次内容，请调整表达后重试。"
        case .providerRejected: return "MiMo 返回了服务错误，本次请求未完成。请检查控制台后重试。"
        case .unsupportedOutput: return "MiMo 返回了首版暂不支持的输出，本次未执行任何动作。"
        }
    }

    static func forHTTPStatus(_ status: Int) -> Self? {
        switch status {
        case 200: return nil
        case 401: return .authentication
        case 402: return .balance
        case 403: return .accessDenied
        case 404: return .modelUnavailable
        case 429: return .rateLimited
        case 500...599: return .server
        default: return .malformedResponse
        }
    }

    static func sanitized(_ error: Error) -> Self {
        if let failure = error as? Self { return failure }
        if let error = error as? URLError, error.code == .timedOut { return .timeout }
        return .network
    }
}
