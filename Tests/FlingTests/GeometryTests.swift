import CoreGraphics
import Testing
@testable import Fling

// A 1200×800 usable area below a 25pt menu bar, and a small window on it.
private let screen = CGRect(x: 0, y: 25, width: 1200, height: 800)
private let window = CGRect(x: 100, y: 100, width: 400, height: 300)

@Test func halvesCornersThirds() {
    #expect(Action.leftHalf.frame(for: window, in: screen) == CGRect(x: 0, y: 25, width: 600, height: 800))
    #expect(Action.bottomHalf.frame(for: window, in: screen) == CGRect(x: 0, y: 425, width: 1200, height: 400))
    #expect(Action.bottomRight.frame(for: window, in: screen) == CGRect(x: 600, y: 425, width: 600, height: 400))
    #expect(Action.centerThird.frame(for: window, in: screen) == CGRect(x: 400, y: 25, width: 400, height: 800))
    #expect(Action.lastTwoThirds.frame(for: window, in: screen) == CGRect(x: 400, y: 25, width: 800, height: 800))
}

@Test func maximizeAndCenter() {
    #expect(Action.maximize.frame(for: window, in: screen) == screen)
    #expect(Action.maximizeHeight.frame(for: window, in: screen) == CGRect(x: 100, y: 25, width: 400, height: 800))
    #expect(Action.center.frame(for: window, in: screen) == CGRect(x: 400, y: 275, width: 400, height: 300))
    // A window bigger than the screen is shrunk to fit when centered.
    let huge = CGRect(x: 0, y: 0, width: 5000, height: 5000)
    #expect(Action.center.frame(for: huge, in: screen) == screen)
}

@Test func largerSmallerClamp() {
    #expect(Action.larger.frame(for: window, in: screen) == CGRect(x: 70, y: 70, width: 460, height: 360))
    #expect(Action.larger.frame(for: screen, in: screen) == screen)
    let tiny = CGRect(x: 0, y: 25, width: 320, height: 220)
    #expect(Action.smaller.frame(for: tiny, in: screen) == tiny)
}

@Test func displayHelpers() {
    let right = CGRect(x: 1200, y: 0, width: 2400, height: 1600)
    #expect(map(Action.leftHalf.frame(for: window, in: screen), from: screen, to: right)
        == CGRect(x: 1200, y: 0, width: 1200, height: 1600))
    #expect(screenIndex(for: CGRect(x: 1100, y: 100, width: 400, height: 300), in: [screen, right]) == 1)
    #expect(screenIndex(for: CGRect(x: -9000, y: 0, width: 10, height: 10), in: [screen, right]) == 0)
    // AppKit bottom-left origin → AX top-left origin on a 900pt-tall primary display.
    #expect(flip(CGRect(x: 0, y: 0, width: 1200, height: 875), primaryHeight: 900) == CGRect(x: 0, y: 25, width: 1200, height: 875))
}

@Test func gridsCyclingAndGaps() {
    #expect(Action.secondFourth.frame(for: window, in: screen) == CGRect(x: 300, y: 25, width: 300, height: 800))
    #expect(Action.bottomRightSixth.frame(for: window, in: screen) == CGRect(x: 800, y: 425, width: 400, height: 400))
    #expect(Action.centerTwoThirds.frame(for: window, in: screen) == CGRect(x: 200, y: 25, width: 800, height: 800))
    // Portrait displays split thirds into rows.
    let portrait = CGRect(x: 0, y: 0, width: 900, height: 1500)
    #expect(Action.firstThird.frame(for: window, in: portrait) == CGRect(x: 0, y: 0, width: 900, height: 500))
    // Repeating Right Half: ½ → ⅔ → ⅓ → ½.
    #expect(Action.rightHalf.frame(for: window, in: screen, repeatCount: 1) == CGRect(x: 400, y: 25, width: 800, height: 800))
    #expect(Action.rightHalf.frame(for: window, in: screen, repeatCount: 2) == CGRect(x: 800, y: 25, width: 400, height: 800))
    #expect(Action.rightHalf.frame(for: window, in: screen, repeatCount: 3) == Action.rightHalf.frame(for: window, in: screen))
    // A 20px gap at the screen edges and between the two halves (10 + 10).
    #expect(Action.leftHalf.frame(for: window, in: screen, gap: 20) == CGRect(x: 20, y: 45, width: 570, height: 760))
    #expect(Action.rightHalf.frame(for: window, in: screen, gap: 20) == CGRect(x: 610, y: 45, width: 570, height: 760))
    // Floating actions ignore gaps.
    #expect(Action.center.frame(for: window, in: screen, gap: 20) == Action.center.frame(for: window, in: screen))
}

@Test func snapAreas() {
    let full = CGRect(x: 0, y: 0, width: 1200, height: 825)
    #expect(snapAction(at: CGPoint(x: 0, y: 400), in: full) == .leftHalf)
    #expect(snapAction(at: CGPoint(x: 1199, y: 400), in: full) == .rightHalf)
    #expect(snapAction(at: CGPoint(x: 600, y: 0), in: full) == .maximize)
    #expect(snapAction(at: CGPoint(x: 10, y: 0), in: full) == .topLeft)
    #expect(snapAction(at: CGPoint(x: 1199, y: 820), in: full) == .bottomRight)
    #expect(snapAction(at: CGPoint(x: 600, y: 824), in: full) == .centerThird)
    #expect(snapAction(at: CGPoint(x: 600, y: 400), in: full) == nil)
    // Configured areas: left edge maximizes, top edge disabled.
    let custom: (SnapArea) -> String = { $0 == .left ? "maximize" : $0 == .top ? "none" : $0.defaultSetting }
    #expect(snapAction(at: CGPoint(x: 0, y: 400), in: full, setting: custom) == .maximize)
    #expect(snapAction(at: CGPoint(x: 600, y: 0), in: full, setting: custom) == nil)
    #expect(snapAction(at: CGPoint(x: 600, y: 824), in: full, setting: custom) == .centerThird)
}

@Test func throwsAndQuickThrows() {
    #expect(throwAction(dx: 50, dy: 0, long: false) == .rightHalf)
    #expect(throwAction(dx: 50, dy: 0, long: false) { sector, _ in sector == 0 ? "none" : "maximize" } == nil)
    #expect(throwAction(dx: 0, dy: 50, long: true) { _, long in long ? "almostMaximize" : "none" } == .almostMaximize)
    #expect(throwAction(dx: 0, dy: -50, long: false) == .topHalf)
    #expect(throwAction(dx: -40, dy: 40, long: false) == .bottomLeft)
    #expect(throwAction(dx: -50, dy: 5, long: true) == .firstTwoThirds)
    #expect(throwAction(dx: 3, dy: -200, long: true) == .maximize)
    #expect(quickThrowAction(dx: -80, dy: 10) == .leftHalf)
    #expect(quickThrowAction(dx: 5, dy: 90) == .minimize)
    #expect(quickThrowAction(dx: 10, dy: 10) == nil)
}

@Test func fillTileCascadeNudge() {
    // A window occupying the right third: Fill Left stops at its edge; nothing in the way → half.
    let rightThird = CGRect(x: 800, y: 25, width: 400, height: 800)
    #expect(fillFrame(left: true, others: [rightThird], in: screen) == CGRect(x: 0, y: 25, width: 800, height: 800))
    #expect(fillFrame(left: true, others: [], in: screen) == CGRect(x: 0, y: 25, width: 600, height: 800))
    #expect(fillFrame(left: false, others: [CGRect(x: 0, y: 25, width: 400, height: 800)], in: screen)
        == CGRect(x: 400, y: 25, width: 800, height: 800))

    let tiles = tileFrames(count: 5, columns: 2, rows: 2, in: screen)
    #expect(tiles.count == 4)
    #expect(tiles[3] == CGRect(x: 600, y: 425, width: 600, height: 400))
    #expect(tileFrames(count: 2, columns: 2, rows: 2, in: screen, gap: 20)[1] == CGRect(x: 610, y: 45, width: 570, height: 370))

    let cascade = cascadeFrames(sizes: [CGSize(width: 2000, height: 300), CGSize(width: 400, height: 300)], in: screen)
    #expect(cascade[0] == CGRect(x: 0, y: 25, width: 1170, height: 300))
    #expect(cascade[1] == CGRect(x: 30, y: 55, width: 400, height: 300))

    #expect(Action.nudgeUp.frame(for: window, in: screen) == CGRect(x: 100, y: 70, width: 400, height: 300))
    #expect(Action.tile2x2.urlName == "tile2x2" && Action.tile2x2.title == "2×2 Tiles")
}

@Test func adjacentResizeAndDockAdjust() {
    let left = CGRect(x: 0, y: 25, width: 600, height: 800), right = CGRect(x: 600, y: 25, width: 600, height: 800)
    let below = CGRect(x: 0, y: 900, width: 600, height: 100) // not beside the dragged edge
    // Dragging the left window's right edge to 700 shrinks its neighbour.
    let moved = adjacentFrames(old: left, new: CGRect(x: 0, y: 25, width: 700, height: 800), others: [right, below])
    #expect(moved == [0: CGRect(x: 700, y: 25, width: 500, height: 800)])
    // With a 10pt gap between them, the gap is kept.
    let gapped = adjacentFrames(old: CGRect(x: 0, y: 25, width: 595, height: 800), new: CGRect(x: 0, y: 25, width: 695, height: 800),
                                others: [CGRect(x: 605, y: 25, width: 595, height: 800)], tolerance: 14)
    #expect(gapped == [0: CGRect(x: 705, y: 25, width: 495, height: 800)])

    // Dock hidden: the usable area grows from 800 to 875 tall; a left half stretches, a centered window doesn't.
    let old = CGRect(x: 0, y: 25, width: 1200, height: 800), new = CGRect(x: 0, y: 25, width: 1200, height: 875)
    #expect(adjusted(left, from: old, to: new) == CGRect(x: 0, y: 25, width: 600, height: 875))
    #expect(adjusted(CGRect(x: 300, y: 200, width: 400, height: 300), from: old, to: new) == nil)
}
