import SwiftUI
import AppKit

/// 拦截系统标准粘贴动作，使 ⌘V 与工具栏粘贴使用同一自动格式化流程。
@MainActor
final class JSONTextView: NSTextView {
    /// 编辑器固定使用的等宽字体。
    fileprivate static let editorFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    /// 深色主题下的固定文本颜色。
    fileprivate static let editorTextColor = NSColor(hex: "#d4d4d4")

    /// 测试时可替换的粘贴板；生产环境默认使用系统通用粘贴板。
    var sourcePasteboard: NSPasteboard = .general

    /// 获取到文本时调用的业务处理闭包。
    var onPaste: ((String) -> Void)?

    /// 配置为 NSScrollView 的可滚动深色纯文本 document view。
    ///
    /// 允许垂直扩展并让文本容器跟随视口宽度，长 JSON 行自动换行。
    /// 这样避免无限宽 TextKit 容器在不同 SDK 下产生不可绘制的布局结果。
    func configureForScrolling() {
        let themeAttributes: [NSAttributedString.Key: Any] = [
            .font: Self.editorFont,
            .foregroundColor: Self.editorTextColor,
        ]
        font = Self.editorFont
        textColor = Self.editorTextColor
        typingAttributes = themeAttributes
        minSize = .zero
        maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textContainer?.widthTracksTextView = true
    }

    /// 以固定深色主题属性替换编辑器全文。
    ///
    /// - Parameter text: 要显示的 JSON 纯文本。
    ///
    /// 直接写入 `NSTextView.string` 时，新字符可能使用系统默认黑色。这里显式设置全文属性，
    /// 并同步 typing attributes，确保程序化更新和后续键盘输入都保持可见。
    func setPlainText(_ text: String) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.editorFont,
            .foregroundColor: Self.editorTextColor,
        ]
        textStorage?.setAttributedString(NSAttributedString(string: text, attributes: attributes))
        typingAttributes = attributes
    }

    /// 根据可视区域和实际文本尺寸更新 NSScrollView 的 document view frame。
    ///
    /// - Parameter scrollView: 承载当前文本视图的滚动视图。
    ///
    /// `NSTextView()` 初始 frame 为零；SwiftUI 不会替 AppKit 的 document view 自动建立高度。
    /// frame 至少覆盖滚动视图内容区，并在长行或多行文本超出时扩展以启用滚动。
    func updateDocumentSize(in scrollView: NSScrollView) {
        guard let layoutManager, let textContainer else { return }
        let viewport = scrollView.contentSize
        let viewportWidth = max(viewport.width, 1)
        frame.size.width = viewportWidth
        textContainer.containerSize = NSSize(
            width: max(viewportWidth - textContainerInset.width * 2, 1),
            height: CGFloat.greatestFiniteMagnitude
        )
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let requiredHeight = ceil(usedRect.maxY + textContainerInset.height * 2)
        frame.size = NSSize(
            width: viewportWidth,
            height: max(viewport.height, requiredHeight, 1)
        )
    }

    /// 读取纯文本并转交 ViewModel；没有纯文本时不执行任何操作。
    ///
    /// - Parameter sender: 触发粘贴动作的菜单项或响应链对象。
    override func paste(_ sender: Any?) {
        // JSON 编辑器只接受纯文本，不能让富文本通过父类实现绕过格式化与校验。
        guard let text = sourcePasteboard.string(forType: .string) else { return }
        onPaste?(text)
    }
}

/// Wraps NSTextView with proper dark-theme colors and reliable focus handling.
struct TextEditorView: NSViewRepresentable {
    @Environment(EditorViewModel.self) private var viewModel

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = NSColor(hex: "#1e1e1e")
        scrollView.drawsBackground = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let textView = JSONTextView()
        textView.configureForScrolling()
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.font = JSONTextView.editorFont
        textView.textColor = JSONTextView.editorTextColor
        textView.backgroundColor = NSColor(hex: "#1e1e1e")
        textView.insertionPointColor = NSColor.white
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: 16, height: 12)
        textView.delegate = context.coordinator
        textView.onPaste = { [weak coordinator = context.coordinator] text in
            coordinator?.pasteAndFormat(text)
        }
        textView.allowsCharacterPickerTouchBarItem = false

        scrollView.documentView = textView
        let rulerView = LineNumberRulerView(scrollView: scrollView)
        rulerView.clientView = textView
        scrollView.verticalRulerView = rulerView
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        context.coordinator.lineNumberRulerView = rulerView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        if textView.string != viewModel.rawText {
            textView.setPlainText(viewModel.rawText)
        }
        textView.updateDocumentSize(in: scrollView)
        context.coordinator.lineNumberRulerView?.updateError(
            lineNumber: viewModel.errorLineNumber,
            message: viewModel.errorMessage
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var viewModel: EditorViewModel
        weak var textView: JSONTextView?
        weak var scrollView: NSScrollView?
        weak var lineNumberRulerView: LineNumberRulerView?

        init(viewModel: EditorViewModel) {
            self.viewModel = viewModel
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            viewModel.rawText = textView.string
            if let scrollView {
                textView.updateDocumentSize(in: scrollView)
            }
            lineNumberRulerView?.updateError(
                lineNumber: viewModel.errorLineNumber,
                message: viewModel.errorMessage
            )
        }

        /// 将标准粘贴动作交给 ViewModel 自动格式化并触发校验。
        ///
        /// - Parameter text: 系统粘贴板中的纯文本。
        func pasteAndFormat(_ text: String) {
            viewModel.pasteAndFormat(text)
        }
    }
}
