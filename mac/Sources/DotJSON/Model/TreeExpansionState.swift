import Foundation

/// 区分用户展开状态与系统搜索定位产生的临时展开状态。
///
/// `userExpandedIDs` 是唯一持久真相源。搜索只能写入 `systemExpandedIDs`；搜索期间用户主动
/// 收起的节点会进入本次会话的阻止集合，后续结果切换不得再次强行展开。
struct TreeExpansionState: Sendable {
    /// 用户明确展开并希望保留的节点。
    private(set) var userExpandedIDs: Set<TreeNodeID> = []

    /// 当前搜索结果定位所需的临时展开节点。
    private(set) var systemExpandedIDs: Set<TreeNodeID> = []

    /// 当前搜索会话中被用户明确收起的节点。
    private var userBlockedSystemIDs: Set<TreeNodeID> = []

    /// 是否处于一次搜索会话中。
    private var isSearchSessionActive = false

    /// 当前界面应该呈现为展开的节点集合。
    var effectiveExpandedIDs: Set<TreeNodeID> {
        userExpandedIDs.union(systemExpandedIDs)
    }

    /// 开始新的搜索会话并清除上一会话的临时状态。
    mutating func beginSearchSession() {
        isSearchSessionActive = true
        systemExpandedIDs.removeAll(keepingCapacity: true)
        userBlockedSystemIDs.removeAll(keepingCapacity: true)
    }

    /// 结束搜索并只保留用户状态。
    mutating func endSearchSession() {
        isSearchSessionActive = false
        systemExpandedIDs.removeAll(keepingCapacity: true)
        userBlockedSystemIDs.removeAll(keepingCapacity: true)
    }

    /// 记录一次用户主动展开。
    ///
    /// - Parameter nodeID: 用户展开的稳定节点身份。
    mutating func recordUserExpanded(_ nodeID: TreeNodeID) {
        userExpandedIDs.insert(nodeID)
        systemExpandedIDs.remove(nodeID)
        userBlockedSystemIDs.remove(nodeID)
    }

    /// 记录一次用户主动收起。
    ///
    /// - Parameter nodeID: 用户收起的稳定节点身份。
    ///
    /// 搜索会话中的用户收起会阻止后续系统定位再次展开同一节点，保证用户操作优先。
    mutating func recordUserCollapsed(_ nodeID: TreeNodeID) {
        userExpandedIDs.remove(nodeID)
        systemExpandedIDs.remove(nodeID)
        if isSearchSessionActive {
            userBlockedSystemIDs.insert(nodeID)
        }
    }

    /// 用当前结果的祖先链替换上一条结果的临时展开路径。
    ///
    /// - Parameter nodeIDs: 当前搜索结果需要临时展开的祖先身份。
    mutating func replaceSystemExpansion(with nodeIDs: [TreeNodeID]) {
        guard isSearchSessionActive else {
            systemExpandedIDs.removeAll(keepingCapacity: true)
            return
        }
        systemExpandedIDs = Set(nodeIDs).subtracting(userBlockedSystemIDs)
    }
}
