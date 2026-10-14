// 드래그(또는 ⌃⌥E)로 연 후보 팝업 (F-05~F-08).

import AppKit
import Carbon.HIToolbox
import FormulaCore

enum PopupController {
    private static var panel: NSPanel?
    private static var selection: Selection?
    private static var anchor = NSRect.zero
    private static var pid: pid_t = 0
    private static var candidates: [Candidate] = []
    private static var format = OutputFormat.unicode
    private static var highlighted = 0
    private static var rows: [CandidateRow] = []
    /// 읽기 전용 글이면 붙여 넣지 않고 복사만 한다 (F-07 엣지 케이스).
    private static var copyOnly = false

    static var isOpen: Bool { panel?.isVisible == true }

    /// 후보가 있으면 팝업을 띄우고 true.
    @discardableResult
    static func open(_ selection: Selection, pid: pid_t, mouse: NSPoint) -> Bool {
        let settings = Settings.shared
        let found = engine.candidates(for: selection.text, format: settings.format, options: settings.engineOptions)
        guard !found.isEmpty else { return false }
        self.selection = selection
        self.pid = pid
        candidates = found
        format = settings.format
        highlighted = 0
        copyOnly = selection.editable == false
        anchor = selection.rect ?? NSRect(x: mouse.x, y: mouse.y - 8, width: 1, height: 16)
        render()
        KeyInterceptor.refresh()
        return true
    }

    static func close(reason: String) {
        guard isOpen else { return }
        panel?.orderOut(nil)
        selection = nil
        candidates = []
        KeyInterceptor.refresh()
        Log.write("  팝업 닫힘: \(reason)")
    }

    /// 팝업이 열린 동안의 키. true면 키를 삼킨다 (대상 앱에 전달하지 않음).
    static func handleKey(_ keyCode: Int, flags: CGEventFlags) -> Bool {
        let commandLike = flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate)
        let digits = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5]
        if !commandLike, Settings.shared.numberKeys, let index = digits.firstIndex(of: keyCode) {
            guard index < candidates.count else { return true }
            DispatchQueue.main.async { choose(index, via: "숫자키") }
            return true
        }
        if commandLike {
            // ⌘C 같은 단축키는 대상 앱에 그대로 보내고 팝업만 닫는다.
            DispatchQueue.main.async { close(reason: "다른 키") }
            return false
        }
        switch keyCode {
        case kVK_Return, kVK_ANSI_KeypadEnter:
            DispatchQueue.main.async { choose(highlighted, via: "enter") }
            return true
        case kVK_DownArrow:
            DispatchQueue.main.async { move(1) }
            return true
        case kVK_UpArrow:
            DispatchQueue.main.async { move(-1) }
            return true
        case kVK_Tab:
            DispatchQueue.main.async { toggleFormat() }
            return true
        case kVK_Escape:
            DispatchQueue.main.async { close(reason: "esc") }
            return true
        case kVK_ANSI_0 where Settings.shared.numberKeys:
            DispatchQueue.main.async { close(reason: "0 (원문 유지)") }
            return true
        default:
            // 그 밖의 키는 대상 앱에 그대로 보내고 팝업만 닫는다.
            DispatchQueue.main.async { close(reason: "다른 키") }
            return false
        }
    }

    private static func move(_ delta: Int) {
        guard !candidates.isEmpty else { return }
        highlighted = (highlighted + delta + candidates.count) % candidates.count
        for (i, row) in rows.enumerated() { row.highlighted = i == highlighted }
    }

    /// Tab: 이 팝업의 후보 전체를 유니코드 ↔ LaTeX로 바꾼다.
    private static func toggleFormat() {
        guard let selection else { return }
        format = format == .unicode ? .latex : .unicode
        let found = engine.candidates(for: selection.text, format: format, options: Settings.shared.engineOptions)
        if !found.isEmpty { candidates = found }
        highlighted = min(highlighted, candidates.count - 1)
        render()
    }

    private static func choose(_ index: Int, via: String) {
        guard isOpen, let selection, index < candidates.count else { return }
        let text = candidates[index].text(for: format)
        let copyOnly = self.copyOnly
        close(reason: "후보 \(index + 1) 선택 (\(via))")
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
            Log.write("  치환 취소: 포커스 앱이 바뀜")
            return
        }
        if copyOnly {
            TextInserter.copy(text)
            Toast.show("복사됨  \(text)", near: anchor)
            Log.write("  읽기 전용 → 클립보드에 복사")
            return
        }
        guard SelectionReader.isUnchanged(selection) else {
            Log.write("  치환 취소: 선택이 바뀜")
            return
        }
        TextInserter.replaceSelection(with: text)
        Log.write("  ⌘V 치환")
    }

    private static func render() {
        rows = candidates.enumerated().map { index, candidate in
            let row = PanelFactory.row(candidate, key: "\(index + 1)", format: format) { choose(index, via: "클릭") }
            row.highlighted = index == highlighted
            return row
        }
        var views: [NSView] = rows
        views.append(CandidateRow(key: "0", title: "원문 유지", secondary: true) { close(reason: "원문 유지 클릭") })
        let hint = (format == .unicode ? "Tab → LaTeX" : "Tab → 유니코드") + (copyOnly ? "  ·  고르면 복사됩니다" : "")
        views.append(PanelFactory.label(hint, size: 10, color: .tertiaryLabelColor))
        let (content, size) = PanelFactory.content(views)
        let current = panel ?? PanelFactory.panel()
        current.contentView = content
        current.setFrame(NSRect(origin: PanelFactory.origin(size: size, near: anchor, above: true), size: size), display: true)
        current.orderFrontRegardless()
        panel = current
    }
}
