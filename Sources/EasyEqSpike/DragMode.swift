// 드래그 모드: 텍스트를 드래그하면 선택 위치에 후보 팝업을 띄운다.

import AppKit
import Carbon.HIToolbox
import FormulaCore

enum DragMode {
    private(set) static var panel: NSPanel?
    private static var choices: [String] = []
    private static var targetPID: pid_t = 0

    static var isOpen: Bool { panel != nil }
    /// 입력 칸에서 드래그했을 때만 팝업을 띄운다 (메뉴에서 끌 수 있음).
    static var onlyEditable = true

    static func handleSelection(mouse: NSPoint, trigger: String) {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        let name = front.bundleIdentifier ?? front.localizedName ?? "?"
        if IsSecureEventInputEnabled() {
            log("[\(name)] 보안 입력 모드 → 건너뜀")
            return
        }
        let start = CFAbsoluteTimeGetCurrent()
        // 입력 칸이 아닌 곳(웹 페이지 본문 등)을 드래그한 것이면 읽지도 않는다.
        let (editable, role) = editability(pid: front.processIdentifier)
        if onlyEditable, editable == false {
            log("[\(name)] \(trigger): 입력 칸 아님 (\(role)) → 건너뜀")
            return
        }
        guard let selection = readSelection(pid: front.processIdentifier) else {
            log("[\(name)] \(trigger): 선택 없음 (AX·클립보드 모두)")
            return
        }
        guard selection.text.count <= FormulaEngine.maxInputLength else {
            log("[\(name)] \(trigger): 200자 초과 → 무시")
            return
        }
        let candidates = engine.candidates(for: selection.text).map { $0.text(for: .unicode) }
        let elapsed = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        let summary = "[\(name)] \(trigger): 읽기=\(selection.method) 길이=\(selection.text.count) "
            + "좌표=\(selection.rect == nil ? "마우스 폴백" : "AX") 역할=\(role)"
            + "(\(editable.map { $0 ? "입력칸" : "읽기전용" } ?? "모름")) 파서후보=\(candidates.count)"
        // 수식이 아니면 팝업을 띄우지 않는다.
        guard !candidates.isEmpty else {
            log(summary + " → 팝업 생략 \(elapsed)ms")
            return
        }
        choices = candidates
        targetPID = front.processIdentifier
        show(near: selection.rect, mouse: mouse)
        let tapOK = KeyTap.setEnabled(true)
        log(summary + " 키탭=\(tapOK ? "OK" : "실패") \(elapsed)ms")
    }

    static func close(reason: String) {
        guard let current = panel else { return }
        current.orderOut(nil)
        panel = nil
        KeyTap.refresh()
        log("  팝업 닫힘: \(reason)")
    }

    static func choose(_ index: Int, via: String) {
        guard panel != nil, index < choices.count else { return }
        let text = choices[index]
        close(reason: "후보 \(index + 1) 선택 (\(via))")
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID else {
            log("  치환 취소: 포커스 앱이 바뀜")
            return
        }
        pasteReplacingSelection(with: text)
    }

    /// 팝업이 열린 동안의 키 처리. true면 키를 삼킨다.
    static func handleKey(_ keyCode: Int) -> Bool {
        let digits = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5]
        if let index = digits.firstIndex(of: keyCode) {
            DispatchQueue.main.async { choose(index, via: "숫자키") }
            return true
        }
        switch keyCode {
        case kVK_Return:
            DispatchQueue.main.async { choose(0, via: "enter") }
            return true
        case kVK_Escape, kVK_ANSI_0:
            DispatchQueue.main.async { close(reason: "esc/0 (원문 유지)") }
            return true
        default:
            DispatchQueue.main.async { close(reason: "다른 키 → 통과") }
            return false
        }
    }

    private static func show(near rect: CGRect?, mouse: NSPoint) {
        var rows: [NSView] = choices.enumerated().map { index, choice in
            CandidateRow(key: "\(index + 1)", title: choice) { choose(index, via: "클릭") }
        }
        rows.append(CandidateRow(key: "0", title: "원문 유지 (Esc)", secondary: true) {
            close(reason: "원문 유지 클릭")
        })
        let (content, size) = makePanelContent(rows)

        var anchor = NSRect(x: mouse.x, y: mouse.y, width: 1, height: 16)
        if let rect { anchor = cocoaRect(fromAX: rect) }
        let origin = panelOrigin(size: size, near: anchor, above: true)

        let newPanel = makeNonActivatingPanel(frame: NSRect(origin: origin, size: size))
        newPanel.contentView = content
        newPanel.orderFrontRegardless()
        panel = newPanel
    }
}
