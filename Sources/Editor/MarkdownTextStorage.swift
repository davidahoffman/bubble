import AppKit

class MarkdownTextStorage: NSTextStorage {
    private let backing = NSMutableAttributedString()

    // MARK: - NSTextStorage Primitives

    override var string: String {
        backing.string
    }

    override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
        backing.attributes(at: location, effectiveRange: range)
    }

    override func replaceCharacters(in range: NSRange, with str: String) {
        beginEditing()
        backing.replaceCharacters(in: range, with: str)
        edited(.editedCharacters, range: range, changeInLength: (str as NSString).length - range.length)
        endEditing()
    }

    override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        beginEditing()
        backing.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
        endEditing()
    }

    // MARK: - Syntax Highlighting

    override func processEditing() {
        if editedMask.contains(.editedCharacters) {
            highlightFullDocument()
        }
        super.processEditing()
    }

    private func highlightFullDocument() {
        let range = NSRange(location: 0, length: length)
        guard range.length > 0 else { return }

        let text = string as NSString

        backing.setAttributes(MarkdownStyles.base, range: range)

        applyCodeBlocks(text)
        applyHeadings(text)
        applyBoldItalic(text)
        applyBold(text)
        applyItalic(text)
        applyStrikethrough(text)
        applyHighlight(text)
        applyInlineCode(text)
        applyBlockquotes(text)
        applyBullets(text)
        applyNumberedLists(text)
        applyCheckboxes(text)
        applyTables(text)
        applyHorizontalRules(text)
        applyLinks(text)
    }

    // MARK: - Formatting Rules

    private func applyHeadings(_ text: NSString) {
        enumeratePattern(#"^(#{1,6})\s+(.+)$"#, in: text, options: .anchorsMatchLines) { match in
            let hashRange = match.range(at: 1)
            let level = hashRange.length
            let fullRange = match.range(at: 0)
            let contentRange = match.range(at: 2)

            let font = MarkdownStyles.headingFont(level: level)
            let paraStyle = MarkdownStyles.headingParagraphStyle(level: level)

            backing.addAttribute(.font, value: font, range: fullRange)
            backing.addAttribute(.paragraphStyle, value: paraStyle, range: fullRange)
            backing.addAttribute(.foregroundColor, value: MarkdownStyles.mutedColor, range: hashRange)
            let spaceRange = NSRange(location: hashRange.location + hashRange.length, length: contentRange.location - (hashRange.location + hashRange.length))
            if spaceRange.length > 0 {
                backing.addAttribute(.foregroundColor, value: MarkdownStyles.mutedColor, range: spaceRange)
            }
        }
    }

    // ***bold and italic*** or ___bold and italic___
    private func applyBoldItalic(_ text: NSString) {
        enumeratePattern(#"\*\*\*(.+?)\*\*\*"#, in: text) { match in
            applyBoldItalicMatch(match, delimLen: 3)
        }
        enumeratePattern(#"___(.+?)___"#, in: text) { match in
            applyBoldItalicMatch(match, delimLen: 3)
        }
    }

    private func applyBoldItalicMatch(_ match: NSTextCheckingResult, delimLen: Int) {
        let fullRange = match.range(at: 0)
        let contentRange = match.range(at: 1)

        if let currentFont = backing.attribute(.font, at: contentRange.location, effectiveRange: nil) as? NSFont {
            var font = NSFontManager.shared.convert(currentFont, toHaveTrait: .boldFontMask)
            font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
            backing.addAttribute(.font, value: font, range: contentRange)
        }

        let open = NSRange(location: fullRange.location, length: delimLen)
        let close = NSRange(location: fullRange.location + fullRange.length - delimLen, length: delimLen)
        backing.addAttribute(.foregroundColor, value: MarkdownStyles.mutedColor, range: open)
        backing.addAttribute(.foregroundColor, value: MarkdownStyles.mutedColor, range: close)
    }

    // **bold** or __bold__
    private func applyBold(_ text: NSString) {
        enumeratePattern(#"\*\*(.+?)\*\*"#, in: text) { match in
            applyBoldMatch(match, delimLen: 2)
        }
        enumeratePattern(#"(?<!_)__(?!_)(.+?)(?<!_)__(?!_)"#, in: text) { match in
            applyBoldMatch(match, delimLen: 2)
        }
    }

    private func applyBoldMatch(_ match: NSTextCheckingResult, delimLen: Int) {
        let fullRange = match.range(at: 0)
        let contentRange = match.range(at: 1)

        if let currentFont = backing.attribute(.font, at: contentRange.location, effectiveRange: nil) as? NSFont {
            let bold = NSFontManager.shared.convert(currentFont, toHaveTrait: .boldFontMask)
            backing.addAttribute(.font, value: bold, range: contentRange)
        }

        let open = NSRange(location: fullRange.location, length: delimLen)
        let close = NSRange(location: fullRange.location + fullRange.length - delimLen, length: delimLen)
        backing.addAttribute(.foregroundColor, value: MarkdownStyles.mutedColor, range: open)
        backing.addAttribute(.foregroundColor, value: MarkdownStyles.mutedColor, range: close)
    }

    // *italic* or _italic_
    private func applyItalic(_ text: NSString) {
        enumeratePattern(#"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#, in: text) { match in
            applyItalicMatch(match, delimLen: 1)
        }
        enumeratePattern(#"(?<!_)_(?!_)(.+?)(?<!_)_(?!_)"#, in: text) { match in
            applyItalicMatch(match, delimLen: 1)
        }
    }

    private func applyItalicMatch(_ match: NSTextCheckingResult, delimLen: Int) {
        let fullRange = match.range(at: 0)
        let contentRange = match.range(at: 1)

        if let currentFont = backing.attribute(.font, at: contentRange.location, effectiveRange: nil) as? NSFont {
            let italic = NSFontManager.shared.convert(currentFont, toHaveTrait: .italicFontMask)
            backing.addAttribute(.font, value: italic, range: contentRange)
        }

        let open = NSRange(location: fullRange.location, length: delimLen)
        let close = NSRange(location: fullRange.location + fullRange.length - delimLen, length: delimLen)
        backing.addAttribute(.foregroundColor, value: MarkdownStyles.mutedColor, range: open)
        backing.addAttribute(.foregroundColor, value: MarkdownStyles.mutedColor, range: close)
    }

    // ~~strikethrough~~
    private func applyStrikethrough(_ text: NSString) {
        enumeratePattern(#"~~(.+?)~~"#, in: text) { match in
            let fullRange = match.range(at: 0)
            let contentRange = match.range(at: 1)

            backing.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: contentRange)
            backing.addAttribute(.foregroundColor, value: MarkdownStyles.mutedColor, range: contentRange)

            let open = NSRange(location: fullRange.location, length: 2)
            let close = NSRange(location: fullRange.location + fullRange.length - 2, length: 2)
            backing.addAttribute(.foregroundColor, value: MarkdownStyles.mutedColor, range: open)
            backing.addAttribute(.foregroundColor, value: MarkdownStyles.mutedColor, range: close)
        }
    }

    // ==highlight==
    private func applyHighlight(_ text: NSString) {
        enumeratePattern(#"==(.+?)=="#, in: text) { match in
            let fullRange = match.range(at: 0)
            let contentRange = match.range(at: 1)

            backing.addAttribute(.backgroundColor, value: MarkdownStyles.highlightBackground, range: contentRange)

            let open = NSRange(location: fullRange.location, length: 2)
            let close = NSRange(location: fullRange.location + fullRange.length - 2, length: 2)
            backing.addAttribute(.foregroundColor, value: MarkdownStyles.mutedColor, range: open)
            backing.addAttribute(.foregroundColor, value: MarkdownStyles.mutedColor, range: close)
        }
    }

    private func applyInlineCode(_ text: NSString) {
        enumeratePattern(#"`([^`\n]+)`"#, in: text) { match in
            let fullRange = match.range(at: 0)
            let contentRange = match.range(at: 1)

            backing.addAttribute(.foregroundColor, value: MarkdownStyles.inlineCodeColor, range: contentRange)
            backing.addAttribute(.backgroundColor, value: MarkdownStyles.codeBackground, range: fullRange)

            let open = NSRange(location: fullRange.location, length: 1)
            let close = NSRange(location: fullRange.location + fullRange.length - 1, length: 1)
            backing.addAttribute(.foregroundColor, value: MarkdownStyles.mutedColor, range: open)
            backing.addAttribute(.foregroundColor, value: MarkdownStyles.mutedColor, range: close)
        }
    }

    private func applyCodeBlocks(_ text: NSString) {
        enumeratePattern(#"^(```[^\n]*\n)([\s\S]*?)(```\s*)$"#, in: text, options: .anchorsMatchLines) { match in
            let fullRange = match.range(at: 0)
            let openFence = match.range(at: 1)
            let contentRange = match.range(at: 2)
            let closeFence = match.range(at: 3)

            backing.addAttribute(.backgroundColor, value: MarkdownStyles.codeBlockBackground, range: fullRange)
            backing.addAttribute(.foregroundColor, value: MarkdownStyles.codeBlockText, range: contentRange)
            backing.addAttribute(.foregroundColor, value: MarkdownStyles.codeBlockFence, range: openFence)
            backing.addAttribute(.foregroundColor, value: MarkdownStyles.codeBlockFence, range: closeFence)
        }
    }

    private func applyBlockquotes(_ text: NSString) {
        enumeratePattern(#"^(>)\s+(.+)$"#, in: text, options: .anchorsMatchLines) { match in
            let markerRange = match.range(at: 1)
            let contentRange = match.range(at: 2)
            let fullRange = match.range(at: 0)

            backing.addAttribute(.foregroundColor, value: MarkdownStyles.blockquoteColor, range: contentRange)
            backing.addAttribute(.foregroundColor, value: MarkdownStyles.mutedColor, range: markerRange)

            let style = NSMutableParagraphStyle()
            style.headIndent = 24
            style.firstLineHeadIndent = 24
            style.lineSpacing = 4
            backing.addAttribute(.paragraphStyle, value: style, range: fullRange)
        }
    }

    private func applyBullets(_ text: NSString) {
        enumeratePattern(#"^(\s*)([-*+])\s+"#, in: text, options: .anchorsMatchLines) { match in
            let markerRange = match.range(at: 2)
            let indentRange = match.range(at: 1)
            let indentLevel = indentRange.length / 2 + 1

            backing.addAttribute(.foregroundColor, value: MarkdownStyles.mutedColor, range: markerRange)

            let lineRange = text.lineRange(for: match.range(at: 0))
            let style = NSMutableParagraphStyle()
            style.headIndent = CGFloat(indentLevel) * 20
            style.firstLineHeadIndent = CGFloat(indentLevel - 1) * 20
            style.lineSpacing = 4
            style.paragraphSpacingBefore = 2
            backing.addAttribute(.paragraphStyle, value: style, range: lineRange)
        }
    }

    private func applyNumberedLists(_ text: NSString) {
        enumeratePattern(#"^(\s*)(\d+\.)\s+"#, in: text, options: .anchorsMatchLines) { match in
            let numberRange = match.range(at: 2)
            let indentRange = match.range(at: 1)
            let indentLevel = indentRange.length / 2 + 1

            backing.addAttribute(.foregroundColor, value: MarkdownStyles.mutedColor, range: numberRange)

            let lineRange = text.lineRange(for: match.range(at: 0))
            let style = NSMutableParagraphStyle()
            style.headIndent = CGFloat(indentLevel) * 20
            style.firstLineHeadIndent = CGFloat(indentLevel - 1) * 20
            style.lineSpacing = 4
            style.paragraphSpacingBefore = 2
            backing.addAttribute(.paragraphStyle, value: style, range: lineRange)
        }
    }

    private func applyCheckboxes(_ text: NSString) {
        enumeratePattern(#"^(\s*[-*+]\s+\[)([ xX])(\].*)$"#, in: text, options: .anchorsMatchLines) { match in
            let stateRange = match.range(at: 2)
            let state = text.substring(with: stateRange)
            let isChecked = state.lowercased() == "x"
            let fullRange = match.range(at: 0)
            let prefixRange = match.range(at: 1)

            backing.addAttribute(.foregroundColor, value: MarkdownStyles.mutedColor, range: prefixRange)
            backing.addAttribute(.foregroundColor, value: MarkdownStyles.mutedColor, range: stateRange)

            let bracketAndAfter = match.range(at: 3)
            let bracketRange = NSRange(location: bracketAndAfter.location, length: 1)
            backing.addAttribute(.foregroundColor, value: MarkdownStyles.mutedColor, range: bracketRange)

            if isChecked {
                backing.addAttribute(.foregroundColor, value: MarkdownStyles.checkedColor, range: fullRange)
                if bracketAndAfter.length > 2 {
                    let textRange = NSRange(location: bracketAndAfter.location + 2, length: bracketAndAfter.length - 2)
                    backing.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: textRange)
                    backing.addAttribute(.strikethroughColor, value: MarkdownStyles.checkedColor, range: textRange)
                }
            }
        }
    }

    private func applyTables(_ text: NSString) {
        // Separator rows: mute entirely
        enumeratePattern(#"^\|[-:| ]+\|$"#, in: text, options: .anchorsMatchLines) { match in
            backing.addAttribute(.foregroundColor, value: MarkdownStyles.mutedColor, range: match.range(at: 0))
        }
        // Data rows: just mute the pipes, no background
        enumeratePattern(#"^(\|)(.+?)(\|)$"#, in: text, options: .anchorsMatchLines) { match in
            let fullRange = match.range(at: 0)
            let line = text.substring(with: fullRange)
            if (line as NSString).range(of: "^\\|[-:| ]+\\|$", options: .regularExpression).location != NSNotFound { return }

            var searchRange = fullRange
            while searchRange.length > 0 {
                let pipeRange = text.range(of: "|", range: searchRange)
                if pipeRange.location == NSNotFound { break }
                backing.addAttribute(.foregroundColor, value: MarkdownStyles.mutedColor, range: pipeRange)
                let newLoc = pipeRange.location + 1
                if newLoc >= fullRange.location + fullRange.length { break }
                searchRange = NSRange(location: newLoc, length: fullRange.location + fullRange.length - newLoc)
            }
        }
    }

    private func applyHorizontalRules(_ text: NSString) {
        enumeratePattern(#"^[-*_]{3,}\s*$"#, in: text, options: .anchorsMatchLines) { match in
            backing.addAttribute(.foregroundColor, value: MarkdownStyles.mutedColor, range: match.range(at: 0))
        }
    }

    private func applyLinks(_ text: NSString) {
        enumeratePattern(#"\[([^\]]+)\]\(([^\)]+)\)"#, in: text) { match in
            let fullRange = match.range(at: 0)
            let textRange = match.range(at: 1)

            backing.addAttribute(.foregroundColor, value: MarkdownStyles.linkColor, range: textRange)

            let openBracket = NSRange(location: fullRange.location, length: 1)
            let rest = NSRange(location: textRange.location + textRange.length, length: fullRange.location + fullRange.length - textRange.location - textRange.length)
            backing.addAttribute(.foregroundColor, value: MarkdownStyles.mutedColor, range: openBracket)
            backing.addAttribute(.foregroundColor, value: MarkdownStyles.mutedColor, range: rest)
        }
    }

    // MARK: - Helpers

    private func enumeratePattern(
        _ pattern: String,
        in text: NSString,
        options: NSRegularExpression.Options = [],
        body: (NSTextCheckingResult) -> Void
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        let range = NSRange(location: 0, length: text.length)
        regex.enumerateMatches(in: text as String, range: range) { match, _, _ in
            guard let match = match else { return }
            body(match)
        }
    }
}

// MARK: - Rounded Background Layout Manager

class BubbleLayoutManager: NSLayoutManager {
    override func fillBackgroundRectArray(_ rectArray: UnsafePointer<NSRect>, count rectCount: Int, forCharacterRange charRange: NSRange, color: NSColor) {
        guard rectCount > 0, textStorage != nil else {
            super.fillBackgroundRectArray(rectArray, count: rectCount, forCharacterRange: charRange, color: color)
            return
        }

        let isCodeBlock = color == MarkdownStyles.codeBlockBackground

        if isCodeBlock {
            // Union all rects, add padding, draw with rounded corners
            var union = rectArray[0]
            for i in 1..<rectCount {
                union = union.union(rectArray[i])
            }

            // Expand to full text container width and add vertical padding
            if let tc = textContainers.first {
                let fullWidth = tc.containerSize.width - tc.lineFragmentPadding * 2
                union.origin.x = tc.lineFragmentPadding
                union.size.width = fullWidth
            }
            let padded = union.insetBy(dx: -12, dy: -8)
            let path = NSBezierPath(roundedRect: padded, xRadius: 8, yRadius: 8)
            color.setFill()
            path.fill()
        } else {
            super.fillBackgroundRectArray(rectArray, count: rectCount, forCharacterRange: charRange, color: color)
        }
    }
}
