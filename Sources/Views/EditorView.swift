import AppKit
import SwiftUI

struct EditorView: NSViewRepresentable {
    var document: MarkdownDocument
    var store: DocumentStore

    func makeCoordinator() -> Coordinator {
        Coordinator(document: document, store: store)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textStorage = MarkdownTextStorage()
        let layoutManager = BubbleLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer()
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = BubbleTextView(frame: .zero, textContainer: textContainer)
        textView.font = MarkdownStyles.baseFont
        textView.textColor = MarkdownStyles.textColor
        textView.insertionPointColor = MarkdownStyles.textColor
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 60, height: 20)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.delegate = context.coordinator
        textView.typingAttributes = MarkdownStyles.base

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        if !document.content.isEmpty {
            textStorage.replaceCharacters(in: NSRange(location: 0, length: 0), with: document.content)
        }

        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView

        scrollView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrollViewFrameChanged(_:)),
            name: NSView.frameDidChangeNotification,
            object: scrollView
        )

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
            context.coordinator.updateInsets()
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coord = context.coordinator
        coord.store = store

        if document.id != coord.document.id {
            coord.document = document
            if let textView = coord.textView {
                let newContent = document.content
                coord.isSwapping = true
                textView.string = newContent
                if let storage = textView.textStorage as? MarkdownTextStorage {
                    storage.beginEditing()
                    storage.edited(.editedCharacters, range: NSRange(location: 0, length: (newContent as NSString).length), changeInLength: 0)
                    storage.endEditing()
                }
                coord.isSwapping = false
                textView.setSelectedRange(NSRange(location: 0, length: 0))
                textView.scrollToBeginningOfDocument(nil)
                textView.window?.makeFirstResponder(textView)
            }
        } else {
            coord.document = document
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        var document: MarkdownDocument
        var store: DocumentStore
        var textView: BubbleTextView?
        var scrollView: NSScrollView?
        var isSwapping = false

        init(document: MarkdownDocument, store: DocumentStore) {
            self.document = document
            self.store = store
        }

        func textDidChange(_ notification: Notification) {
            guard !isSwapping, let textView = notification.object as? NSTextView else { return }
            document.content = textView.string
            document.isDirty = true
            store.scheduleAutoSave()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = textView else { return }
            textView.updateListSwitcher()
        }

        @objc func scrollViewFrameChanged(_ notification: Notification) {
            updateInsets()
        }

        func updateInsets() {
            guard let scrollView = scrollView, let textView = textView else { return }
            let availableWidth = scrollView.bounds.width
            let maxWidth = MarkdownStyles.maxContentWidth
            let horizontal = max(60, (availableWidth - maxWidth) / 2)
            textView.textContainerInset = NSSize(width: horizontal, height: 20)
        }
    }
}

// MARK: - BubbleTextView

class BubbleTextView: NSTextView {

    private var listSwitcher: ListSwitcherPanel?

    // MARK: - Key Equivalents

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers {
        case "w":
            BubbleAction.closeTab.post()
            return true
        case "b":
            toggleMarkdownWrap("**")
            return true
        case "i":
            toggleMarkdownWrap("*")
            return true
        case "k":
            insertMarkdownLink()
            return true
        case "f":
            let item = NSMenuItem()
            item.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
            performFindPanelAction(item)
            return true
        case "g":
            let item = NSMenuItem()
            item.tag = event.modifierFlags.contains(.shift)
                ? Int(NSFindPanelAction.previous.rawValue)
                : Int(NSFindPanelAction.next.rawValue)
            performFindPanelAction(item)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    // MARK: - Inline Formatting (Cmd+B, Cmd+I)

    private func toggleMarkdownWrap(_ delimiter: String) {
        guard let storage = textStorage else { return }
        let sel = selectedRange()
        let text = storage.string as NSString
        let dLen = (delimiter as NSString).length

        if sel.length > 0 {
            let before = sel.location >= dLen ? text.substring(with: NSRange(location: sel.location - dLen, length: dLen)) : ""
            let after = (sel.location + sel.length + dLen <= text.length) ? text.substring(with: NSRange(location: sel.location + sel.length, length: dLen)) : ""

            if before == delimiter && after == delimiter {
                let fullRange = NSRange(location: sel.location - dLen, length: sel.length + dLen * 2)
                let inner = text.substring(with: sel)
                if shouldChangeText(in: fullRange, replacementString: inner) {
                    storage.replaceCharacters(in: fullRange, with: inner)
                    didChangeText()
                    setSelectedRange(NSRange(location: sel.location - dLen, length: sel.length))
                }
            } else {
                let selected = text.substring(with: sel)
                let wrapped = "\(delimiter)\(selected)\(delimiter)"
                if shouldChangeText(in: sel, replacementString: wrapped) {
                    storage.replaceCharacters(in: sel, with: wrapped)
                    didChangeText()
                    setSelectedRange(NSRange(location: sel.location + dLen, length: sel.length))
                }
            }
        } else {
            let insert = "\(delimiter)\(delimiter)"
            if shouldChangeText(in: sel, replacementString: insert) {
                storage.replaceCharacters(in: sel, with: insert)
                didChangeText()
                setSelectedRange(NSRange(location: sel.location + dLen, length: 0))
            }
        }
    }

    private func insertMarkdownLink() {
        guard let storage = textStorage else { return }
        let sel = selectedRange()
        let text = storage.string as NSString

        if sel.length > 0 {
            let selected = text.substring(with: sel)
            let link = "[\(selected)](url)"
            if shouldChangeText(in: sel, replacementString: link) {
                storage.replaceCharacters(in: sel, with: link)
                didChangeText()
                let urlStart = sel.location + (selected as NSString).length + 2
                setSelectedRange(NSRange(location: urlStart, length: 3))
            }
        } else {
            let link = "[](url)"
            if shouldChangeText(in: sel, replacementString: link) {
                storage.replaceCharacters(in: sel, with: link)
                didChangeText()
                setSelectedRange(NSRange(location: sel.location + 1, length: 0))
            }
        }
    }

    // MARK: - Tab / Shift+Tab to Indent/Outdent Lists

    override func insertTab(_ sender: Any?) {
        guard let storage = textStorage else { super.insertTab(sender); return }
        let text = storage.string as NSString
        let sel = selectedRange()
        let linesRange = text.lineRange(for: sel)

        let listRegex = try! NSRegularExpression(pattern: #"^(\s*)([-*+]|\d+\.)\s+"#)
        var anyList = false
        text.enumerateSubstrings(in: linesRange, options: .byLines) { line, _, _, _ in
            guard let line = line else { return }
            if listRegex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil {
                anyList = true
            }
        }

        guard anyList else { super.insertTab(sender); return }

        var lineStarts: [Int] = []
        text.enumerateSubstrings(in: linesRange, options: .byLines) { line, lineRange, _, _ in
            guard let line = line else { return }
            if listRegex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil {
                lineStarts.append(lineRange.location)
            }
        }

        if shouldChangeText(in: linesRange, replacementString: text.substring(with: linesRange)) {
            for start in lineStarts.reversed() {
                storage.replaceCharacters(in: NSRange(location: start, length: 0), with: "  ")
            }
            didChangeText()
            let newSel = NSRange(location: sel.location + 2, length: sel.length + (lineStarts.count - 1) * 2)
            setSelectedRange(newSel)
        }
    }

    override func insertBacktab(_ sender: Any?) {
        guard let storage = textStorage else { super.insertBacktab(sender); return }
        let text = storage.string as NSString
        let sel = selectedRange()
        let linesRange = text.lineRange(for: sel)

        let listRegex = try! NSRegularExpression(pattern: #"^(\s{2,})([-*+](\s+\[[ xX]\])?\s+|\d+\.\s+)"#)
        var lineStarts: [Int] = []
        text.enumerateSubstrings(in: linesRange, options: .byLines) { line, lineRange, _, _ in
            guard let line = line else { return }
            if listRegex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil {
                lineStarts.append(lineRange.location)
            }
        }

        guard !lineStarts.isEmpty else { super.insertBacktab(sender); return }

        if shouldChangeText(in: linesRange, replacementString: text.substring(with: linesRange)) {
            for start in lineStarts.reversed() {
                storage.replaceCharacters(in: NSRange(location: start, length: 2), with: "")
            }
            didChangeText()
            let newStart = max(linesRange.location, sel.location - 2)
            let newLen = max(0, sel.length - (lineStarts.count - 1) * 2)
            setSelectedRange(NSRange(location: newStart, length: newLen))
        }
    }

    // MARK: - Newline Handling (continue lists)

    override func insertNewline(_ sender: Any?) {
        guard let storage = textStorage else {
            super.insertNewline(sender)
            return
        }

        let text = storage.string as NSString
        let cursorLocation = selectedRange().location
        let lineRange = text.lineRange(for: NSRange(location: cursorLocation, length: 0))
        let line = text.substring(with: lineRange).trimmingCharacters(in: .newlines)

        if let continuation = listContinuation(for: line) {
            if continuation.isEmpty {
                let replaceRange = NSRange(location: lineRange.location, length: (line as NSString).length)
                if shouldChangeText(in: replaceRange, replacementString: "") {
                    storage.replaceCharacters(in: replaceRange, with: "")
                    didChangeText()
                }
            } else {
                super.insertNewline(sender)
                let insertRange = selectedRange()
                if shouldChangeText(in: insertRange, replacementString: continuation) {
                    storage.replaceCharacters(in: insertRange, with: continuation)
                    didChangeText()
                    setSelectedRange(NSRange(location: insertRange.location + (continuation as NSString).length, length: 0))
                }
            }
        } else {
            super.insertNewline(sender)
        }

        typingAttributes = MarkdownStyles.base
    }

    private func listContinuation(for line: String) -> String? {
        let ns = line as NSString

        if let match = try? NSRegularExpression(pattern: #"^(\s*)([-*+])\s+\[[ xX]\]\s+"#).firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
            let indent = ns.substring(with: match.range(at: 1))
            let marker = ns.substring(with: match.range(at: 2))
            let content = ns.substring(from: match.range.location + match.range.length)
            if content.trimmingCharacters(in: .whitespaces).isEmpty { return "" }
            return "\(indent)\(marker) [ ] "
        }

        if let match = try? NSRegularExpression(pattern: #"^(\s*)([-*+])\s+"#).firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
            let indent = ns.substring(with: match.range(at: 1))
            let marker = ns.substring(with: match.range(at: 2))
            let content = ns.substring(from: match.range.location + match.range.length)
            if content.trimmingCharacters(in: .whitespaces).isEmpty { return "" }
            return "\(indent)\(marker) "
        }

        if let match = try? NSRegularExpression(pattern: #"^(\s*)(\d+)\.\s+"#).firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
            let indent = ns.substring(with: match.range(at: 1))
            let numStr = ns.substring(with: match.range(at: 2))
            let content = ns.substring(from: match.range.location + match.range.length)
            if content.trimmingCharacters(in: .whitespaces).isEmpty { return "" }
            let next = (Int(numStr) ?? 0) + 1
            return "\(indent)\(next). "
        }

        return nil
    }

    // MARK: - Mouse Handling

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let origin = textContainerOrigin
        let containerPoint = NSPoint(x: point.x - origin.x, y: point.y - origin.y)

        guard let lm = layoutManager, let tc = textContainer else {
            super.mouseDown(with: event)
            return
        }

        var fraction: CGFloat = 0
        let index = lm.characterIndex(for: containerPoint, in: tc, fractionOfDistanceBetweenInsertionPoints: &fraction)

        if event.modifierFlags.contains(.command) {
            if openLinkAtIndex(index) { return }
        }

        if toggleCheckbox(at: index) { return }

        super.mouseDown(with: event)
    }

    private func openLinkAtIndex(_ index: Int) -> Bool {
        guard let storage = textStorage, index < storage.length else { return false }
        let text = storage.string as NSString
        let searchStart = max(0, index - 500)
        let searchEnd = min(text.length, index + 500)
        let searchRange = NSRange(location: searchStart, length: searchEnd - searchStart)

        guard let regex = try? NSRegularExpression(pattern: #"\[([^\]]+)\]\(([^\)]+)\)"#) else { return false }
        var opened = false
        regex.enumerateMatches(in: text as String, range: searchRange) { match, _, stop in
            guard let match = match else { return }
            if NSLocationInRange(index, match.range(at: 1)) || NSLocationInRange(index, match.range(at: 2)) {
                let urlString = text.substring(with: match.range(at: 2))
                if let url = URL(string: urlString) {
                    NSWorkspace.shared.open(url)
                    opened = true
                    stop.pointee = true
                }
            }
        }
        return opened
    }

    private func toggleCheckbox(at index: Int) -> Bool {
        guard let storage = textStorage, index < storage.length else { return false }
        let text = storage.string as NSString
        let lineRange = text.lineRange(for: NSRange(location: index, length: 0))
        let line = text.substring(with: lineRange)

        guard let regex = try? NSRegularExpression(pattern: #"^(\s*[-*+]\s+\[)([ xX])(\])"#),
              let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length))
        else { return false }

        let checkCharOffset = match.range(at: 2).location
        let globalCheckRange = NSRange(location: lineRange.location + checkCharOffset, length: 1)

        let openBracket = lineRange.location + match.range(at: 1).location + match.range(at: 1).length - 1
        let closeBracket = lineRange.location + match.range(at: 3).location + match.range(at: 3).length

        guard index >= openBracket && index <= closeBracket else { return false }

        let current = text.substring(with: globalCheckRange)
        let replacement = (current == " ") ? "x" : " "

        if shouldChangeText(in: globalCheckRange, replacementString: replacement) {
            storage.replaceCharacters(in: globalCheckRange, with: replacement)
            didChangeText()
        }
        return true
    }

    // MARK: - Paste Link Auto-Format

    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general

        // Strip duplicate list prefix when pasting a list item onto an auto-continued line
        if let text = pb.string(forType: .string),
           let storage = textStorage {
            let listPattern = #"^(\s*)([-*+]( \[[ xX]\])?|\d+\.)\s+"#
            let pastedHasPrefix = text.range(of: listPattern, options: .regularExpression) != nil
            if pastedHasPrefix {
                let nsText = storage.string as NSString
                let cursor = selectedRange().location
                let lineRange = nsText.lineRange(for: NSRange(location: cursor, length: 0))
                let lineUpToCursor = nsText.substring(with: NSRange(location: lineRange.location, length: cursor - lineRange.location))
                let lineIsEmptyPrefix = lineUpToCursor.range(of: #"^\s*([-*+]( \[[ xX]\])?|\d+\.)\s*$"#, options: .regularExpression) != nil
                if lineIsEmptyPrefix {
                    let replaceRange = NSRange(location: lineRange.location, length: cursor - lineRange.location)
                    if shouldChangeText(in: replaceRange, replacementString: "") {
                        storage.replaceCharacters(in: replaceRange, with: "")
                        didChangeText()
                    }
                    super.paste(sender)
                    return
                }
            }
        }

        if let urlString = pb.string(forType: .URL) ?? pb.string(forType: .string),
           let url = URL(string: urlString),
           url.scheme != nil,
           (urlString.hasPrefix("http://") || urlString.hasPrefix("https://"))
        {
            let sel = selectedRange()
            let selectedText: String
            if sel.length > 0, let storage = textStorage {
                selectedText = (storage.string as NSString).substring(with: sel)
            } else {
                selectedText = ""
            }

            let markdown: String
            let cursorOffset: Int
            if selectedText.isEmpty {
                markdown = "[](\(urlString))"
                cursorOffset = 1
            } else {
                markdown = "[\(selectedText)](\(urlString))"
                cursorOffset = markdown.count
            }

            if shouldChangeText(in: sel, replacementString: markdown) {
                textStorage?.replaceCharacters(in: sel, with: markdown)
                didChangeText()
                setSelectedRange(NSRange(location: sel.location + cursorOffset, length: 0))
            }
            return
        }
        // Strip base64 data URIs from pasted markdown before inserting
        if let text = pb.string(forType: .string),
           text.contains("data:image/") {
            let stripped = text.replacingOccurrences(
                of: #"!\[([^\]]*)\]\(data:image/[^)]+\)"#,
                with: "![$1]()",
                options: .regularExpression
            )
            if stripped != text {
                let sel = selectedRange()
                if shouldChangeText(in: sel, replacementString: stripped) {
                    textStorage?.replaceCharacters(in: sel, with: stripped)
                    didChangeText()
                    setSelectedRange(NSRange(location: sel.location + stripped.count, length: 0))
                }
                return
            }
        }

        super.paste(sender)
    }

    // MARK: - List Switcher

    enum ListType { case bullet, numbered, checkbox }

    func updateListSwitcher() {
        guard let storage = textStorage else { hideListSwitcher(); return }
        let sel = selectedRange()
        guard sel.length > 0 else { hideListSwitcher(); return }

        let text = storage.string as NSString
        let selRange = text.lineRange(for: sel)
        var lines: [(range: NSRange, type: ListType)] = []

        text.enumerateSubstrings(in: selRange, options: .byLines) { line, lineRange, _, _ in
            guard let line = line else { return }
            let ns = line as NSString
            let r = NSRange(location: 0, length: ns.length)
            if (try? NSRegularExpression(pattern: #"^\s*[-*+]\s+\[[ xX]\]\s+"#))?.firstMatch(in: line, range: r) != nil {
                lines.append((lineRange, .checkbox))
            } else if (try? NSRegularExpression(pattern: #"^\s*[-*+]\s+"#))?.firstMatch(in: line, range: r) != nil {
                lines.append((lineRange, .bullet))
            } else if (try? NSRegularExpression(pattern: #"^\s*\d+\.\s+"#))?.firstMatch(in: line, range: r) != nil {
                lines.append((lineRange, .numbered))
            }
        }

        guard lines.count >= 2 else { hideListSwitcher(); return }
        let currentType = lines[0].type

        showListSwitcher(currentType: currentType, selectedLines: lines.map { $0.range })
    }

    private func showListSwitcher(currentType: ListType, selectedLines: [NSRange]) {
        guard let lm = layoutManager, let _ = textContainer else { return }
        let glyphRange = lm.glyphRange(forCharacterRange: selectedLines[0], actualCharacterRange: nil)
        var lineRect = lm.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
        lineRect.origin.x += textContainerOrigin.x
        lineRect.origin.y += textContainerOrigin.y

        let panel = getOrCreateSwitcher()
        panel.currentType = currentType
        panel.selectedLines = selectedLines
        panel.textView = self
        panel.updateButtons()

        let panelSize = panel.frame.size
        let screenPoint = convert(NSPoint(x: lineRect.midX - panelSize.width / 2, y: lineRect.minY - panelSize.height - 4), to: nil)
        let windowPoint = window?.convertPoint(toScreen: screenPoint) ?? screenPoint
        panel.setFrameOrigin(windowPoint)
        panel.orderFront(nil)
    }

    func hideListSwitcher() {
        listSwitcher?.orderOut(nil)
    }

    private func getOrCreateSwitcher() -> ListSwitcherPanel {
        if let existing = listSwitcher { return existing }
        let panel = ListSwitcherPanel()
        listSwitcher = panel
        return panel
    }

    func convertListLines(_ ranges: [NSRange], to type: ListType) {
        guard let storage = textStorage else { return }
        let text = storage.string as NSString
        var offset = 0

        let fullRange = NSRange(location: ranges.first!.location, length: NSMaxRange(ranges.last!) - ranges.first!.location)
        let fullText = text.substring(with: fullRange)

        if shouldChangeText(in: fullRange, replacementString: fullText) {
            var num = 1
            for lineRange in ranges {
                let adjusted = NSRange(location: lineRange.location + offset, length: lineRange.length)
                let line = (storage.string as NSString).substring(with: adjusted)
                let ns = line as NSString
                let r = NSRange(location: 0, length: ns.length)

                var prefixRange = NSRange(location: 0, length: 0)
                if let m = (try? NSRegularExpression(pattern: #"^(\s*)([-*+]\s+\[[ xX]\]\s+|[-*+]\s+|\d+\.\s+)"#))?.firstMatch(in: line, range: r) {
                    prefixRange = m.range(at: 2)
                }

                let oldPrefix = ns.substring(with: prefixRange)
                let newPrefix: String
                switch type {
                case .bullet: newPrefix = "- "
                case .numbered: newPrefix = "\(num). "; num += 1
                case .checkbox: newPrefix = "- [ ] "
                }

                let globalPrefixRange = NSRange(location: adjusted.location + prefixRange.location, length: prefixRange.length)
                storage.replaceCharacters(in: globalPrefixRange, with: newPrefix)
                offset += (newPrefix as NSString).length - oldPrefix.count
            }
            didChangeText()
        }
    }
}

// MARK: - List Switcher Panel

class ListSwitcherPanel: NSPanel {
    var currentType: BubbleTextView.ListType = .bullet
    var selectedLines: [NSRange] = []
    weak var textView: BubbleTextView?

    private var bulletBtn: NSButton!
    private var numberedBtn: NSButton!
    private var checkboxBtn: NSButton!

    private let btnSize: CGFloat = 28
    private let panelPad: CGFloat = 4
    private let btnSpacing: CGFloat = 1

    init() {
        let totalW = 28 * 3 + 1 * 2 + 4 * 2
        let totalH = 28 + 4 * 2
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: totalW, height: totalH),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .floating
        hasShadow = true
        backgroundColor = .clear
        isOpaque = false
        hidesOnDeactivate = true

        let bg = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: totalW, height: totalH))
        bg.material = .popover
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 6
        bg.layer?.masksToBounds = true
        contentView = bg

        bulletBtn = makeButton(symbol: "list.bullet", tag: 0)
        numberedBtn = makeButton(symbol: "list.number", tag: 1)
        checkboxBtn = makeButton(symbol: "checklist", tag: 2)

        let stack = NSStackView(views: [bulletBtn, numberedBtn, checkboxBtn])
        stack.orientation = .horizontal
        stack.spacing = btnSpacing
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: panelPad),
            stack.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -panelPad),
            stack.topAnchor.constraint(equalTo: bg.topAnchor, constant: panelPad),
            stack.bottomAnchor.constraint(equalTo: bg.bottomAnchor, constant: -panelPad),
        ])
    }

    private func makeButton(symbol: String, tag: Int) -> NSButton {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        let btn = NSButton(frame: .zero)
        btn.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        btn.imagePosition = .imageOnly
        btn.isBordered = false
        btn.tag = tag
        btn.target = self
        btn.action = #selector(switchType(_:))
        btn.widthAnchor.constraint(equalToConstant: btnSize).isActive = true
        btn.heightAnchor.constraint(equalToConstant: btnSize).isActive = true
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 4
        return btn
    }

    func updateButtons() {
        for (btn, type) in [(bulletBtn!, BubbleTextView.ListType.bullet),
                            (numberedBtn!, BubbleTextView.ListType.numbered),
                            (checkboxBtn!, BubbleTextView.ListType.checkbox)] {
            let active = currentType == type
            btn.contentTintColor = active ? .controlAccentColor : .tertiaryLabelColor
            btn.layer?.backgroundColor = active ? NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor : nil
        }
    }

    @objc private func switchType(_ sender: NSButton) {
        let type: BubbleTextView.ListType
        switch sender.tag {
        case 0: type = .bullet
        case 1: type = .numbered
        case 2: type = .checkbox
        default: return
        }
        textView?.convertListLines(selectedLines, to: type)
    }
}
