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
    /// The file changed on disk while this document had unsaved edits. Neither
    /// side wins automatically: autosave stops and the user picks a version.
    var hasDiskConflict = false

    private var fileWatcher: DispatchSourceFileSystemObject?
    private var directoryWatcher: DispatchSourceFileSystemObject?
    private var pendingReload: DispatchWorkItem?

    var displayName: String {
        if let url = fileURL {
            return Self.strippingDefaultNamePrefixes(from: url.deletingPathExtension().lastPathComponent)
        }
        if let custom = customName, !custom.isEmpty {
            return custom
        }
        let firstLine = content.components(separatedBy: .newlines).first ?? ""
        let stripped = firstLine.replacingOccurrences(of: "^#+\\s*", with: "", options: .regularExpression)
        let withoutPrefixes = Self.strippingDefaultNamePrefixes(from: stripped)
        let words = withoutPrefixes.split(separator: " ").prefix(3).joined(separator: " ")
        return words.isEmpty ? "Untitled" : String(words)
    }

    private static func strippingDefaultNamePrefixes(from name: String) -> String {
        var stripped = name.replacingOccurrences(
            of: #"^\s*\d{4}[-_.]\d{1,2}[-_.]\d{1,2}(?:[\s_\-–—:]+|$)"#,
            with: "",
            options: .regularExpression
        )
        stripped = stripped.replacingOccurrences(
            of: #"(?i)^\s*david(?:[\s_\-–—:]+|$)"#,
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? name : stripped
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
        stopWatching()
    }

    private func snapshotModDate() {
        guard let url = fileURL else { return }
        lastKnownModDate = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    private func startWatching() {
        stopWatching()
        guard let url = fileURL else { return }
        startDirectoryWatcher(for: url)
        restartFileWatcher(for: url)
    }

    private func stopWatching() {
        pendingReload?.cancel()
        pendingReload = nil
        fileWatcher?.cancel()
        fileWatcher = nil
        directoryWatcher?.cancel()
        directoryWatcher = nil
    }

    private func startDirectoryWatcher(for url: URL) {
        let directoryURL = url.deletingLastPathComponent()
        let fd = open(directoryURL.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            self?.scheduleReload(restartFileWatcher: true)
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        directoryWatcher = source
    }

    private func restartFileWatcher(for url: URL? = nil) {
        fileWatcher?.cancel()
        fileWatcher = nil

        let url = url ?? fileURL
        guard let url else { return }

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            self?.scheduleReload(restartFileWatcher: true)
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        fileWatcher = source
    }

    private func scheduleReload(restartFileWatcher: Bool = false) {
        pendingReload?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.reloadIfChanged()
            if restartFileWatcher {
                self.restartFileWatcher()
            }
        }
        pendingReload = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    func reloadIfChanged() {
        guard let url = fileURL else { return }
        let currentMod = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        guard let currentMod, currentMod != lastKnownModDate else { return }
        guard let newContent = try? String(contentsOf: url, encoding: .utf8) else { return }

        lastKnownModDate = currentMod
        guard newContent != content else { return }
        if isDirty {
            let alreadyConflicted = hasDiskConflict
            hasDiskConflict = true
            if !alreadyConflicted {
                NotificationCenter.default.post(name: .documentDidConflictWithDisk, object: self)
            }
            return
        }
        content = newContent
        NotificationCenter.default.post(name: .documentDidReloadFromDisk, object: self)
    }

    /// Writes the document to its file. Marks it clean only after the write
    /// succeeds, and refuses to overwrite a newer disk version it hasn't seen.
    func write() throws {
        guard let url = fileURL else { throw CocoaError(.fileNoSuchFile) }
        if !hasDiskConflict {
            let diskMod = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
            if let diskMod, let lastKnownModDate, diskMod != lastKnownModDate {
                reloadIfChanged()
            }
        }
        if hasDiskConflict { throw CocoaError(.fileWriteUnknown) }
        try content.write(to: url, atomically: true, encoding: .utf8)
        isDirty = false
        markJustSaved()
    }

    /// Resolves a disk conflict by keeping the in-memory edits (they overwrite the file).
    func keepLocalVersion() throws {
        hasDiskConflict = false
        snapshotModDate()
        try write()
    }

    /// Resolves a disk conflict by discarding in-memory edits for the disk version.
    func useDiskVersion() {
        hasDiskConflict = false
        isDirty = false
        lastKnownModDate = nil
        reloadIfChanged()
    }

    func markJustSaved() {
        snapshotModDate()
        restartFileWatcher()
    }
}

extension Notification.Name {
    static let documentDidReloadFromDisk = Notification.Name("Bubble.documentDidReloadFromDisk")
    static let documentDidConflictWithDisk = Notification.Name("Bubble.documentDidConflictWithDisk")
}
