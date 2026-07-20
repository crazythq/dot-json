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
            width: 1,
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
        invalidateTextLayout()
    }

    /// 将当前文本存储归一化为编辑器主题属性，并保留用户当前选区。
    ///
    /// 用户输入或系统输入法有可能绕过 `setPlainText(_:)`，让 `NSTextView.string` 已经更新，
    /// 但文字属性仍是系统默认值。此时右侧解析树会更新，左侧文字却可能因为颜色太暗而不可见。
    func applyThemeAttributesToCurrentText() {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.editorFont,
            .foregroundColor: Self.editorTextColor,
        ]
        font = Self.editorFont
        textColor = Self.editorTextColor
        typingAttributes = attributes

        guard let textStorage, textStorage.length > 0 else { return }
        let selectedRanges = selectedRanges
        textStorage.beginEditing()
        textStorage.addAttributes(
            attributes,
            range: NSRange(location: 0, length: textStorage.length)
        )
        textStorage.endEditing()
        self.selectedRanges = selectedRanges
        invalidateTextLayout()
    }

    /// 让 TextKit 丢弃旧布局并重绘当前可见文本。
    ///
    /// AppKit 文本存储可能已经有内容，但如果此前在零宽容器中完成布局，正文会保持不可见。
    /// 显式失效布局可以确保后续 frame/container 更新后按真实宽度重新绘制。
    func invalidateTextLayout() {
        guard let layoutManager, let textContainer else {
            needsDisplay = true
            return
        }
        let range = NSRange(location: 0, length: max(textStorage?.length ?? 0, 0))
        layoutManager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
        layoutManager.invalidateDisplay(forCharacterRange: range)
        layoutManager.ensureLayout(for: textContainer)
        needsDisplay = true
        enclosingScrollView?.contentView.needsDisplay = true
    }

    /// 根据可视区域和实际文本尺寸更新 NSScrollView 的 document view frame。
    ///
    /// - Parameter scrollView: 承载当前文本视图的滚动视图。
    ///
    /// `NSTextView()` 初始 frame 为零；SwiftUI 不会替 AppKit 的 document view 自动建立高度。
    /// frame 至少覆盖滚动视图内容区，并在长行或多行文本超出时扩展以启用滚动。
    func updateDocumentSize(in scrollView: NSScrollView) {
        guard let layoutManager, let textContainer else { return }
        let viewport = scrollView.contentView.bounds.size
        let viewportWidth = max(viewport.width, 1)
        frame = NSRect(
            origin: .zero,
            size: NSSize(width: viewportWidth, height: max(viewport.height, 1))
        )
        textContainer.containerSize = NSSize(
            width: max(viewportWidth - textContainerInset.width * 2, 1),
            height: CGFloat.greatestFiniteMagnitude
        )
        invalidateTextLayout()
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let requiredHeight = ceil(usedRect.maxY + textContainerInset.height * 2)
        frame = NSRect(
            origin: .zero,
            size: NSSize(
                width: viewportWidth,
                height: max(viewport.height, requiredHeight, 1)
            )
        )
        invalidateTextLayout()
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

    func makeNSView(context: Context) -> NSView {
        let containerView = NSView()
        containerView.translatesAutoresizingMaskIntoConstraints = false

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
        containerView.addSubview(rulerView)
        containerView.addSubview(scrollView)
        NSLayoutConstraint.activate([
            rulerView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            rulerView.topAnchor.constraint(equalTo: containerView.topAnchor),
            rulerView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            rulerView.widthAnchor.constraint(equalToConstant: LineNumberRulerView.width),
            scrollView.leadingAnchor.constraint(equalTo: rulerView.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        context.coordinator.lineNumberRulerView = rulerView
        context.coordinator.observeScrollViewBounds(scrollView, textView: textView)
        return containerView
    }

    func updateNSView(_ containerView: NSView, context: Context) {
        guard let textView = context.coordinator.textView,
              let scrollView = context.coordinator.scrollView else { return }
        context.coordinator.synchronizeTextView(
            textView,
            rawText: viewModel.rawText,
            in: scrollView
        )
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
        var textView: JSONTextView?
        var scrollView: NSScrollView?
        var lineNumberRulerView: LineNumberRulerView?
        private var lastDocumentLayoutViewportSize: NSSize?

        init(viewModel: EditorViewModel) {
            self.viewModel = viewModel
        }

        /// 监听滚动内容区尺寸变化，在 SwiftUI 完成首帧或分栏调整后重新布局文本。
        ///
        /// - Parameters:
        ///   - scrollView: 承载文本视图的滚动容器。
        ///   - textView: 需要随可视宽度更新 frame 和 TextKit 容器的文本视图。
        func observeScrollViewBounds(_ scrollView: NSScrollView, textView: JSONTextView) {
            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.removeObserver(
                self,
                name: NSView.boundsDidChangeNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(scrollViewBoundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
        }

        /// 滚动内容区尺寸变化后重新计算 TextKit 容器，避免正文停留在零宽布局里。
        ///
        /// - Parameter notification: `NSClipView` bounds 变化通知。
        @objc private func scrollViewBoundsDidChange(_ notification: Notification) {
            guard let scrollView, let textView else { return }
            updateDocumentSizeIfViewportChanged(textView, in: scrollView)
            lineNumberRulerView?.needsDisplay = true
        }

        /// 仅在滚动视图可视区域尺寸变化时重新计算文本 document view。
        ///
        /// - Parameters:
        ///   - textView: 当前承载 JSON 输入的 AppKit 文本视图。
        ///   - scrollView: 承载文本视图的滚动容器。
        ///
        /// `NSView.boundsDidChangeNotification` 同时覆盖滚动偏移和尺寸变化。纯滚动时重置
        /// document view frame 会干扰 `NSClipView` 的当前偏移，所以这里用尺寸作为布局条件。
        func updateDocumentSizeIfViewportChanged(
            _ textView: JSONTextView,
            in scrollView: NSScrollView
        ) {
            let viewportSize = scrollView.contentView.bounds.size
            guard lastDocumentLayoutViewportSize != viewportSize else { return }
            textView.updateDocumentSize(in: scrollView)
            lastDocumentLayoutViewportSize = viewportSize
        }

        /// 同步 SwiftUI 状态到 AppKit 文本视图，并确保内容已经存在时也重新应用可见主题。
        ///
        /// - Parameters:
        ///   - textView: 当前承载 JSON 输入的 AppKit 文本视图。
        ///   - rawText: `EditorViewModel` 中的最新原始 JSON 文本。
        ///   - scrollView: 承载文本视图的滚动容器，用于更新 document view 尺寸。
        func synchronizeTextView(
            _ textView: JSONTextView,
            rawText: String,
            in scrollView: NSScrollView
        ) {
            if textView.string != rawText {
                textView.setPlainText(rawText)
            }
            textView.applyThemeAttributesToCurrentText()
            textView.updateDocumentSize(in: scrollView)
            lastDocumentLayoutViewportSize = scrollView.contentView.bounds.size
            lineNumberRulerView?.needsDisplay = true
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            textView.applyThemeAttributesToCurrentText()
            viewModel.rawText = textView.string
            if let scrollView {
                textView.updateDocumentSize(in: scrollView)
            }
            lineNumberRulerView?.needsDisplay = true
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
