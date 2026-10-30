import AppKit
import XCTest
@testable import Bubble

/// Renders the real editor offscreen under each appearance and checks the pixels.
/// The attribute tests prove the palette *stores* dynamic colors; this proves they
/// *resolve at draw time* through NSLayoutManager, which is what dark mode depends on.
///
/// Set BUBBLE_SNAPSHOT_DIR=/some/dir to also write bubble-render-{dark,light}.png for eyeballing.
final class AppearanceRenderTests: XCTestCase {

    override class func setUp() {
        super.setUp()
        _ = NSApplication.shared
    }

    private let sample = """
    # You Can Do It

    ## Monday

    - [ ] water the plants
    - [x] finish the first draft

    Body with **bold**, *italic*, `inline code`, ==highlight== and a [link](https://example.com).

    > A quote line

    ```
    let x = 1
    ```
    """

    private struct Stats {
        var minLuma: Double = 1
        var maxLuma: Double = 0
        var brightFraction: Double = 0  // pixels with luma > 0.6
        var darkFraction: Double = 0    // pixels with luma < 0.3
    }

    private func render(appearance name: NSAppearance.Name, pageGray: CGFloat) -> NSBitmapImageRep {
        let storage = MarkdownTextStorage()
        let layoutManager = BubbleLayoutManager()
        storage.addLayoutManager(layoutManager)
        let size = NSSize(width: 640, height: 440)
        let container = NSTextContainer(size: NSSize(width: size.width, height: 10_000_000))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)

        let textView = BubbleTextView(frame: NSRect(origin: .zero, size: size), textContainer: container)
        textView.isRichText = false
        textView.drawsBackground = true
        textView.backgroundColor = NSColor(white: pageGray, alpha: 1)
        textView.textContainerInset = NSSize(width: 24, height: 16)
        textView.typingAttributes = MarkdownStyles.base
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: sample)

        // An offscreen (never ordered front) window gives the view a real appearance chain.
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: name)
        window.contentView = textView
        layoutManager.ensureLayout(for: container)

        let rep = textView.bitmapImageRepForCachingDisplay(in: textView.bounds)!
        textView.cacheDisplay(in: textView.bounds, to: rep)
        return rep
    }

    private func stats(of rep: NSBitmapImageRep) -> Stats {
        guard let data = rep.bitmapData else { XCTFail("no bitmap data"); return Stats() }
        let spp = rep.samplesPerPixel, bpr = rep.bytesPerRow
        var s = Stats()
        var bright = 0, dark = 0, total = 0
        for y in 0..<rep.pixelsHigh {
            let row = data + y * bpr
            for x in 0..<rep.pixelsWide {
                let p = row + x * spp
                let luma = (Double(p[0]) + Double(p[1]) + Double(p[2])) / (3 * 255)
                s.minLuma = min(s.minLuma, luma)
                s.maxLuma = max(s.maxLuma, luma)
                if luma > 0.6 { bright += 1 }
                if luma < 0.3 { dark += 1 }
                total += 1
            }
        }
        s.brightFraction = Double(bright) / Double(total)
        s.darkFraction = Double(dark) / Double(total)
        return s
    }

    private func snapshot(_ rep: NSBitmapImageRep, name: String) {
        guard let dir = ProcessInfo.processInfo.environment["BUBBLE_SNAPSHOT_DIR"],
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("bubble-render-\(name).png"))
    }

    func testDarkModeRendersLightTextOnDarkPage() {
        let rep = render(appearance: .darkAqua, pageGray: 0.17)
        snapshot(rep, name: "dark")
        let s = stats(of: rep)

        XCTAssertGreaterThan(s.maxLuma, 0.75, "body text should reach a light gray in dark mode")
        XCTAssertGreaterThan(s.brightFraction, 0.005, "there must be a visible amount of light text")
        XCTAssertLessThan(s.brightFraction, 0.30, "the page itself must stay dark")
    }

    func testLightModeRendersDarkTextOnLightPage() {
        let rep = render(appearance: .aqua, pageGray: 0.96)
        snapshot(rep, name: "light")
        let s = stats(of: rep)

        XCTAssertLessThan(s.minLuma, 0.25, "body text should reach a near-black in light mode")
        XCTAssertGreaterThan(s.darkFraction, 0.005, "there must be a visible amount of dark text")
        XCTAssertLessThan(s.darkFraction, 0.30, "the page itself must stay light")
    }
}
