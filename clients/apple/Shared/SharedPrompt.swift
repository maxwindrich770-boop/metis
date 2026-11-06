import Foundation

enum SharedPrompt {
    enum ShareError: LocalizedError {
        case unavailable
        case occupied

        var errorDescription: String? {
            switch self {
            case .unavailable: return "This build does not have access to the Metis App Group."
            case .occupied: return "Open Metis to review the existing shared draft first."
            }
        }
    }

    private static func location() throws -> URL {
        guard var id = Bundle.main.bundleIdentifier else { throw ShareError.unavailable }
        if Bundle.main.bundleURL.pathExtension == "appex", id.hasSuffix(".share") { id.removeLast(6) }
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group." + id) else {
            throw ShareError.unavailable
        }
        return container.appendingPathComponent("shared-prompt.txt")
    }

    static func save(_ text: String) throws {
        let url = try location()
        let pending = url.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: pending) }
        try Data(text.utf8).write(to: pending, options: .completeFileProtection)
        do { try FileManager.default.linkItem(at: pending, to: url) }
        catch let error as CocoaError where error.code == .fileWriteFileExists { throw ShareError.occupied }
    }

    static func take() -> String? {
        guard let url = try? location(),
              let data = try? Data(contentsOf: url), data.count <= 64_000,
              let text = String(data: data, encoding: .utf8),
              !text.isEmpty else { return nil }
        do { try FileManager.default.removeItem(at: url) }
        catch { return nil }
        return text
    }
}
