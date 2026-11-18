import CoreGraphics
import Foundation
import Testing
@testable import DotJSON

struct TabBarAutoScrollLogicTests {

    /// 自动滚动节拍必须可暂停，不能在静止切签时用常驻 Timer 打主线程。
    @Test func tabBarAutoScrollUsesPausedTimelineInsteadOfAlwaysOnTimer() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DotJSON/Views/TabBarView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("TimelineView("))
        #expect(source.contains("if draggingTabId != nil"))
        #expect(!source.contains("Timer.publish("))
    }

    /// 单击切签不得使用系统双击手势，否则会等待双击判定窗口（约 300–500ms）。
    @Test func tabBarActivationDoesNotWaitForSystemDoubleTapGesture() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DotJSON/Views/TabBarView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("handleTitleTap()"))
        #expect(source.contains("TabBarRenameTiming.doubleTapInterval"))
        #expect(!source.contains("TapGesture(count: 2)"))
        #expect(!source.contains("highPriorityGesture("))
    }

    @Test func tabBarRenameDoubleTapIntervalIsBelowHalfSecond() {
        #expect(TabBarRenameTiming.doubleTapInterval < 0.5)
        #expect(TabBarRenameTiming.doubleTapInterval > 0)
    }


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
