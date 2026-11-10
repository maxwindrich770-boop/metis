import Foundation

// The authenticated /api/models response is the only source of choices.
struct ModelSelection: Codable, Equatable {
    let id: String
    let value: String
}

struct ModelParameter: Codable, Identifiable {
    struct Value: Codable { let value: String; let displayName: String? }
    struct NumberRange: Codable { let min: Double; let max: Double; let step: Double }
    let id: String
    let displayName: String?
    let values: [Value]
    let customNumber: NumberRange?
    var title: String { displayName ?? id }

    func accepts(_ value: String) -> Bool {
        if values.contains(where: { $0.value == value }) { return true }
        guard let range = customNumber, let number = Double(value), number.isFinite,
              range.min.isFinite, range.max.isFinite, range.step.isFinite, range.step > 0,
              number >= range.min, number <= range.max else { return false }
        let steps = (number - range.min) / range.step
        return abs(steps - steps.rounded()) < 0.000001
    }
}

struct MetisModel: Codable, Identifiable {
    let id: String
    let legacyIds: [String]?
    let displayName: String?
    let name: String?
    let label: String?
    let connectionLabel: String?
    let parameters: [ModelParameter]?
    let defaultParams: [ModelSelection]?
    var title: String { displayName ?? label ?? name ?? id }

    // Revalidate defaults and persisted selections on every model switch.
    func selections(_ saved: [ModelSelection]) -> [ModelSelection] {
        (parameters ?? []).compactMap { parameter in
            if let value = saved.last(where: { $0.id == parameter.id }), parameter.accepts(value.value) { return value }
            return defaultParams?.first(where: { $0.id == parameter.id && parameter.accepts($0.value) })
        }
    }

    func validate(_ selections: [ModelSelection]) throws {
        var seen = Set<String>()
        for selection in selections {
            guard seen.insert(selection.id).inserted,
                  let parameter = parameters?.first(where: { $0.id == selection.id }),
                  parameter.accepts(selection.value) else { throw ModelContractError.changed }
        }
    }
}

enum ModelContractError: LocalizedError {
    case changed
    var errorDescription: String? { "Model options changed. Refresh and select again." }
}

struct WatchConfiguration: Codable {
    let models: [MetisModel]
    let modelID: String?
    let selections: [ModelSelection]
    let nextOffset: Int?
}

struct WatchTranscript: Codable {
    struct Message: Codable, Identifiable {
        let id: String
        let role: String
        let content: String
    }
    let messages: [Message]
    let status: String
}
