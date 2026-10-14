// 잠깐 떴다 사라지는 알림 ("복사됨").

import AppKit

enum Toast {
    private static var panel: NSPanel?
    private static var hideWork: DispatchWorkItem?

    static func show(_ message: String, near anchor: NSRect) {
        let (content, size) = PanelFactory.content([PanelFactory.label(message, size: 13, color: .labelColor)])
        let current = panel ?? PanelFactory.panel()
        current.ignoresMouseEvents = true
        current.contentView = content
        current.setFrame(NSRect(origin: PanelFactory.origin(size: size, near: anchor, above: true), size: size), display: true)
        current.alphaValue = 1
        current.orderFrontRegardless()
        panel = current

        hideWork?.cancel()
        let work = DispatchWorkItem {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                current.animator().alphaValue = 0
            }, completionHandler: { current.orderOut(nil) })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }
}
