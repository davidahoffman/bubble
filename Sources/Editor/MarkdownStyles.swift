import AppKit

enum MarkdownStyles {
    static let baseFont = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
    static let textColor = NSColor(srgbRed: 0.12, green: 0.12, blue: 0.13, alpha: 1)
    static let mutedColor = NSColor(srgbRed: 0.68, green: 0.68, blue: 0.72, alpha: 1)
    static let codeBackground = NSColor(srgbRed: 0.94, green: 0.94, blue: 0.96, alpha: 0.7)
    static let blockquoteColor = NSColor(srgbRed: 0.4, green: 0.4, blue: 0.44, alpha: 1)
    static let linkColor = NSColor.systemBlue
    static let checkedColor = NSColor(srgbRed: 0.6, green: 0.6, blue: 0.64, alpha: 1)
    static let inlineCodeColor = NSColor(srgbRed: 0.18, green: 0.55, blue: 0.34, alpha: 1)
    static let highlightBackground = NSColor(srgbRed: 1.0, green: 0.92, blue: 0.3, alpha: 0.4)

    // Dark code blocks (off-black, not pure black)
    static let codeBlockBackground = NSColor(srgbRed: 0.19, green: 0.20, blue: 0.24, alpha: 1)
    static let codeBlockText = NSColor(srgbRed: 0.84, green: 0.85, blue: 0.88, alpha: 1)
    static let codeBlockFence = NSColor(srgbRed: 0.44, green: 0.45, blue: 0.50, alpha: 1)

    static let maxContentWidth: CGFloat = 720

    static let baseParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        style.paragraphSpacing = 2
        return style
    }()

    static let base: [NSAttributedString.Key: Any] = [
        .font: baseFont,
        .foregroundColor: textColor,
        .paragraphStyle: baseParagraphStyle,
    ]

    static func headingFont(level: Int) -> NSFont {
        let sizes: [CGFloat] = [32, 26, 22, 18, 16, 15]
        let size = sizes[min(level - 1, sizes.count - 1)]
        return NSFont.monospacedSystemFont(ofSize: size, weight: .bold)
    }

    static func headingParagraphStyle(level: Int) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = level <= 2 ? 8 : 4
        style.paragraphSpacingBefore = level <= 2 ? 12 : 8
        style.paragraphSpacing = level <= 2 ? 6 : 4
        return style
    }
}
