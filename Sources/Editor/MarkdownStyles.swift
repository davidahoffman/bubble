import AppKit

extension NSAttributedString.Key {
    /// Marks fenced code block ranges so BubbleLayoutManager can draw the rounded,
    /// full-width background without comparing appearance-dependent colors.
    static let bubbleCodeBlock = NSAttributedString.Key("bubble.codeBlock")
}

enum MarkdownStyles {
    static let baseFont = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)

    // Appearance-aware palette. Each entry carries a light and a dark value; AppKit
    // resolves the pair against the view's effective appearance every time it draws,
    // so one attributed string renders correctly in both modes and re-renders live
    // when the system switches. Light values are the original palette, unchanged.
    // Dark values are tuned for the ~0.17 gray of the window material.
    static let textColor = dynamic("text",
                                   light: (0.12, 0.12, 0.13, 1),
                                   dark:  (0.88, 0.88, 0.90, 1))
    static let mutedColor = dynamic("muted",
                                    light: (0.68, 0.68, 0.72, 1),
                                    dark:  (0.44, 0.44, 0.48, 1))
    static let codeBackground = dynamic("inlineCodeBackground",
                                        light: (0.94, 0.94, 0.96, 0.7),
                                        dark:  (1.00, 1.00, 1.00, 0.09))
    static let blockquoteColor = dynamic("blockquote",
                                         light: (0.40, 0.40, 0.44, 1),
                                         dark:  (0.66, 0.66, 0.70, 1))
    static let linkColor = NSColor.systemBlue  // system color, already adapts
    static let checkedColor = dynamic("checked",
                                      light: (0.60, 0.60, 0.64, 1),
                                      dark:  (0.50, 0.50, 0.54, 1))
    static let inlineCodeColor = dynamic("inlineCode",
                                         light: (0.18, 0.55, 0.34, 1),
                                         dark:  (0.48, 0.80, 0.58, 1))
    static let highlightBackground = dynamic("highlight",
                                             light: (1.00, 0.92, 0.30, 0.40),
                                             dark:  (1.00, 0.78, 0.20, 0.30))

    // Code blocks are dark in both modes: off-black on a light page, and an inset
    // block darker than the window on a dark page so it still reads as a block.
    static let codeBlockBackground = dynamic("codeBlockBackground",
                                             light: (0.19, 0.20, 0.24, 1),
                                             dark:  (0.11, 0.11, 0.13, 1))
    static let codeBlockText = NSColor(srgbRed: 0.84, green: 0.85, blue: 0.88, alpha: 1)  // on a dark block in both modes
    static let codeBlockFence = dynamic("codeBlockFence",
                                        light: (0.44, 0.45, 0.50, 1),
                                        dark:  (0.50, 0.51, 0.56, 1))

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

    // MARK: - Helpers

    private typealias RGBA = (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)

    /// A color that resolves to `light` under Aqua and `dark` under Dark Aqua
    /// (including the high-contrast variants of each) at draw time.
    private static func dynamic(_ name: String, light: RGBA, dark: RGBA) -> NSColor {
        NSColor(name: NSColor.Name("bubble.\(name)")) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let c = isDark ? dark : light
            return NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: c.a)
        }
    }
}
