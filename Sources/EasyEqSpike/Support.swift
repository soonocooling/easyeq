// 로그, 클립보드, 키 입력 합성, 접근성 읽기처럼 두 모드가 함께 쓰는 기능.

import AppKit
import ApplicationServices
import Carbon.HIToolbox

// MARK: 로그

let logURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Logs/EasyEqSpike.log")

func log(_ message: String) {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    let line = "\(formatter.string(from: Date())) \(message)\n"
    print(line, terminator: "")
    guard let data = line.data(using: .utf8) else { return }
    if let handle = try? FileHandle(forWritingTo: logURL) {
        handle.seekToEndOfFile()
        handle.write(data)
        try? handle.close()
    } else {
        try? data.write(to: logURL)
    }
}

// MARK: 클립보드

typealias PasteboardSnapshot = [[NSPasteboard.PasteboardType: Data]]

let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

func snapshotPasteboard() -> PasteboardSnapshot {
    (NSPasteboard.general.pasteboardItems ?? []).map { item in
        var contents: [NSPasteboard.PasteboardType: Data] = [:]
        for type in item.types {
            if let data = item.data(forType: type) { contents[type] = data }
        }
        return contents
    }
}

func restorePasteboard(_ snapshot: PasteboardSnapshot) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    let items = snapshot.map { contents -> NSPasteboardItem in
        let item = NSPasteboardItem()
        for (type, data) in contents { item.setData(data, forType: type) }
        return item
    }
    if !items.isEmpty { pasteboard.writeObjects(items) }
}

func postKey(_ keyCode: Int, flags: CGEventFlags = []) {
    let source = CGEventSource(stateID: .combinedSessionState)
    for keyDown in [true, false] {
        let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: keyDown)
        event?.flags = flags
        event?.post(tap: .cghidEventTap)
    }
}

/// 현재 선택 영역을 `text`로 바꾼다: 클립보드에 넣고 ⌘V → 200ms 뒤 이전 클립보드 복원.
func pasteReplacingSelection(with text: String) {
    let pasteboard = NSPasteboard.general
    let snapshot = snapshotPasteboard()
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
    pasteboard.setData(Data(), forType: transientType)
    pasteboard.setData(Data(), forType: concealedType)
    let expected = pasteboard.changeCount
    postKey(kVK_ANSI_V, flags: .maskCommand)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
        if pasteboard.changeCount == expected {
            restorePasteboard(snapshot)
            log("  ⌘V 전송, 클립보드 복원 (항목 \(snapshot.count)개)")
        } else {
            log("  ⌘V 전송, 그 사이 클립보드가 바뀌어 복원 생략")
        }
    }
}

// MARK: 접근성

/// 앞에 있는 앱의 포커스된 요소. Electron/Chromium 앱은 접근성 트리를 먼저 켠다.
func focusedElement(pid: pid_t) -> AXUIElement? {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 0.25)
    AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    var focused: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
          let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
    return (focused as! AXUIElement)
}

func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value as? String
}

func selectedRange(_ element: AXUIElement) -> CFRange? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
          let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    var range = CFRange()
    return AXValueGetValue(value as! AXValue, .cfRange, &range) ? range : nil
}

func setSelectedRange(_ element: AXUIElement, _ range: CFRange) -> Bool {
    var range = range
    guard let value = AXValueCreate(.cfRange, &range) else { return false }
    return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success
}

/// 텍스트 범위의 화면 위치 (접근성 좌표: 주 화면 좌상단 원점).
func boundsForRange(_ element: AXUIElement, _ range: CFRange) -> CGRect? {
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
func elementFrame(_ element: AXUIElement) -> CGRect? {
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

/// 글을 고칠 수 있는 입력 칸인지. 웹 페이지 본문 같은 읽기 전용 글이면 false,
/// 판단할 수 없으면(포커스 요소를 못 얻음) nil.
func editability(pid: pid_t) -> (editable: Bool?, role: String) {
    guard let element = focusedElement(pid: pid) else { return (nil, "없음") }
    let role = stringAttribute(element, kAXRoleAttribute) ?? "?"
    let textRoles: Set<String> = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole]
    if textRoles.contains(role) { return (true, role) }
    var settable: DarwinBoolean = false
    if AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success,
       settable.boolValue {
        return (true, role)
    }
    // 웹 본문·정적 글·목록 등 읽기 전용으로 확실한 역할만 false. 그 밖(Word 문서 등)은 판단 보류.
    let readOnlyRoles: Set<String> = [
        "AXWebArea", kAXStaticTextRole, kAXGroupRole, kAXScrollAreaRole, "AXLink", "AXHeading",
        kAXListRole, kAXTableRole, kAXCellRole, kAXRowRole, kAXOutlineRole, kAXImageRole, kAXButtonRole,
        kAXWindowRole, kAXApplicationRole,
    ]
    return (readOnlyRoles.contains(role) ? false : nil, role)
}

// MARK: 선택 읽기 (드래그 모드)

struct Selection {
    var text: String
    var method: String
    var rect: CGRect?
}

func readViaAccessibility(pid: pid_t) -> (text: String?, rect: CGRect?) {
    guard let element = focusedElement(pid: pid) else { return (nil, nil) }
    let text = stringAttribute(element, kAXSelectedTextAttribute)

    var rect: CGRect?
    var range: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success,
       let range {
        var bounds: CFTypeRef?
        if AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, range, &bounds
        ) == .success, let bounds, CFGetTypeID(bounds) == AXValueGetTypeID() {
            var r = CGRect.zero
            if AXValueGetValue(bounds as! AXValue, .cgRect, &r), r.width > 0, r.height > 0 { rect = r }
        }
    }
    return (text, rect)
}

func readViaClipboard() -> String? {
    let pasteboard = NSPasteboard.general
    let snapshot = snapshotPasteboard()
    let before = pasteboard.changeCount
    postKey(kVK_ANSI_C, flags: .maskCommand)
    var copied: String?
    for _ in 0..<20 {
        usleep(10_000)
        if pasteboard.changeCount != before {
            copied = pasteboard.string(forType: .string)
            break
        }
    }
    if pasteboard.changeCount != before { restorePasteboard(snapshot) }
    // VS Code·Cursor 같은 편집기는 선택이 없을 때 ⌘C로 현재 줄 전체(끝에 줄바꿈)를 복사한다.
    // 빈 곳을 드래그했을 때 그 줄이 후보로 뜨지 않도록 버린다.
    if let text = copied, text.hasSuffix("\n") { return nil }
    return copied
}

func readSelection(pid: pid_t) -> Selection? {
    let ax = readViaAccessibility(pid: pid)
    if let text = ax.text, !text.isEmpty {
        return Selection(text: text, method: "AX", rect: ax.rect)
    }
    if let text = readViaClipboard(), !text.isEmpty {
        return Selection(text: text, method: "clipboard", rect: ax.rect)
    }
    return nil
}
