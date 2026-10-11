import CoreGraphics
import Testing

@testable import LiveSplitOne

@Suite struct WindowPlacementTests {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)

    @Test func aSavedFrameOnAScreenIsUsed() {
        let saved = WindowFrame(x: 100, y: 200, width: 250, height: 400)
        #expect(
            WindowPlacement.restoredFrame(saved, screens: [screen])
                == CGRect(x: 100, y: 200, width: 250, height: 400))
    }

    @Test func aSavedFrameOffEveryScreenIsIgnored() {
        let saved = WindowFrame(x: 3000, y: 200, width: 250, height: 400)
        #expect(WindowPlacement.restoredFrame(saved, screens: [screen]) == nil)
    }

    @Test func aSavedFrameBarelyOnAScreenIsIgnored() {
        // 30 points of it on the screen: too little to grab and drag back.
        let saved = WindowFrame(x: 1410, y: 200, width: 250, height: 400)
        #expect(WindowPlacement.restoredFrame(saved, screens: [screen]) == nil)
    }

    @Test func aSavedFrameWithLittleHeightOnScreenIsIgnored() {
        // 10 points of its height on the screen.
        let saved = WindowFrame(x: 100, y: -390, width: 250, height: 400)
        #expect(WindowPlacement.restoredFrame(saved, screens: [screen]) == nil)
    }

    @Test func aSavedFrameOnASecondScreenIsUsed() {
        let second = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let saved = WindowFrame(x: 2000, y: 100, width: 300, height: 500)
        #expect(
            WindowPlacement.restoredFrame(saved, screens: [screen, second])
                == CGRect(x: 2000, y: 100, width: 300, height: 500))
    }

    @Test func aSavedFrameSplitBetweenTwoScreensNeedsEnoughOnOne() {
        // 30 points of its width on each screen: 60 in all, but too little on either.
        let second = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let saved = WindowFrame(x: 1410, y: 200, width: 60, height: 400)
        #expect(WindowPlacement.restoredFrame(saved, screens: [screen, second]) == nil)
    }

    @Test func aSavedFrameAtTheMinimumWidthMustBeWhollyOnScreen() {
        // As wide as the minimum visible width: all of it must show.
        let fits = WindowFrame(x: 1400, y: 200, width: 40, height: 400)
        #expect(
            WindowPlacement.restoredFrame(fits, screens: [screen])
                == CGRect(x: 1400, y: 200, width: 40, height: 400))
        let sliver = WindowFrame(x: 1401, y: 200, width: 40, height: 400)
        #expect(WindowPlacement.restoredFrame(sliver, screens: [screen]) == nil)
    }

    @Test func aShortSavedFrameMustBeWhollyOnScreen() {
        // 20 points tall, under the 40 asked of a larger frame: all 20 must show.
        let fits = WindowFrame(x: 100, y: 0, width: 300, height: 20)
        #expect(
            WindowPlacement.restoredFrame(fits, screens: [screen])
                == CGRect(x: 100, y: 0, width: 300, height: 20))
        let partly = WindowFrame(x: 100, y: -5, width: 300, height: 20)
        #expect(WindowPlacement.restoredFrame(partly, screens: [screen]) == nil)
    }

    @Test func aSavedFrameLargerThanItsScreenShrinksToFit() {
        let saved = WindowFrame(x: 0, y: -1125, width: 3000, height: 2000)
        #expect(WindowPlacement.restoredFrame(saved, screens: [screen]) == screen)
    }

    @Test func aSavedFrameTooTallKeepsItsTopLeft() {
        // Its top-left corner is at the top of the screen, so only the bottom is cut.
        let saved = WindowFrame(x: 100, y: -1000, width: 300, height: 1875)
        #expect(
            WindowPlacement.restoredFrame(saved, screens: [screen])
                == CGRect(x: 100, y: 0, width: 300, height: 875))
    }

    @Test func aShrunkFrameMovesOntoItsScreen() {
        // Shrunk to the screen's width, it would still hang off the left edge.
        let saved = WindowFrame(x: -1000, y: 100, width: 3000, height: 500)
        #expect(
            WindowPlacement.restoredFrame(saved, screens: [screen])
                == CGRect(x: 0, y: 100, width: 1440, height: 500))
    }

    @Test func aLargeFrameShrinksToTheScreenItIsMostOn() {
        let second = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        // 240 points wide on the first screen, 1920 on the second.
        let saved = WindowFrame(x: 1200, y: 0, width: 2400, height: 1080)
        #expect(
            WindowPlacement.restoredFrame(saved, screens: [screen, second])
                == CGRect(x: 1440, y: 0, width: 1920, height: 1080))
    }

    @Test func aFramePartlyOffScreenThatFitsIsKept() {
        let saved = WindowFrame(x: 1300, y: 200, width: 300, height: 500)
        #expect(
            WindowPlacement.restoredFrame(saved, screens: [screen])
                == CGRect(x: 1300, y: 200, width: 300, height: 500))
    }

    @Test func noSavedFrameOrNoScreensGivesNothing() {
        #expect(WindowPlacement.restoredFrame(nil, screens: [screen]) == nil)
        let saved = WindowFrame(x: 100, y: 200, width: 250, height: 400)
        #expect(WindowPlacement.restoredFrame(saved, screens: []) == nil)
    }

    @Test func aTinySavedFrameGrowsToTheMinimum() throws {
        let saved = WindowFrame(x: 100, y: 200, width: 1, height: 1)
        let frame = try #require(
            WindowPlacement.restoredFrame(saved, screens: [screen]))
        #expect(frame.size == WindowPlacement.minimumSize)
    }

    @Test func theDefaultSizeIsLiveSplitOnes() {
        #expect(WindowPlacement.defaultSize == CGSize(width: 300, height: 500))
    }

    @Test func centredIsInTheMiddleOfTheScreen() {
        let frame = WindowPlacement.centred(CGSize(width: 300, height: 500), on: screen)
        #expect(frame == CGRect(x: 570, y: 187, width: 300, height: 500))
    }

    @Test func resizingKeepsTheTopLeftCorner() {
        let frame = CGRect(x: 100, y: 200, width: 300, height: 500)
        let resized = WindowPlacement.resized(frame, to: CGSize(width: 300, height: 600))
        #expect(resized == CGRect(x: 100, y: 100, width: 300, height: 600))
        #expect(resized.minX == frame.minX && resized.maxY == frame.maxY)
    }

    @Test func aHintInPixelsBecomesPoints() {
        #expect(
            WindowPlacement.size(forHint: CGSize(width: 600, height: 1200), scale: 2)
                == CGSize(width: 300, height: 600))
    }

    @Test func aHintThatIsntASizeIsIgnored() {
        #expect(WindowPlacement.size(forHint: CGSize(width: 0, height: 100), scale: 2) == nil)
        #expect(
            WindowPlacement.size(
                forHint: CGSize(width: CGFloat.infinity, height: 100), scale: 2) == nil)
        #expect(WindowPlacement.size(forHint: CGSize(width: 300, height: 500), scale: 0) == nil)
        #expect(
            WindowPlacement.size(forHint: CGSize(width: CGFloat.nan, height: 100), scale: 2) == nil)
        #expect(
            WindowPlacement.size(forHint: CGSize(width: 300, height: CGFloat.nan), scale: 2) == nil)
        #expect(WindowPlacement.size(forHint: CGSize(width: -300, height: 500), scale: 2) == nil)
        #expect(WindowPlacement.size(forHint: CGSize(width: 300, height: -500), scale: 2) == nil)
        #expect(WindowPlacement.size(forHint: CGSize(width: 300, height: 500), scale: -2) == nil)
        #expect(
            WindowPlacement.size(forHint: CGSize(width: 300, height: 500), scale: .nan) == nil)
    }

    @Test func aTinyHintGrowsToTheMinimum() {
        #expect(
            WindowPlacement.size(forHint: CGSize(width: 10, height: 10), scale: 1)
                == WindowPlacement.minimumSize)
    }

    @Test func aRectBecomesAWindowFrame() {
        #expect(
            WindowPlacement.windowFrame(CGRect(x: 1, y: 2, width: 3, height: 4))
                == WindowFrame(x: 1, y: 2, width: 3, height: 4))
    }
}
