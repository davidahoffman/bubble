import AppKit
import Observation
import UniformTypeIdentifiers

@Observable
class DocumentStore {
    static let shared = DocumentStore()
    static var active: DocumentStore? { shared }

    var documents: [MarkdownDocument] = []
    var activeDocumentID: UUID?
    var sidebarVisible = true

    private var autoSaveWork: DispatchWorkItem?

    private static let sessionFile: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("Bubble", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("session.json")
    }()

    var activeDocument: MarkdownDocument? {
        documents.first { $0.id == activeDocumentID }
    }

    private init() {
        if !restoreSession() {
            let doc = MarkdownDocument()
            documents.append(doc)
            activeDocumentID = doc.id
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.saveAllDirty()
            self?.persistSession()
        }

        NotificationCenter.default.addObserver(
            forName: .documentDidConflictWithDisk,
            object: nil, queue: .main
        ) { [weak self] notif in
            guard let doc = notif.object as? MarkdownDocument else { return }
            self?.resolveDiskConflict(doc)
        }
    }

    // MARK: - Document Management

    func newDocument() {
        let doc = MarkdownDocument()
        documents.append(doc)
        activeDocumentID = doc.id
    }

    func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md"),
            UTType(filenameExtension: "markdown"),
            .plainText,
        ].compactMap { $0 }
        panel.allowsMultipleSelection = true
        panel.allowsOtherFileTypes = true

        panel.begin { [weak self] response in
            guard response == .OK else { return }
            for url in panel.urls {
                self?.openURL(url)
            }
        }
    }

    func openURL(_ url: URL) {
        if let existing = documents.first(where: { $0.fileURL == url }) {
            activeDocumentID = existing.id
            return
        }

        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        let doc = MarkdownDocument(content: content, fileURL: url)

        removeBlankUntitled()

        documents.append(doc)
        activeDocumentID = doc.id
    }

    func closeDocument(_ id: UUID) {
        guard let doc = documents.first(where: { $0.id == id }) else { return }
        guard doc.isDirty else { removeDocument(id); return }

        if doc.fileURL != nil {
            if save(doc) || confirmDiscard(doc, reason: doc.hasDiskConflict ? "The file changed on disk." : "Bubble couldn't save it.") { removeDocument(id) }
            return
        }

        // Untitled with edits: the tab stays until the user saves or explicitly discards.
        if doc.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { removeDocument(id); return }
        let alert = NSAlert()
        alert.messageText = "Save changes to \u{201C}\(doc.displayName)\u{201D}?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save…")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Don't Save")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            saveAs(doc) { [weak self] saved in
                if saved { self?.removeDocument(id) }
            }
        case .alertThirdButtonReturn:
            removeDocument(id)
        default:
            break
        }
    }

    private func removeDocument(_ id: UUID) {
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return }
        documents.remove(at: index)

        if activeDocumentID == id {
            activeDocumentID = documents.last?.id
        }

        if documents.isEmpty {
            newDocument()
        }
    }

    // MARK: - Save

    /// Returns true only when the edits are on disk. A failure leaves the
    /// document dirty; `interactive` decides whether the user hears about it.
    @discardableResult
    func save(_ document: MarkdownDocument, interactive: Bool = true) -> Bool {
        guard document.fileURL != nil else {
            if interactive { saveAs(document) }
            return false
        }
        do {
            try document.write()
            return true
        } catch {
            if interactive && !document.hasDiskConflict {
                showError("Couldn't save \u{201C}\(document.displayName)\u{201D}", error)
            }
            return false
        }
    }

    func saveAs(_ document: MarkdownDocument, completion: ((Bool) -> Void)? = nil) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]

        let baseName = document.displayName
        let fileName = baseName.hasSuffix(".md") ? baseName : "\(baseName).md"
        panel.nameFieldStringValue = fileName

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { completion?(false); return }
            let previousURL = document.fileURL
            document.fileURL = url
            // The user just chose this path (and confirmed any overwrite), so
            // it isn't a conflict with an older disk version.
            document.hasDiskConflict = false
            document.lastKnownModDate = nil
            let saved = self.save(document)
            if !saved { document.fileURL = previousURL }
            completion?(saved)
        }
    }

    func saveActive() {
        guard let doc = activeDocument else { return }
        save(doc)
    }

    func closeActiveTab() {
        guard let id = activeDocumentID else { return }
        closeDocument(id)
    }

    func renameDocument(_ id: UUID, to newName: String) {
        guard let doc = documents.first(where: { $0.id == id }) else { return }
        if let oldURL = doc.fileURL {
            let fileName = newName.hasSuffix(".md") ? newName : "\(newName).md"
            let newURL = oldURL.deletingLastPathComponent().appendingPathComponent(fileName)
            guard newURL != oldURL else { return }
            do {
                // Fails if newURL exists — never repoint at someone else's file.
                try FileManager.default.moveItem(at: oldURL, to: newURL)
                doc.fileURL = newURL
            } catch {
                showError("Couldn't rename to \u{201C}\(fileName)\u{201D}", error)
            }
        } else {
            doc.customName = newName
        }
    }

    func moveDocument(from source: IndexSet, to destination: Int) {
        documents.move(fromOffsets: source, toOffset: destination)
    }

    func scheduleAutoSave() {
        autoSaveWork?.cancel()
        autoSaveWork = DispatchWorkItem { [weak self] in
            self?.saveAllDirty()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: autoSaveWork!)
    }

    // MARK: - Private

    private func saveAllDirty() {
        for doc in documents where doc.isDirty && doc.fileURL != nil && !doc.hasDiskConflict {
            save(doc, interactive: false)
        }
    }

    /// Documents whose edits would be lost if the app quit now.
    func unsavedDocumentsBeforeQuit() -> [MarkdownDocument] {
        saveAllDirty()
        return documents.filter { doc in
            doc.isDirty && !(doc.fileURL == nil && doc.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func resolveDiskConflict(_ doc: MarkdownDocument) {
        guard doc.hasDiskConflict, documents.contains(where: { $0.id == doc.id }) else { return }
        let alert = NSAlert()
        alert.messageText = "\u{201C}\(doc.displayName)\u{201D} changed on disk"
        alert.informativeText = "Another app changed this file while you had unsaved edits. Which version do you want to keep?"
        alert.addButton(withTitle: "Keep My Edits")
        alert.addButton(withTitle: "Use Disk Version")
        if alert.runModal() == .alertFirstButtonReturn {
            do { try doc.keepLocalVersion() } catch { showError("Couldn't save \u{201C}\(doc.displayName)\u{201D}", error) }
        } else {
            doc.useDiskVersion()
        }
    }

    private func confirmDiscard(_ doc: MarkdownDocument, reason: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Close \u{201C}\(doc.displayName)\u{201D} without saving?"
        alert.informativeText = "\(reason) Your unsaved changes will be lost."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Close Anyway")
        return alert.runModal() == .alertSecondButtonReturn
    }

    private func showError(_ message: String, _ error: Error) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    private func removeBlankUntitled() {
        documents.removeAll { doc in
            doc.fileURL == nil && doc.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    // MARK: - Session Persistence

    func persistSession() {
        let paths = documents.compactMap { $0.fileURL?.path }
        let activeIndex = documents.firstIndex(where: { $0.id == activeDocumentID }) ?? 0
        let session: [String: Any] = ["paths": paths, "active": activeIndex]
        if let data = try? JSONSerialization.data(withJSONObject: session) {
            try? data.write(to: Self.sessionFile)
        }
    }

    private func restoreSession() -> Bool {
        guard let data = try? Data(contentsOf: Self.sessionFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let paths = json["paths"] as? [String],
              !paths.isEmpty
        else { return false }

        let activeIndex = json["active"] as? Int ?? 0
        var restored: [MarkdownDocument] = []

        for path in paths {
            let url = URL(fileURLWithPath: path)
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            restored.append(MarkdownDocument(content: content, fileURL: url))
        }

        guard !restored.isEmpty else { return false }

        documents = restored
        let idx = min(activeIndex, restored.count - 1)
        activeDocumentID = restored[idx].id
        return true
    }
}
