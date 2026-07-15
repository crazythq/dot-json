import Foundation

struct SearchResult: Identifiable, Equatable {
    let id = UUID()
    let lineNumber: Int
    let column: Int
    let matchedText: String
    let isKey: Bool
}
