// 후보 목록 UI. 대상 앱의 포커스를 빼앗지 않는 비활성 패널 위에 클릭 가능한 행을 놓는다.

import AppKit

/// 마우스로 고를 수 있는 후보 한 줄. 앱이 비활성이어도 첫 클릭을 받는다.
final class CandidateRow: NSView {
    private let action: () -> Void
    private var hovering = false {
        didSet { needsDisplay = true }
    }

    init(key: String, title: String, secondary: Bool = false, action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)

        let keyLabel = NSTextField(labelWithString: key)
        keyLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        keyLabel.textColor = .secondaryLabelColor
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 15)
        titleLabel.textColor = secondary ? .secondaryLabelColor : .labelColor

        let stack = NSStackView(views: [keyLabel, titleLabel])
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 3, left: 8, bottom: 3, right: 10)
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
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
    // 패널 배경 드래그(창 이동)로 넘어가지 않게 행에서 처리한다.
    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { action() }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard hovering else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.25).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
    }
}

/// 둥근 반투명 배경 위에 세로로 쌓은 내용.
func makePanelContent(_ views: [NSView]) -> (view: NSView, size: NSSize) {
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

func makeNonActivatingPanel(frame: NSRect) -> NSPanel {
    let panel = NSPanel(
        contentRect: frame,
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

func makeLabel(_ text: String, size: CGFloat = 12, color: NSColor = .secondaryLabelColor) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = .systemFont(ofSize: size)
    label.textColor = color
    label.lineBreakMode = .byTruncatingTail
    return label
}

/// 접근성 좌표(주 화면 좌상단 원점)를 Cocoa 좌표(좌하단 원점)로 바꾼다.
func cocoaRect(fromAX r: CGRect) -> NSRect {
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    return NSRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
}

/// `anchor` 옆에 붙인 패널의 위치. 화면을 벗어나면 반대쪽으로 넘긴다.
func panelOrigin(size: NSSize, near anchor: NSRect, above: Bool) -> NSPoint {
    let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)) }
        ?? NSScreen.main
    let visible = screen?.visibleFrame ?? .zero
    let aboveY = anchor.maxY + 6
    let belowY = anchor.minY - size.height - 6
    var origin = NSPoint(x: anchor.minX, y: above ? aboveY : belowY)
    if above, origin.y + size.height > visible.maxY { origin.y = belowY }
    if !above, origin.y < visible.minY { origin.y = aboveY }
    origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - size.width - 4)
    return origin
}
