// Compiled only in Debug Simulator builds. No server/session or live tools.
#if DEBUG && targetEnvironment(simulator)
import Foundation

enum WatchPreviewFixture {
    static func reply(_ message: [String: Any]) throws -> [String: Any] {
        let chat = ["id": "synthetic-chat", "title": "Watch preview", "status": "idle", "attention": "no"]
        switch message["action"] as? String {
        case "chats": return ["chats": [chat]]
        case "create": return ["chat": chat]
        case "configuration":
            return ["configuration": Data("""
            {"models":[{"id":"synthetic-watch","displayName":"Preview model","connectionLabel":"Synthetic account",
            "parameters":[{"id":"effort","displayName":"Reasoning","values":[{"value":"quiet","displayName":"Quiet"},{"value":"deep","displayName":"Deep"}]},
            {"id":"fast","displayName":"Fast mode","values":[{"value":"off","displayName":"Off"},{"value":"on","displayName":"On"}]}],
            "defaultParams":[{"id":"effort","value":"quiet"},{"id":"fast","value":"off"}]},
            {"id":"synthetic-second","displayName":"Second preview model","parameters":[]}],
            "modelID":"synthetic-watch","selections":[{"id":"effort","value":"deep"}]}
            """.utf8)]
        case "transcript":
            return ["transcript": try JSONEncoder().encode(WatchTranscript(messages: [
                .init(id: "sample-user", role: "user", content: "Show the latest chat."),
                .init(id: "sample-answer", role: "assistant", content: "Synthetic preview. You can select a model, change its options, and compose a prompt.")
            ], status: "idle"))]
        case "pending": return ["pending": [String: String]()]
        case "prompt": return ["jobId": "synthetic-preview-only"]
        case "open": return ["opened": true]
        default: throw ModelContractError.changed
        }
    }
}
#endif
