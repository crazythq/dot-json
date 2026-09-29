import CoreGraphics
import Testing
@testable import DotJSON

struct TabBarAutoScrollLogicTests {

    @Test func towardLeadingPicksRightmostTabCutOffOnLeadingSide() {
        let ids = (0..<4).map { _ in UUID() }
        let clip = CGRect(x: 100, y: 0, width: 300, height: 32)
        let frames: [UUID: CGRect] = [
            ids[0]: CGRect(x: 10, y: 0, width: 60, height: 28),
            ids[1]: CGRect(x: 70, y: 0, width: 80, height: 28),
            ids[2]: CGRect(x: 200, y: 0, width: 80, height: 28),
            ids[3]: CGRect(x: 420, y: 0, width: 80, height: 28),
        ]

        let target = TabBarAutoScrollLogic.scrollTargetTabId(
            orderedTabIds: ids,
            tabFrames: frames,
            visibleClip: clip,
            towardLeading: true
        )

        #expect(target == ids[1])
    }

    @Test func towardTrailingPicksLeftmostTabCutOffOnTrailingSide() {
        let ids = (0..<4).map { _ in UUID() }
        let clip = CGRect(x: 100, y: 0, width: 300, height: 32)
        let frames: [UUID: CGRect] = [
            ids[0]: CGRect(x: 10, y: 0, width: 60, height: 28),
            ids[1]: CGRect(x: 120, y: 0, width: 80, height: 28),
            ids[2]: CGRect(x: 350, y: 0, width: 80, height: 28),
            ids[3]: CGRect(x: 430, y: 0, width: 80, height: 28),
        ]

        let target = TabBarAutoScrollLogic.scrollTargetTabId(
            orderedTabIds: ids,
            tabFrames: frames,
            visibleClip: clip,
            towardLeading: false
        )

        #expect(target == ids[2])
    }

    @Test func advancingFromWalksFurtherLeadingWhenStuckOnSameTarget() {
        let ids = (0..<3).map { _ in UUID() }
        let clip = CGRect(x: 100, y: 0, width: 300, height: 32)
        let frames: [UUID: CGRect] = [
            ids[0]: CGRect(x: 20, y: 0, width: 50, height: 28),
            ids[1]: CGRect(x: 70, y: 0, width: 50, height: 28),
            ids[2]: CGRect(x: 200, y: 0, width: 80, height: 28),
        ]

        let first = TabBarAutoScrollLogic.scrollTargetTabId(
            orderedTabIds: ids,
            tabFrames: frames,
            visibleClip: clip,
            towardLeading: true
        )
        #expect(first == ids[1])

        let advanced = TabBarAutoScrollLogic.scrollTargetTabId(
            orderedTabIds: ids,
            tabFrames: frames,
            visibleClip: clip,
            towardLeading: true,
            advancingFrom: ids[1]
        )
        #expect(advanced == ids[0])
    }

    @Test func returnsNilWhenNothingOffScreenInDirection() {
        let ids = [UUID(), UUID()]
        let clip = CGRect(x: 0, y: 0, width: 400, height: 32)
        let frames: [UUID: CGRect] = [
            ids[0]: CGRect(x: 10, y: 0, width: 80, height: 28),
            ids[1]: CGRect(x: 100, y: 0, width: 80, height: 28),
        ]

        #expect(
            TabBarAutoScrollLogic.scrollTargetTabId(
                orderedTabIds: ids,
                tabFrames: frames,
                visibleClip: clip,
                towardLeading: true
            ) == nil
        )
        #expect(
            TabBarAutoScrollLogic.scrollTargetTabId(
                orderedTabIds: ids,
                tabFrames: frames,
                visibleClip: clip,
                towardLeading: false
            ) == nil
        )
    }
}
