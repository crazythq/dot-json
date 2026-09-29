import CoreGraphics
import Foundation

/// Pure helpers for tab-bar edge auto-scroll during drag (commit-on-drop; scroll by geometry).
enum TabBarAutoScrollLogic {

    /// Tab to scroll toward so content hidden on the leading/trailing side enters the clip rect.
    ///
    /// - Parameter towardLeading: `true` when the pointer is in the left edge band (reveal tabs to the left).
    /// - Parameter advancingFrom: When the same tab remains off-screen after a tick, walk one index further.
    static func scrollTargetTabId(
        orderedTabIds: [UUID],
        tabFrames: [UUID: CGRect],
        visibleClip: CGRect,
        towardLeading: Bool,
        advancingFrom previousTargetId: UUID? = nil,
        alignmentMargin: CGFloat = 2
    ) -> UUID? {
        guard !orderedTabIds.isEmpty, !visibleClip.isEmpty else { return nil }

        let primary = primaryOffScreenTabId(
            orderedTabIds: orderedTabIds,
            tabFrames: tabFrames,
            visibleClip: visibleClip,
            towardLeading: towardLeading,
            alignmentMargin: alignmentMargin
        )

        guard let previousTargetId,
              primary == previousTargetId,
              let prevIndex = orderedTabIds.firstIndex(of: previousTargetId) else {
            return primary
        }

        let furtherIndex = towardLeading ? prevIndex - 1 : prevIndex + 1
        guard orderedTabIds.indices.contains(furtherIndex) else { return primary }
        return orderedTabIds[furtherIndex]
    }

    private static func primaryOffScreenTabId(
        orderedTabIds: [UUID],
        tabFrames: [UUID: CGRect],
        visibleClip: CGRect,
        towardLeading: Bool,
        alignmentMargin: CGFloat
    ) -> UUID? {
        if towardLeading {
            var bestId: UUID?
            var bestMaxX = -CGFloat.infinity
            for id in orderedTabIds {
                guard let frame = tabFrames[id] else { continue }
                if frame.minX < visibleClip.minX - alignmentMargin, frame.maxX > bestMaxX {
                    bestMaxX = frame.maxX
                    bestId = id
                }
            }
            return bestId
        }

        var bestId: UUID?
        var bestMinX = CGFloat.infinity
        for id in orderedTabIds {
            guard let frame = tabFrames[id] else { continue }
            if frame.maxX > visibleClip.maxX + alignmentMargin, frame.minX < bestMinX {
                bestMinX = frame.minX
                bestId = id
            }
        }
        return bestId
    }
}
