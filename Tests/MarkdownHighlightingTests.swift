import AppKit
import XCTest
@testable import Bubble

/// Headless harness for the editor's rendering pipeline.
///
/// Rendering is deterministic on text (visual state = f(document string)), so these
/// tests drive a real BubbleTextView + MarkdownTextStorage without a window: simulate
/// the keypress, then assert on the attributes the highlighter produced.
final class MarkdownHighlightingTests: XCTestCase {

    override class func setUp() {
        super.setUp()
        _ = NSApplication.shared
    }

    // MARK: - Harness

    private func makeTextView(_ content: String) -> BubbleTextView {
        let storage = MarkdownTextStorage()
        let layoutManager = BubbleLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 800, height: 10_000_000))
        layoutManager.addTextContainer(container)
        let textView = BubbleTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), textContainer: container)
        textView.isRichText = false
        textView.allowsUndo = false
        textView.typingAttributes = MarkdownStyles.base
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: content)
        return textView
    }

    private func paragraphStyle(in textView: BubbleTextView, at needle: String, file: StaticString = #filePath, line: UInt = #line) -> NSParagraphStyle? {
        let text = textView.string as NSString
        let location = text.range(of: needle).location
        guard location != NSNotFound, let storage = textView.textStorage else {
            XCTFail("\(needle.debugDescription) not found in document", file: file, line: line)
            return nil
        }
        return storage.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
    }

    private func assertFirstLineIndent(_ textView: BubbleTextView, at needle: String, equals expected: CGFloat, file: StaticString = #filePath, line: UInt = #line) {
        guard let style = paragraphStyle(in: textView, at: needle, file: file, line: line) else { return }
        XCTAssertEqual(style.firstLineHeadIndent, expected,
                       "\(needle.debugDescription) firstLineHeadIndent",
                       file: file, line: line)
    }

    private let doc = "Hello\n\n- [ ] first\n  - [ ] nested\n- [ ] second"

    // MARK: - Regression: Enter near a blank line must not indent the first list item
    // Root cause was \s in the line-anchored highlighter regexes: it matched the
    // blank-line newlines before a marker, inflating indentLevel.

    func testEnterOnBlankLineAboveListDoesNotIndentFirstItem() {
        let textView = makeTextView(doc)
        textView.setSelectedRange(NSRange(location: 6, length: 0)) // on the blank line above the list
        textView.insertNewline(nil)

        XCTAssertTrue(textView.string.hasPrefix("Hello\n\n\n- [ ] first"), "Enter should insert a plain line break")
        assertFirstLineIndent(textView, at: "- [ ] first", equals: 0)
        assertFirstLineIndent(textView, at: "- [ ] nested", equals: 20)
    }

    func testEnterInFrontOfFirstItemDoesNotIndentIt() {
        let textView = makeTextView(doc)
        textView.setSelectedRange(NSRange(location: 7, length: 0)) // start of "- [ ] first"
        textView.insertNewline(nil)

        XCTAssertTrue(textView.string.hasPrefix("Hello\n\n\n- [ ] first"), "Enter should insert a plain line break")
        assertFirstLineIndent(textView, at: "- [ ] first", equals: 0)
    }

    func testEnterAboveNumberedListDoesNotIndentFirstItem() {
        let textView = makeTextView("Hello\n\n1. one\n2. two")
        textView.setSelectedRange(NSRange(location: 6, length: 0))
        textView.insertNewline(nil)

        assertFirstLineIndent(textView, at: "1. one", equals: 0)
    }

    // MARK: - Control: normal documents still style correctly

    func testListIndentLevelsInUntouchedDocument() {
        let textView = makeTextView(doc)

        assertFirstLineIndent(textView, at: "- [ ] first", equals: 0)
        assertFirstLineIndent(textView, at: "- [ ] nested", equals: 20)
        assertFirstLineIndent(textView, at: "- [ ] second", equals: 0)
    }

    func testBlankLineAboveListKeepsDefaultParagraphStyle() {
        let textView = makeTextView(doc)

        guard let storage = textView.textStorage else { return XCTFail("no storage") }
        // Location 6 is the blank line between "Hello" and the list.
        let style = storage.attribute(.paragraphStyle, at: 6, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(style?.firstLineHeadIndent ?? 0, 0, "blank line must not inherit list indentation")
        XCTAssertEqual(style?.headIndent ?? 0, 0, "blank line must not inherit list indentation")
    }
}
