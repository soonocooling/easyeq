// 드래그 선택 감지 (F-02)와 수동 변환. 켜져 있을 때만 전역 모니터를 둔다.

import AppKit
import Carbon.HIToolbox

enum SelectionMonitor {
    private static var monitors: [Any] = []
    private static var mouseDownPoint = NSPoint.zero

    static var isRunning: Bool { !monitors.isEmpty }

    static func start() {
        guard monitors.isEmpty else { return }
        let down = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { _ in
            mouseDownPoint = NSEvent.mouseLocation
            // 선택 해제(빈 곳 클릭)·팝업 밖 클릭이면 닫는다.
            PopupController.close(reason: "팝업 밖 클릭")
        }
        let up = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { event in
            LiveController.scheduleRefresh()
            guard Settings.shared.dragEnabled else { return }
            let point = NSEvent.mouseLocation
            let moved = hypot(point.x - mouseDownPoint.x, point.y - mouseDownPoint.y)
            guard moved >= 4 || event.clickCount >= 2 else { return }
            let trigger = moved >= 4 ? "드래그" : "\(event.clickCount)번 클릭"
            // 선택이 안정되도록 잠깐 기다린다.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                handle(trigger: trigger, mouse: point, requireEditable: Settings.shared.editableOnly)
            }
        }
        let keys = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { _ in
            LiveController.scheduleRefresh()
        }
        monitors = [down, up, keys].compactMap { $0 }
    }

    static func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        PopupController.close(reason: "꺼짐")
    }

    /// `⌃⌥E`: 지금 선택을 바로 처리한다. 읽기 전용 글도 대상 (고르면 복사).
    static func convertCurrentSelection() {
        handle(trigger: "단축키", mouse: NSEvent.mouseLocation, requireEditable: false)
    }

    private static func handle(trigger: String, mouse: NSPoint, requireEditable: Bool) {
        guard Settings.shared.enabled,
              let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        let name = front.bundleIdentifier ?? front.localizedName ?? "?"
        if Settings.shared.isExcluded(front.bundleIdentifier) {
            Log.write("[\(name)] \(trigger): 제외 앱 → 건너뜀")
            return
        }
        if IsSecureEventInputEnabled() {
            Log.write("[\(name)] \(trigger): 보안 입력 → 건너뜀")
            return
        }
        let start = CFAbsoluteTimeGetCurrent()
        let (selection, reason) = SelectionReader.read(pid: front.processIdentifier, requireEditable: requireEditable)
        guard let selection else {
            Log.write("[\(name)] \(trigger): \(reason)")
            return
        }
        guard selection.text.count <= 200 else {
            Log.write("[\(name)] \(trigger): 200자 초과 → 무시")
            return
        }
        LiveController.scheduleRefresh()
        let opened = PopupController.open(selection, pid: front.processIdentifier, mouse: mouse)
        let elapsed = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        Log.write("[\(name)] \(trigger): 읽기=\(selection.method.rawValue) 길이=\(selection.text.count) "
            + "역할=\(selection.role) 좌표=\(selection.rect == nil ? "마우스" : "AX") "
            + (opened ? "팝업" : "후보 없음") + " \(elapsed)ms")
    }
}
