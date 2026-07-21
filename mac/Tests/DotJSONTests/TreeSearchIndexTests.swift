import DotJSONCore
import Foundation
import Testing
@testable import DotJSON

/// 树搜索索引的正确性与性能回归测试。
struct TreeSearchIndexTests {
    /// 单行紧凑 JSON 中的重复 key 必须映射到不同树节点，而不是依赖源码行列猜测。
    @Test func compactJSONRepeatedKeysHaveDistinctNodeIdentities() throws {
        let root = try JSONParser.parse(
            #"{"rows":[{"rowIndex":1},{"rowIndex":2}]}"#
        )
        let index = TreeSearchIndex(root: root)

        let matches = index.matches(query: "rowIndex")

        #expect(matches.count == 2)
        #expect(matches.allSatisfy { $0.field == .key })
        #expect(Set(matches.map(\.nodeID)).count == 2)
    }

    /// 相同 value 出现在不同节点时，每一项都必须能独立导航。
    @Test func repeatedValuesHaveDistinctNodeIdentities() throws {
        let root = try JSONParser.parse(
            #"{"first":{"label":"same"},"second":{"label":"same"}}"#
        )
        let index = TreeSearchIndex(root: root)

        let matches = index.matches(query: "same")

        #expect(matches.count == 2)
        #expect(matches.allSatisfy { $0.field == .value })
        #expect(Set(matches.map(\.nodeID)).count == 2)
    }

    /// 命中结果应直接携带祖先身份，导航时不需要重新 DFS 整棵树。
    @Test func deepMatchContainsOrderedAncestorChain() throws {
        let root = try JSONParser.parse(
            #"{"outer":{"items":[{"target":"found"}]}}"#
        )
        let index = TreeSearchIndex(root: root)

        let match = try #require(index.matches(query: "found").first)

        #expect(match.nodeID.components == [
            .key("outer"),
            .key("items"),
            .index(0),
            .key("target"),
        ])
        #expect(match.ancestorIDs.map(\.components) == [
            [],
            [.key("outer")],
            [.key("outer"), .key("items")],
            [.key("outer"), .key("items"), .index(0)],
        ])
    }

    /// 搜索 key 和显示 value 时应保存命中范围，供单个树行做精确高亮。
    @Test func matchRangeUsesUTF16Coordinates() throws {
        let root = try JSONParser.parse(#"{"标题":"前缀目标后缀"}"#)
        let index = TreeSearchIndex(root: root)

        let match = try #require(index.matches(query: "目标").first)

        #expect(match.matchRange == NSRange(location: 3, length: 2))
        #expect(match.field == .value)
    }

    /// 十万叶子节点的建索引与查询总耗时必须低于用户可感知的三秒上限。
    @Test func largeTreeIndexAndQueryCompleteWithinThreeSeconds() {
        let rows = (0..<100_000).map { index in
            JSONNode.object([
                (key: "rowIndex", value: .number(String(index))),
                (key: "label", value: .string(index == 99_999 ? "needle" : "other")),
            ])
        }
        let root = JSONNode.object([
            (key: "rows", value: .array(rows)),
        ])
        let clock = ContinuousClock()

        let duration = clock.measure {
            let index = TreeSearchIndex(root: root)
            let matches = index.matches(query: "needle")
            #expect(matches.count == 1)
        }

        #expect(duration < .seconds(3))
    }
}
