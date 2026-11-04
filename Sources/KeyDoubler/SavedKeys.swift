import Foundation
import KeyDoublerCore

struct SavedKey: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var profile: String
    var definition: String
    var mode: String
    var combination: String
    var tolerance: String
    var thinHandle: Bool
    var matchHandle: Bool
}

enum SavedKeyStore {
    static var url: URL { Catalog.defaultUserRoot.appendingPathComponent("saved-keys.json") }
    static func load() -> [SavedKey] {
        guard let d = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([SavedKey].self, from: d)) ?? []
    }
    static func save(_ keys: [SavedKey]) {
        try? FileManager.default.createDirectory(at: Catalog.defaultUserRoot, withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(keys) { try? d.write(to: url, options: .atomic) }
    }
}
