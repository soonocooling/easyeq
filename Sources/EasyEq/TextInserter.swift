// 클립보드 보존과 치환 입력 (F-03 폴백, F-07).

import AppKit
import Carbon.HIToolbox

enum Keyboard {
    static func post(_ keyCode: Int, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: keyDown)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }
}

enum Clipboard {
    typealias Snapshot = [[NSPasteboard.PasteboardType: Data]]

    /// 클립보드 관리자가 기록하지 않도록 붙이는 표식.
    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    /// 텍스트·이미지·파일 등 모든 타입을 그대로 보관한다.
    static func snapshot() -> Snapshot {
        (NSPasteboard.general.pasteboardItems ?? []).map { item in
            var contents: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { contents[type] = data }
            }
            return contents
        }
    }

    static func restore(_ snapshot: Snapshot) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let items = snapshot.map { contents -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in contents { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }

    /// ⌘C로 현재 선택을 읽고 클립보드를 되돌린다. 복사가 일어나지 않으면 nil.
    static func copySelection() -> String? {
        let pasteboard = NSPasteboard.general
        let saved = snapshot()
        let before = pasteboard.changeCount
        Keyboard.post(kVK_ANSI_C, flags: .maskCommand)
        var copied: String?
        for _ in 0..<20 {
            usleep(10_000)
            if pasteboard.changeCount != before {
                copied = pasteboard.string(forType: .string)
                break
            }
        }
        if pasteboard.changeCount != before { restore(saved) }
        // VS Code·Cursor 같은 편집기는 선택이 없을 때 ⌘C로 현재 줄 전체(끝에 줄바꿈)를 복사한다.
        if let text = copied, text.hasSuffix("\n") { return nil }
        return copied
    }
}

enum TextInserter {
    /// 현재 선택을 `text`로 바꾼다: 클립보드에 넣고 ⌘V → 200ms 뒤 이전 클립보드 복원.
    /// 그 사이 사용자가 직접 복사했다면 복원하지 않는다.
    static func replaceSelection(with text: String) {
        let pasteboard = NSPasteboard.general
        let saved = Clipboard.snapshot()
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        pasteboard.setData(Data(), forType: Clipboard.transientType)
        pasteboard.setData(Data(), forType: Clipboard.concealedType)
        let expected = pasteboard.changeCount
        Keyboard.post(kVK_ANSI_V, flags: .maskCommand)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if pasteboard.changeCount == expected {
                Clipboard.restore(saved)
            } else {
                Log.write("  클립보드가 그 사이 바뀌어 복원 생략")
            }
        }
    }

    /// 붙여 넣을 수 없는 곳(읽기 전용)에서는 후보를 클립보드에 복사만 한다.
    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
