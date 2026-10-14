// 전역 단축키 (RegisterEventHotKey, 추가 권한 불필요).

import AppKit
import Carbon.HIToolbox

enum HotkeyManager {
    enum Action: UInt32 {
        case toggle = 1
        case convert = 2
    }

    private static var handlers: [Action: () -> Void] = [:]
    private static var refs: [Action: EventHotKeyRef] = [:]
    private static var installed = false

    static func register(_ hotkey: Hotkey, for action: Action, handler: @escaping () -> Void) {
        installHandlerIfNeeded()
        unregister(action)
        handlers[action] = handler
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x4545_5131), id: action.rawValue) // 'EEQ1'
        let status = RegisterEventHotKey(hotkey.keyCode, hotkey.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            refs[action] = ref
        } else {
            Log.write("단축키 등록 실패 (\(hotkey.display), \(status)) — 다른 앱이 쓰고 있을 수 있음")
        }
    }

    static func unregister(_ action: Action) {
        if let ref = refs.removeValue(forKey: action) { UnregisterEventHotKey(ref) }
    }

    /// 설정 창에서 새 단축키를 녹화하는 동안 기존 단축키가 반응하지 않게 한다.
    static func unregisterAll() {
        for action in Array(refs.keys) { unregister(action) }
    }

    private static func installHandlerIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &id
            )
            if let action = HotkeyManager.Action(rawValue: id.id) {
                DispatchQueue.main.async { HotkeyManager.handlers[action]?() }
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
