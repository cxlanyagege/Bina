import Foundation
import Testing
@testable import Bina

@MainActor struct DialogueResponseDecoderTests {
    @Test func everySplitPreservesUnicodeTextWithoutExposingThePrivateHeader() throws {
        let header = "<bina-expression>{\"affect\":\"warm\",\"continuity\":\"new\"}</bina-expression>\n"
        let answer = "晚上好。今天的茶怎么样？🌙\n慢慢说。"
        let response = header + answer
        for offset in 0...response.count {
            let split = response.index(response.startIndex, offsetBy: offset)
            var decoder = DialogueResponseDecoder()
            let first = try decoder.append(String(response[..<split]))
            if offset < header.count { #expect(first.isEmpty) }
            let second = try decoder.append(String(response[split...]))
            #expect(first + second + (try decoder.finish()) == answer)
            #expect(decoder.intent == .init(affect: .warm, continuity: .new))
        }
    }

    @Test func characterSizedChunksAndLeadingWhitespaceHandleCRLF() throws {
        let input = "\u{FEFF} \n <bina-expression>{\"affect\":\"concerned\",\"continuity\":\"continue\"}</bina-expression>\r\n你愿意接着说吗？"
        var decoder = DialogueResponseDecoder()
        var text = ""
        for character in input { text += try decoder.append(String(character)) }
        text += try decoder.finish()
        #expect(text == "你愿意接着说吗？")
        #expect(decoder.intent?.affect == .concerned)
        var splitNewline = DialogueResponseDecoder()
        #expect(try splitNewline.append("<bina-expression>{\n\"affect\":\"warm\",\n\"continuity\":\"new\"\n}</bina-expression>").isEmpty)
        #expect(try splitNewline.append("\r").isEmpty)
        #expect(try splitNewline.append("\n回答") == "回答")
        #expect(splitNewline.intent?.affect == .warm)
    }

    @Test func ordinaryTextStreamsWithoutWaitingForACompleteReply() throws {
        var decoder = DialogueResponseDecoder()
        #expect(try decoder.append("你好，") == "你好，")
        #expect(try decoder.append("<a>只是普通文字</a>") == "<a>只是普通文字</a>")
        #expect(try decoder.finish().isEmpty)
        #expect(decoder.intent == nil)
    }

    @Test func invalidReservedHeadersAreRemovedAndCannotSupplyInstructions() throws {
        for header in [
            #"{"affect":"angry","continuity":"new"}"#,
            #"{"affect":"warm","continuity":"new","action":"move"}"#,
            #"{"affect":"warm","continuity":"resolve"}"#,
            #"{"affect":4,"continuity":"new"}"#,
            "not JSON"
        ] {
            var decoder = DialogueResponseDecoder()
            #expect(try decoder.append("<bina-expression>" + header + "</bina-expression>\n可读回答") == "可读回答")
            #expect(decoder.intent == nil)
        }
        var decoder = DialogueResponseDecoder()
        #expect(try decoder.append("<bina-expression>{}\n回答").isEmpty)
        #expect(throws: ConversationFailure.malformedResponse) { try decoder.finish() }
    }

    @Test func oversizedAndUnfinishedHeadersFailBeforeAnyProtocolIsDisplayed() throws {
        for input in ["<bina", "<bina-expression>{}", "<bina-expression>{}</bina-expression>"] {
            var decoder = DialogueResponseDecoder()
            #expect(try decoder.append(input).isEmpty)
            #expect(throws: ConversationFailure.malformedResponse) { try decoder.finish() }
        }
        for tail in ["", "\nanswer"] {
            var decoder = DialogueResponseDecoder()
            #expect(throws: ConversationFailure.malformedResponse) {
                try decoder.append("<bina-expression>" + String(repeating: "x", count: 513) + tail)
            }
        }
    }
}
