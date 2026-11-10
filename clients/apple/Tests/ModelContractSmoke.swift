import Foundation

@main
struct ModelContractSmoke {
    static func main() throws {
        let data = Data("""
        {"models":[
          {"id":"synthetic-a","displayName":"Synthetic A","parameters":[
            {"id":"effort","displayName":"Reasoning","values":[{"value":"quiet"},{"value":"deep"}]},
            {"id":"context","values":[],"customNumber":{"min":100,"max":1000,"step":100}}
          ],"defaultParams":[{"id":"effort","value":"quiet"},{"id":"invented","value":"yes"}]},
          {"id":"synthetic-b","displayName":"Synthetic B","parameters":[
            {"id":"effort","values":[{"value":"other"}]}
          ],"defaultParams":[{"id":"effort","value":"other"}]},
          {"id":"unknown"}
        ],"modelID":"synthetic-a","selections":[]}
        """.utf8)
        let catalog = try JSONDecoder().decode(WatchConfiguration.self, from: data)
        let first = catalog.models[0], second = catalog.models[1], unknown = catalog.models[2]
        precondition(unknown.parameters == nil && unknown.selections([]).isEmpty)
        precondition(first.selections([]) == [ModelSelection(id: "effort", value: "quiet")])
        let saved = [ModelSelection(id: "effort", value: "deep")]
        precondition(first.selections(saved) == saved)
        precondition(second.selections(saved) == [ModelSelection(id: "effort", value: "other")])
        try first.validate(saved)
        try first.validate([ModelSelection(id: "context", value: "500")])
        for invalid in [
            [ModelSelection(id: "effort", value: "invented")],
            [ModelSelection(id: "unknown", value: "quiet")],
            saved + saved,
            [ModelSelection(id: "context", value: "550")],
            [ModelSelection(id: "context", value: "nan")],
            [ModelSelection(id: "context", value: "1100")]
        ] {
            do { try first.validate(invalid); fatalError("Accepted an invalid model selection") }
            catch ModelContractError.changed {}
        }
        let encoded = try JSONEncoder().encode(catalog)
        let decoded = try JSONDecoder().decode(WatchConfiguration.self, from: encoded)
        precondition(decoded.models[0].parameters?[0].values.count == 2)
        print("Model contract smoke passed: discovery, defaults, switches, numeric bounds, invalid/duplicate selections and relay round-trip")
    }
}
