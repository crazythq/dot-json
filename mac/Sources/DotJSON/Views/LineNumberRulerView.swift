import AppKit

/// 为 JSON 文本编辑器绘制独立行号栏，并突出显示解析失败所在行。
///
/// 该视图只绘制当前可见字符范围，避免大文件滚动时遍历全文。错误原因通过
/// AppKit tooltip 绑定在红色行号上，满足“标红行号并悬停查看原因”的交互要求。
@MainActor
final class LineNumberRulerView: NSView, NSViewToolTipOwner {
    /// 行号栏固定宽度。
    static let width: CGFloat = 46

    /// 当前需要标红的行号；0 表示没有可定位的 JSON 错误。
    private(set) var errorLineNumber = 0

    /// 悬停错误行号时显示的解析错误。
    private(set) var errorMessage: String?

    /// 承载 `NSTextView` 的滚动视图，用于获取当前可见区域。
    private weak var scrollView: NSScrollView?

    /// 当前行号栏对应的文本编辑器。
    weak var clientView: NSTextView?

    /// 使用和 `NSTextView` 一致的顶部原点坐标，保证行号与正文首行对齐。
    override var isFlipped: Bool { true }

    /// 创建绑定到指定滚动视图的行号栏。
    ///
    /// - Parameter scrollView: 承载 `NSTextView` 的滚动视图。
    init(scrollView: NSScrollView) {
        self.scrollView = scrollView
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 0))
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("LineNumberRulerView 不支持从 Interface Builder 创建")
    }

    /// 更新需要标记的错误行和悬停文案。
    ///
    /// - Parameters:
    ///   - lineNumber: 从 1 开始的错误行；0 表示清除标记。
    ///   - message: 对应的解析错误说明。
    func updateError(lineNumber: Int, message: String?) {
        errorLineNumber = max(0, lineNumber)
        errorMessage = message
        needsDisplay = true
    }

    /// 绘制背景、可见行号以及错误行的 tooltip 热区。
    ///
    /// - Parameter dirtyRect: AppKit 请求重绘的区域。
    override func draw(_ dirtyRect: NSRect) {
        guard let textView = clientView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let scrollView else {
            return
        }

        NSColor(hex: "#1e1e1e").setFill()
        dirtyRect.fill()
        removeAllToolTips()

        let visibleRect = scrollView.contentView.bounds
        let visibleGlyphRange = layoutManager.glyphRange(
            forBoundingRect: visibleRect,
            in: textContainer
        )
        let visibleCharacterRange = layoutManager.characterRange(
            forGlyphRange: visibleGlyphRange,
            actualGlyphRange: nil
        )
        drawVisibleLineNumbers(
            in: visibleCharacterRange,
            textView: textView,
            layoutManager: layoutManager,
            visibleRect: visibleRect
        )
    }

    /// 逐行绘制可见字符范围，并为错误行安装悬停提示。
    ///
    /// - Parameters:
    ///   - characterRange: 当前可见的字符范围。
    ///   - textView: 提供文本、字体和容器原点的编辑器。
    ///   - layoutManager: 负责把字符位置转换为屏幕位置的布局管理器。
    ///   - visibleRect: 滚动视图当前可见区域。
    private func drawVisibleLineNumbers(
        in characterRange: NSRange,
        textView: NSTextView,
        layoutManager: NSLayoutManager,
        visibleRect: NSRect
    ) {
        let text = textView.string as NSString
        var characterIndex = text.lineRange(
            for: NSRange(location: min(characterRange.location, text.length), length: 0)
        ).location
        var lineNumber = lineNumber(at: characterIndex, in: text)
        let visibleEnd = min(NSMaxRange(characterRange), text.length)

        repeat {
            let lineRange = text.lineRange(
                for: NSRange(location: min(characterIndex, text.length), length: 0)
            )
            drawLineNumber(
                lineNumber,
                characterIndex: min(characterIndex, max(text.length - 1, 0)),
                textIsEmpty: text.length == 0,
                textView: textView,
                layoutManager: layoutManager,
                visibleRect: visibleRect
            )

            let nextIndex = NSMaxRange(lineRange)
            guard nextIndex > characterIndex else { break }
            characterIndex = nextIndex
            lineNumber += 1
        } while characterIndex <= visibleEnd && characterIndex < text.length
    }

    /// 计算指定 UTF-16 字符位置对应的从 1 开始行号。
    ///
    /// - Parameters:
    ///   - characterIndex: NSString 使用的 UTF-16 字符位置。
    ///   - text: 完整编辑文本。
    /// - Returns: 从 1 开始的行号。
    private func lineNumber(at characterIndex: Int, in text: NSString) -> Int {
        guard characterIndex > 0 else { return 1 }
        let prefix = text.substring(to: min(characterIndex, text.length))
        return prefix.reduce(into: 1) { line, character in
            if character == "\n" { line += 1 }
        }
    }

    /// 绘制单个行号。
    ///
    /// - Parameters:
    ///   - lineNumber: 从 1 开始的行号。
    ///   - characterIndex: 该行首字符的 UTF-16 位置。
    ///   - textIsEmpty: 文档是否为空；空文档仍显示第 1 行。
    ///   - textView: 编辑器视图。
    ///   - layoutManager: 文本布局管理器。
    ///   - visibleRect: 当前滚动位置。
    private func drawLineNumber(
        _ lineNumber: Int,
        characterIndex: Int,
        textIsEmpty: Bool,
        textView: NSTextView,
        layoutManager: NSLayoutManager,
        visibleRect: NSRect
    ) {
        let y: CGFloat
        if textIsEmpty {
            y = textView.textContainerOrigin.y - visibleRect.minY
        } else {
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: characterIndex)
            let fragmentRect = layoutManager.lineFragmentRect(
                forGlyphAt: glyphIndex,
                effectiveRange: nil
            )
            y = fragmentRect.minY + textView.textContainerOrigin.y - visibleRect.minY
        }

        let isError = lineNumber == errorLineNumber
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: isError ? .semibold : .regular),
            .foregroundColor: isError ? NSColor(hex: "#f87171") : NSColor(hex: "#6b7280"),
        ]
        let label = NSAttributedString(string: String(lineNumber), attributes: attributes)
        let labelSize = label.size()
        let labelRect = NSRect(
            x: Self.width - labelSize.width - 8,
            y: y,
            width: labelSize.width,
            height: max(labelSize.height, textView.font?.pointSize ?? 13)
        )
        label.draw(in: labelRect)

        if isError, errorMessage != nil {
            addToolTip(labelRect.insetBy(dx: -6, dy: -2), owner: self, userData: nil)
        }
    }

    /// 为错误行号 tooltip 提供错误说明。
    func view(
        _ view: NSView,
        stringForToolTip tag: NSView.ToolTipTag,
        point: NSPoint,
        userData data: UnsafeMutableRawPointer?
    ) -> String {
        errorMessage ?? "JSON 格式错误"
    }
}
