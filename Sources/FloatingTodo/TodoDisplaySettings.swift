import Foundation
import Combine

final class TodoDisplaySettings: ObservableObject {
    static let defaultsKey = "todoVisibleItemLimit"
    @Published private(set) var limit: Int?
    @Published private(set) var revision = 0
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.integer(forKey: Self.defaultsKey)
        limit = saved > 0 ? saved : nil
    }

    /// Returns false without changing the saved setting when input is invalid.
    @discardableResult func save(_ input: String) -> Bool {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let value: Int?
        if text.isEmpty {
            value = nil
        } else {
            guard text.utf8.allSatisfy({ (48...57).contains($0) }),
                  let number = Int(text), number > 0 else { return false }
            value = number
        }
        if let value {
            defaults.set(value, forKey: Self.defaultsKey)
        } else {
            defaults.removeObject(forKey: Self.defaultsKey)
        }
        limit = value
        revision += 1
        return true
    }

    static func viewportHeight(rowHeights: [CGFloat], limit: Int?) -> CGFloat {
        guard !rowHeights.isEmpty else { return 0 }
        return min(rowHeights.prefix(limit ?? rowHeights.count).reduce(0, +) + 12, 380)
    }
}
