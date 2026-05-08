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
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return }
        let doc = documents[index]
        if doc.isDirty { save(doc) }

        documents.remove(at: index)

        if activeDocumentID == id {
            activeDocumentID = documents.last?.id
        }

        if documents.isEmpty {
            newDocument()
        }
    }

    // MARK: - Save

    func save(_ document: MarkdownDocument) {
        guard let url = document.fileURL else {
            saveAs(document)
            return
        }
        try? document.content.write(to: url, atomically: true, encoding: .utf8)
        document.isDirty = false
    }

    func saveAs(_ document: MarkdownDocument) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]

        let baseName = document.displayName
        let fileName = baseName.hasSuffix(".md") ? baseName : "\(baseName).md"
        panel.nameFieldStringValue = fileName

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            document.fileURL = url
            self?.save(document)
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
            try? FileManager.default.moveItem(at: oldURL, to: newURL)
            doc.fileURL = newURL
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
        for doc in documents where doc.isDirty && doc.fileURL != nil {
            save(doc)
        }
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
