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

    // MARK: - Appearance: the palette must resolve per appearance
    // Every MarkdownStyles color used to be a fixed light-mode sRGB value, so dark mode
    // drew near-black body text on a dark window. Colors are now dynamic; these tests
    // resolve them under each appearance and assert the intended relationships.

    private func resolve(_ color: NSColor, in appearanceName: NSAppearance.Name) -> NSColor {
        var resolved = color
        NSAppearance(named: appearanceName)!.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB) ?? color
        }
        return resolved
    }

    private func foregroundColor(in textView: BubbleTextView, at needle: String, file: StaticString = #filePath, line: UInt = #line) -> NSColor? {
        let text = textView.string as NSString
        let location = text.range(of: needle).location
        guard location != NSNotFound, let storage = textView.textStorage else {
            XCTFail("\(needle.debugDescription) not found in document", file: file, line: line)
            return nil
        }
        return storage.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor
    }

    func testBodyTextIsLightInDarkModeAndDarkInLightMode() {
        let textView = makeTextView("plain body text")
        guard let color = foregroundColor(in: textView, at: "plain") else { return }

        XCTAssertGreaterThan(resolve(color, in: .darkAqua).redComponent, 0.7, "dark mode body text must be light")
        XCTAssertLessThan(resolve(color, in: .aqua).redComponent, 0.3, "light mode body text must stay dark")
    }

    func testSyntaxMarkersAreQuieterThanBodyInBothModes() {
        let textView = makeTextView("# Title\n\nbody")
        guard let marker = foregroundColor(in: textView, at: "#"),
              let body = foregroundColor(in: textView, at: "body") else { return }

        // Dark: markers sit below body brightness. Light: markers sit above it (lighter gray).
        XCTAssertLessThan(resolve(marker, in: .darkAqua).redComponent, resolve(body, in: .darkAqua).redComponent)
        XCTAssertGreaterThan(resolve(marker, in: .aqua).redComponent, resolve(body, in: .aqua).redComponent)
    }

    func testCheckedItemIsDimmedButReadableInDarkMode() {
        let textView = makeTextView("- [x] done\n- [ ] open")
        guard let done = foregroundColor(in: textView, at: "done"),
              let open = foregroundColor(in: textView, at: "open") else { return }

        let doneDark = resolve(done, in: .darkAqua).redComponent
        XCTAssertLessThan(doneDark, resolve(open, in: .darkAqua).redComponent, "checked text must be quieter than open items")
        XCTAssertGreaterThan(doneDark, 0.35, "checked text must still be readable on a dark window")
    }

    func testCodeBlockIsFlaggedForRoundedBackground() {
        let textView = makeTextView("before\n```\nlet x = 1\n```\nafter")
        guard let storage = textView.textStorage else { return XCTFail("no storage") }
        let text = textView.string as NSString

        let inside = text.range(of: "let x").location
        let outside = text.range(of: "after").location
        XCTAssertNotNil(storage.attribute(.bubbleCodeBlock, at: inside, effectiveRange: nil), "code block range must carry the marker")
        XCTAssertNil(storage.attribute(.bubbleCodeBlock, at: outside, effectiveRange: nil), "marker must not leak past the block")

        guard let bg = storage.attribute(.backgroundColor, at: inside, effectiveRange: nil) as? NSColor else {
            return XCTFail("code block has no background color")
        }
        XCTAssertLessThan(resolve(bg, in: .darkAqua).redComponent, resolve(bg, in: .aqua).redComponent,
                          "dark mode code block should sit darker than the light-mode block")
    }
}
