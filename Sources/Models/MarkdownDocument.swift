import Foundation
import Observation

@Observable
class MarkdownDocument: Identifiable {
    let id = UUID()
    var content: String
    var fileURL: URL?
    var isDirty = false
    var customName: String?

    var displayName: String {
        if let url = fileURL {
            return url.deletingPathExtension().lastPathComponent
        }
        if let custom = customName, !custom.isEmpty {
            return custom
        }
        let firstLine = content.components(separatedBy: .newlines).first ?? ""
        let stripped = firstLine.replacingOccurrences(of: "^#+\\s*", with: "", options: .regularExpression)
        let words = stripped.split(separator: " ").prefix(3).joined(separator: " ")
        return words.isEmpty ? "Untitled" : String(words)
    }

    init(content: String = "", fileURL: URL? = nil) {
        self.content = content
        self.fileURL = fileURL
    }
}
