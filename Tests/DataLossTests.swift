import AppKit
import XCTest
@testable import Bubble

/// Regressions for edits that could silently lose or corrupt document text.
final class DataLossTests: XCTestCase {

    override class func setUp() {
        super.setUp()
        _ = NSApplication.shared
    }

    private var window: NSWindow?

    override func tearDown() {
        window?.close()
        window = nil
        super.tearDown()
    }

    // MARK: - Harness

    /// A windowed text view so it gets the window's real undo manager.
    private func makeUndoableTextView(_ content: String) -> (BubbleTextView, UndoManager) {
        let storage = MarkdownTextStorage()
        let layoutManager = BubbleLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 800, height: 10_000_000))
        layoutManager.addTextContainer(container)
        let textView = BubbleTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), textContainer: container)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.typingAttributes = MarkdownStyles.base
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: content)

        let window = NSWindow(contentRect: textView.frame, styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = textView
        self.window = window
        let undo = textView.undoManager!
        undo.groupsByEvent = false
        return (textView, undo)
    }

    private func grouped(_ undo: UndoManager, _ action: () -> Void) {
        undo.beginUndoGrouping()
        action()
        undo.endUndoGrouping()
    }

    // MARK: - Undo must not cross a document swap

    func testUndoAfterDocumentSwapDoesNotTouchNewDocument() {
        let (textView, undo) = makeUndoableTextView("")
        grouped(undo) { textView.insertText("typed in document A", replacementRange: textView.selectedRange()) }

        textView.replaceDocumentText("Document B has its own text that must survive")
        XCTAssertFalse(undo.canUndo, "a swapped-in document must start with empty undo history")
        if undo.canUndo { undo.undo() }
        XCTAssertEqual(textView.string, "Document B has its own text that must survive")
    }

    // MARK: - List edits must round-trip through undo

    func testInsertTabOnListUndoesCleanly() {
        let original = "- a\n- b\n- c"
        let (textView, undo) = makeUndoableTextView(original)
        textView.setSelectedRange(NSRange(location: 0, length: (original as NSString).length))
        grouped(undo) { textView.insertTab(nil) }
        XCTAssertEqual(textView.string, "  - a\n  - b\n  - c")
        undo.undo()
        XCTAssertEqual(textView.string, original)
    }

    func testInsertBacktabOnListUndoesCleanly() {
        let original = "  - a\n  - b\ntext"
        let (textView, undo) = makeUndoableTextView(original)
        textView.setSelectedRange(NSRange(location: 0, length: (original as NSString).length))
        grouped(undo) { textView.insertBacktab(nil) }
        XCTAssertEqual(textView.string, "- a\n- b\ntext")
        undo.undo()
        XCTAssertEqual(textView.string, original)
    }

    func testConvertListUndoesCleanly() {
        let original = "1. a\n2. b\n3. c"
        let (textView, undo) = makeUndoableTextView(original)
        let text = original as NSString
        var ranges: [NSRange] = []
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: .byLines) { _, r, _, _ in ranges.append(r) }
        grouped(undo) { textView.convertListLines(ranges, to: .checkbox) }
        XCTAssertEqual(textView.string, "- [ ] a\n- [ ] b\n- [ ] c")
        undo.undo()
        XCTAssertEqual(textView.string, original)
    }
}
