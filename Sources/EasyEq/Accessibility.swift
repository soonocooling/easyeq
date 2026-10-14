// 접근성(AX) API 도우미.

import AppKit
import ApplicationServices

enum AX {
    /// 앞에 있는 앱의 포커스된 요소. Electron/Chromium 앱은 접근성 트리를 먼저 켠다.
    static func focusedElement(pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        return (focused as! AXUIElement)
    }

    static func string(_ element: AXUIElement, _ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? String
    }

    static func selectedRange(_ element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        return AXValueGetValue(value as! AXValue, .cfRange, &range) ? range : nil
    }

    static func setSelectedRange(_ element: AXUIElement, _ range: CFRange) -> Bool {
        var range = range
        guard let value = AXValueCreate(.cfRange, &range) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success
    }

    /// 텍스트 범위의 화면 위치 (접근성 좌표: 주 화면 좌상단 원점).
    static func bounds(_ element: AXUIElement, _ range: CFRange) -> CGRect? {
        var range = range
        guard let rangeValue = AXValueCreate(.cfRange, &range) else { return nil }
        var bounds: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, rangeValue, &bounds
        ) == .success, let bounds, CFGetTypeID(bounds) == AXValueGetTypeID() else { return nil }
        var r = CGRect.zero
        guard AXValueGetValue(bounds as! AXValue, .cgRect, &r), r.width > 0 || r.height > 0 else { return nil }
        return r
    }

    /// 요소 전체의 화면 위치 (접근성 좌표).
    static func frame(_ element: AXUIElement) -> CGRect? {
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        return CGRect(origin: origin, size: extent)
    }

    /// 글을 고칠 수 있는 입력 칸인지. 웹 본문 같은 읽기 전용이면 false, 판단할 수 없으면 nil.
    static func editability(_ element: AXUIElement?) -> (editable: Bool?, role: String) {
        guard let element else { return (nil, "없음") }
        let role = string(element, kAXRoleAttribute) ?? "?"
        let textRoles: Set<String> = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole]
        if textRoles.contains(role) { return (true, role) }
        var settable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success,
           settable.boolValue {
            return (true, role)
        }
        // 읽기 전용으로 확실한 역할만 false. 그 밖(Word 문서 등)은 판단 보류.
        let readOnlyRoles: Set<String> = [
            "AXWebArea", kAXStaticTextRole, kAXGroupRole, kAXScrollAreaRole, "AXLink", "AXHeading",
            kAXListRole, kAXTableRole, kAXCellRole, kAXRowRole, kAXOutlineRole, kAXImageRole, kAXButtonRole,
            kAXWindowRole, kAXApplicationRole,
        ]
        return (readOnlyRoles.contains(role) ? false : nil, role)
    }
}

/// 접근성 좌표(주 화면 좌상단 원점)를 Cocoa 좌표(좌하단 원점)로 바꾼다.
func cocoaRect(fromAX r: CGRect) -> NSRect {
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    return NSRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
}
