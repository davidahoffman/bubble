import SwiftUI

struct ContentView: View {
    private var store: DocumentStore { DocumentStore.shared }
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if store.sidebarVisible {
                    SidebarView(store: store)
                        .frame(width: 200)
                        .transition(.move(edge: .leading))
                }

                if let doc = store.activeDocument {
                    EditorView(document: doc, store: store)
                        .id(doc.id)
                } else {
                    emptyState
                }
            }

            // Status bar
            if let doc = store.activeDocument {
                StatusBarView(content: doc.content)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.sidebarVisible)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
        }
        .opacity(controlActiveState == .key ? 1.0 : 0.6)
        .animation(.easeInOut(duration: 0.2), value: controlActiveState)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        .onAppear {
            for arg in CommandLine.arguments.dropFirst() {
                let url = URL(fileURLWithPath: arg)
                if FileManager.default.fileExists(atPath: url.path) {
                    store.openURL(url)
                }
            }
            if let delegate = NSApp.delegate as? BubbleAppDelegate {
                for url in delegate.pendingURLs {
                    store.openURL(url)
                }
                delegate.pendingURLs.removeAll()
            }
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak store] event in
                if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                   event.charactersIgnoringModifiers == "w" {
                    if let store = store,
                       store.documents.count <= 1,
                       store.activeDocument?.fileURL == nil,
                       (store.activeDocument?.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        NSApp.keyWindow?.close()
                    } else {
                        BubbleAction.closeTab.post()
                    }
                    return nil
                }
                return event
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: BubbleAction.newDocument.notificationName)) { _ in
            store.newDocument()
        }
        .onReceive(NotificationCenter.default.publisher(for: BubbleAction.openFile.notificationName)) { _ in
            store.openFile()
        }
        .onReceive(NotificationCenter.default.publisher(for: BubbleAction.saveActive.notificationName)) { _ in
            store.saveActive()
        }
        .onReceive(NotificationCenter.default.publisher(for: BubbleAction.closeTab.notificationName)) { _ in
            store.closeActiveTab()
        }
        .onReceive(NotificationCenter.default.publisher(for: BubbleAction.toggleSidebar.notificationName)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                store.sidebarVisible.toggle()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundStyle(.tertiary)
            Text("Open a file to start writing")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("⌘O")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, _ in
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil),
                      ["md", "markdown", "txt"].contains(url.pathExtension.lowercased())
                else { return }
                DispatchQueue.main.async {
                    store.openURL(url)
                }
            }
        }
        return true
    }
}

// MARK: - Status Bar

struct StatusBarView: View {
    let content: String

    private var wordCount: Int {
        content.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    private var charCount: Int {
        content.count
    }

    var body: some View {
        HStack {
            Spacer()
            Text("\(wordCount) words  ·  \(charCount) chars")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .padding(.trailing, 16)
        }
        .frame(height: 22)
        .background(.regularMaterial)
    }
}
