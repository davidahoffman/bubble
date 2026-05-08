import SwiftUI

enum BubbleAction: String {
    case newDocument, openFile, saveActive, closeTab, toggleSidebar
    var notificationName: Notification.Name { .init("Bubble.\(rawValue)") }
    func post() { NotificationCenter.default.post(name: notificationName, object: nil) }
}

struct BubbleCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New") { BubbleAction.newDocument.post() }
                .keyboardShortcut("n")
            Button("New Tab") { BubbleAction.newDocument.post() }
                .keyboardShortcut("t")
            Button("Open...") { BubbleAction.openFile.post() }
                .keyboardShortcut("o")
            Divider()
            Button("Save") { BubbleAction.saveActive.post() }
                .keyboardShortcut("s")
        }

        CommandGroup(replacing: .sidebar) {
            Button("Toggle Sidebar") { BubbleAction.toggleSidebar.post() }
                .keyboardShortcut("0", modifiers: .command)
        }

        CommandGroup(replacing: .help) {}
        CommandGroup(replacing: .toolbar) {}

        CommandGroup(replacing: .windowArrangement) {}
    }
}
