import SwiftUI

@main
struct BubbleApp: App {
    @NSApplicationDelegateAdaptor(BubbleAppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 900, height: 700)
        .commands {
            BubbleCommands()
        }
    }
}

class BubbleAppDelegate: NSObject, NSApplicationDelegate {
    var pendingURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleNewWhenNoWindow(_:)),
            name: BubbleAction.newDocument.notificationName, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleOpenWhenNoWindow(_:)),
            name: BubbleAction.openFile.notificationName, object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        DocumentStore.active?.persistSession()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { reopenWindow() }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            openURLFromFinder(url)
        }
        closeExtraWindows()
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        openURLFromFinder(URL(fileURLWithPath: filename))
        closeExtraWindows()
        return true
    }

    private func openURLFromFinder(_ url: URL) {
        if let store = DocumentStore.active {
            store.openURL(url)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            pendingURLs.append(url)
            reopenWindow()
            drainPendingWhenReady()
        }
    }

    private func closeExtraWindows() {
        DispatchQueue.main.async {
            let visible = NSApp.windows.filter { $0.isVisible && $0.canBecomeMain }
            guard visible.count > 1 else { return }
            let keep = visible.last!
            for window in visible where window !== keep {
                window.close()
            }
            keep.makeKeyAndOrderFront(nil)
        }
    }

    private func drainPendingWhenReady() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
            if let store = DocumentStore.active, !pendingURLs.isEmpty {
                for url in pendingURLs { store.openURL(url) }
                pendingURLs.removeAll()
                closeExtraWindows()
            } else if !pendingURLs.isEmpty {
                drainPendingWhenReady()
            }
        }
    }

    @objc private func handleNewWhenNoWindow(_ notification: Notification) {
        if !hasVisibleWindow() { reopenWindow() }
    }

    @objc private func handleOpenWhenNoWindow(_ notification: Notification) {
        if !hasVisibleWindow() { reopenWindow() }
    }

    private func hasVisibleWindow() -> Bool {
        NSApp.windows.contains { $0.isVisible && !$0.className.contains("StatusBar") }
    }

    private func reopenWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if !hasVisibleWindow() {
            NSApp.sendAction(NSSelectorFromString("newWindowForTab:"), to: nil, from: nil)
        }
    }
}
