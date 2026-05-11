import Foundation
import Observation

@Observable
class MarkdownDocument: Identifiable {
    let id = UUID()
    var content: String
    var fileURL: URL? { didSet { startWatching() } }
    var isDirty = false
    var customName: String?
    var lastKnownModDate: Date?

    private var fileWatcher: DispatchSourceFileSystemObject?

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
        if fileURL != nil {
            snapshotModDate()
            startWatching()
        }
    }

    deinit {
        fileWatcher?.cancel()
    }

    private func snapshotModDate() {
        guard let url = fileURL else { return }
        lastKnownModDate = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    private func startWatching() {
        fileWatcher?.cancel()
        fileWatcher = nil
        guard let url = fileURL else { return }

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            self?.reloadIfChanged()
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        fileWatcher = source
    }

    func reloadIfChanged() {
        guard let url = fileURL else { return }
        let currentMod = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        if let currentMod, currentMod != lastKnownModDate {
            guard let newContent = try? String(contentsOf: url, encoding: .utf8) else { return }
            if newContent != content {
                content = newContent
                isDirty = false
                lastKnownModDate = currentMod
                NotificationCenter.default.post(name: .documentDidReloadFromDisk, object: self)
            }
        }
    }

    func markJustSaved() {
        snapshotModDate()
    }
}

extension Notification.Name {
    static let documentDidReloadFromDisk = Notification.Name("Bubble.documentDidReloadFromDisk")
}
