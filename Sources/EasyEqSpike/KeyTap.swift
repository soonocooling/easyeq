// 키 이벤트 탭. 드래그 팝업이 열렸거나 실시간 모드에 후보가 있을 때만 켠다.

import AppKit
import Carbon.HIToolbox

enum KeyTap {
    private static var tap: CFMachPort?

    /// 지금 상태에 맞게 켜거나 끈다.
    static func refresh() {
        _ = setEnabled(DragMode.isOpen || LiveMode.wantsKeys)
    }

    static func setEnabled(_ enabled: Bool) -> Bool {
        if tap == nil, enabled { create() }
        guard let tap else { return false }
        CGEvent.tapEnable(tap: tap, enable: enabled)
        return true
    }

    private static func create() {
        tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { _, type, event, _ in
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    DispatchQueue.main.async { KeyTap.refresh() }
                    return Unmanaged.passUnretained(event)
                }
                let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
                if DragMode.isOpen {
                    return DragMode.handleKey(keyCode) ? nil : Unmanaged.passUnretained(event)
                }
                if LiveMode.handleKey(keyCode, flags: event.flags) { return nil }
                return Unmanaged.passUnretained(event)
            },
            userInfo: nil
        )
        if let tap {
            let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }
}
