import DotJSONCore
import Testing
@testable import DotJSON

/// 用户展开状态与系统临时展开覆盖层的行为测试。
struct TreeExpansionStateTests {
    private let root = TreeNodeID.root
    private let outer = TreeNodeID(components: [.key("outer")])
    private let inner = TreeNodeID(components: [.key("outer"), .key("inner")])

    /// 切换搜索结果时必须替换旧的系统路径，不能累计展开所有访问过的分支。
    @Test func replacingSystemExpansionRemovesPreviousTemporaryPath() {
        var state = TreeExpansionState()
        state.beginSearchSession()
        state.replaceSystemExpansion(with: [root, outer])

        state.replaceSystemExpansion(with: [root, inner])

        #expect(state.systemExpandedIDs == [root, inner])
        #expect(!state.effectiveExpandedIDs.contains(outer))
    }

    /// 搜索期间的用户展开应成为持久用户状态，结束搜索后继续保留。
    @Test func userExpansionDuringSearchPersistsAfterSearchEnds() {
        var state = TreeExpansionState()
        state.beginSearchSession()
        state.replaceSystemExpansion(with: [root])

        state.recordUserExpanded(outer)
        state.endSearchSession()

        #expect(state.userExpandedIDs == [outer])
        #expect(state.effectiveExpandedIDs == [outer])
        #expect(state.systemExpandedIDs.isEmpty)
    }

    /// 用户主动收起系统临时展开节点后，当前和后续定位都不得再次强行展开该节点。
    @Test func userCollapseDuringSearchBlocksLaterSystemExpansion() {
        var state = TreeExpansionState()
        state.recordUserExpanded(outer)
        state.beginSearchSession()
        state.replaceSystemExpansion(with: [root, outer])

        state.recordUserCollapsed(outer)
        state.replaceSystemExpansion(with: [root, outer, inner])

        #expect(!state.userExpandedIDs.contains(outer))
        #expect(!state.systemExpandedIDs.contains(outer))
        #expect(!state.effectiveExpandedIDs.contains(outer))
    }

    /// 新搜索会清除上次会话的临时阻止标记，但不会改写用户状态。
    @Test func newSearchSessionMayTemporarilyExpandPreviouslyCollapsedPath() {
        var state = TreeExpansionState()
        state.beginSearchSession()
        state.replaceSystemExpansion(with: [root, outer])
        state.recordUserCollapsed(outer)
        state.endSearchSession()

        state.beginSearchSession()
        state.replaceSystemExpansion(with: [root, outer])

        #expect(state.systemExpandedIDs.contains(outer))
        #expect(!state.userExpandedIDs.contains(outer))
    }
}
