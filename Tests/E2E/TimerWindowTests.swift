import AppKit
import XCTest

/// The timer window as a user sees and handles it (spec §6, §14.3).
final class TimerWindowTests: XCTestCase {
    /// The number of different colours in a sample of the element's pixels. An empty window has
    /// one or two; a drawn layout, with its text, many more.
    @MainActor
    private func colours(in element: XCUIElement) -> Int {
        guard
            let image = element.screenshot().image.cgImage(
                forProposedRect: nil, context: nil, hints: nil),
            let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return 0 }
        let (width, height) = (image.width, image.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drew = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard
                let context = CGContext(
                    data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else { return 0 }
        var seen = Set<UInt32>()
        for index in stride(from: 0, to: pixels.count, by: 4 * 7) {
            seen.insert(
                UInt32(pixels[index]) << 16 | UInt32(pixels[index + 1]) << 8
                    | UInt32(pixels[index + 2]))
        }
        return seen.count
    }

    @MainActor
    func testFirstLaunchShowsTheDefaultLayout() {
        let e2e = E2EApp()
        e2e.launch()
        let window = e2e.timerWindow
        XCTAssertTrue(window.waitForExistence(timeout: 10))

        XCTAssertEqual(window.frame.size, CGSize(width: 300, height: 500))
        let layout = window.images["timer-layout"]
        XCTAssertTrue(layout.waitForExistence(timeout: 5))
        let deadline = Date().addingTimeInterval(5)
        while colours(in: window) <= 10, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertGreaterThan(colours(in: window), 10, "the window shows no layout")
    }

    @MainActor
    func testTheWindowMovesAndOpensThereAgain() {
        let e2e = E2EApp()
        e2e.launch()
        let window = e2e.timerWindow
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        let before = window.frame

        // Built from .zero plus explicit offsets: normalized offsets landed in the wrong place on
        // the borderless window.
        let middle = window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: before.width / 2, dy: before.height / 2))
        let target = window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: before.width / 2 + 120, dy: before.height / 2 + 80))
        middle.press(forDuration: 0.2, thenDragTo: target)

        let moved = window.frame
        XCTAssertEqual(moved.minX, before.minX + 120, accuracy: 2)
        XCTAssertEqual(moved.minY, before.minY + 80, accuracy: 2)
        // The frame is saved once the window stops. x is the same in XCUITest's coordinates and
        // AppKit's (only y is flipped), and app.toml writes it as a Double, such as "x = 690.0".
        let saved = e2e.settingsText(containing: "x = \(Double(moved.minX))")
        XCTAssertNotNil(saved, "app.toml doesn't hold the moved frame")
        XCTAssertTrue(saved?.contains("[default_layout_window]") == true)

        e2e.relaunch()
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        XCTAssertEqual(window.frame.minX, moved.minX, accuracy: 1)
        XCTAssertEqual(window.frame.minY, moved.minY, accuracy: 1)
        XCTAssertEqual(window.frame.size, moved.size)
    }

    @MainActor
    func testTheWindowResizesFromItsCorner() {
        let e2e = E2EApp()
        e2e.launch()
        let window = e2e.timerWindow
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        let before = window.frame

        // Built from .zero plus explicit offsets: normalized offsets landed in the wrong place on
        // the borderless window.
        let corner = window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: before.width - 2, dy: before.height - 2))
        corner.press(forDuration: 0.2, thenDragTo: corner.withOffset(CGVector(dx: 60, dy: 40)))

        XCTAssertEqual(window.frame.width, before.width + 60, accuracy: 3)
        XCTAssertEqual(window.frame.height, before.height + 40, accuracy: 3)
        XCTAssertEqual(window.frame.minX, before.minX, accuracy: 1)
        XCTAssertEqual(window.frame.minY, before.minY, accuracy: 1)
    }
}
