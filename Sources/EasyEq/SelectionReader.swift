// 선택 텍스트 읽기 (F-03): 접근성 → 클립보드 폴백. 좌표는 접근성으로 시도.

import AppKit
import ApplicationServices

struct Selection {
    enum Method: String { case ax = "AX", clipboard }

    let text: String
    let method: Method
    /// 선택 영역의 화면 위치 (Cocoa 좌표). 못 얻으면 nil.
    let rect: NSRect?
    let element: AXUIElement?
    /// 입력 칸이면 true, 읽기 전용이면 false, 모르면 nil.
    let editable: Bool?
    let role: String
}

enum SelectionReader {
    /// `requireEditable`이면 읽기 전용으로 확실한 곳은 읽지도 않는다 (`nil`, 사유).
    static func read(pid: pid_t, requireEditable: Bool) -> (Selection?, String) {
        let element = AX.focusedElement(pid: pid)
        let (editable, role) = AX.editability(element)
        if requireEditable, editable == false { return (nil, "입력 칸 아님 (\(role))") }

        var rect: NSRect?
        if let element, let range = AX.selectedRange(element), range.length > 0,
           let r = AX.bounds(element, range) {
            rect = cocoaRect(fromAX: r)
        }
        if let element, let text = AX.string(element, kAXSelectedTextAttribute), !text.isEmpty {
            return (Selection(text: text, method: .ax, rect: rect, element: element, editable: editable, role: role), "")
        }
        if let text = Clipboard.copySelection(), !text.isEmpty {
            return (Selection(
                text: text, method: .clipboard, rect: rect, element: element, editable: editable, role: role
            ), "")
        }
        return (nil, "선택 없음")
    }

    /// 치환 직전에 선택이 그대로인지. 접근성으로 읽은 경우에만 확인할 수 있다.
    static func isUnchanged(_ selection: Selection) -> Bool {
        guard selection.method == .ax, let element = selection.element else { return true }
        return AX.string(element, kAXSelectedTextAttribute) == selection.text
    }
}
