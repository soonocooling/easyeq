// 후보 목록 UI (F-06). 대상 앱의 포커스를 빼앗지 않는 비활성 패널 위에 고를 수 있는 행을 놓는다.

import AppKit
import FormulaCore

/// 후보 한 줄. 클릭으로 고를 수 있고, 키보드 하이라이트를 표시한다. 앱이 비활성이어도 첫 클릭을 받는다.
final class CandidateRow: NSView {
    private let action: () -> Void
    private var hovering = false { didSet { needsDisplay = true } }
    var highlighted = false { didSet { needsDisplay = true } }

    init(key: String, title: String, detail: String? = nil, badge: String? = nil, secondary: Bool = false,
         action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)

        let keyLabel = NSTextField(labelWithString: key)
        keyLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        keyLabel.textColor = .secondaryLabelColor
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 15)
        titleLabel.textColor = secondary ? .secondaryLabelColor : .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail

        var views: [NSView] = [keyLabel, titleLabel]
        if let detail {
            let detailLabel = NSTextField(labelWithString: detail)
            detailLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            detailLabel.textColor = .secondaryLabelColor
            detailLabel.lineBreakMode = .byTruncatingTail
            views.append(detailLabel)
        }
        if let badge {
            let badgeLabel = NSTextField(labelWithString: badge)
            badgeLabel.font = .systemFont(ofSize: 10, weight: .semibold)
            badgeLabel.textColor = .systemOrange
            views.append(badgeLabel)
        }
        let stack = NSStackView(views: views)
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 3, left: 8, bottom: 3, right: 10)
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(lessThanOrEqualToConstant: 520),
        ])
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { action() }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard hovering || highlighted else { return }
        NSColor.controlAccentColor.withAlphaComponent(highlighted ? 0.3 : 0.18).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
    }
}

enum PanelFactory {
    static func panel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }

    /// 둥근 반투명 배경 위에 세로로 쌓은 내용과 그 크기.
    static func content(_ views: [NSView]) -> (view: NSView, size: NSSize) {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 4, bottom: 6, right: 4)
        for view in views where view is CandidateRow {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -8).isActive = true
        }
        let background = NSVisualEffectView()
        background.material = .menu
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        background.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        return (background, stack.fittingSize)
    }

    static func label(_ text: String, size: CGFloat = 11, color: NSColor = .secondaryLabelColor) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size)
        label.textColor = color
        label.lineBreakMode = .byTruncatingTail
        let stack = NSStackView(views: [label])
        stack.edgeInsets = NSEdgeInsets(top: 1, left: 8, bottom: 1, right: 8)
        return stack
    }

    /// 후보 행. LaTeX 형식이면 미리보기는 유니코드, 삽입될 LaTeX는 보조로 표시한다 (F-06).
    static func row(_ candidate: Candidate, key: String, format: OutputFormat, action: @escaping () -> Void) -> CandidateRow {
        let showsLatex = format == .latex || candidate.needsLatex
        return CandidateRow(
            key: key,
            title: candidate.needsLatex && format == .unicode ? candidate.latex : candidate.unicode,
            detail: format == .latex ? candidate.latex : nil,
            badge: showsLatex && candidate.needsLatex ? "LaTeX" : nil,
            action: action
        )
    }

    /// `anchor` 위(또는 아래)에 붙인 패널 위치. 화면을 벗어나면 반대쪽으로 넘기고 좌우를 화면 안으로 맞춘다.
    static func origin(size: NSSize, near anchor: NSRect, above: Bool) -> NSPoint {
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)) }
            ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let aboveY = anchor.maxY + 6
        let belowY = anchor.minY - size.height - 6
        var origin = NSPoint(x: anchor.minX, y: above ? aboveY : belowY)
        if above, origin.y + size.height > visible.maxY { origin.y = belowY }
        if !above, origin.y < visible.minY { origin.y = aboveY }
        origin.y = min(max(origin.y, visible.minY + 4), visible.maxY - size.height - 4)
        origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - size.width - 4)
        return origin
    }
}
