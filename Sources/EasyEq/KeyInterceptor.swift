// 키 이벤트 탭 (F-06). 팝업이 열렸거나 실시간 후보가 있을 때만 켜고, 그 밖에는 꺼 둔다.

import AppKit

enum KeyInterceptor {
    private static var tap: CFMachPort?
    /// 지금 켜 두려는 상태. 탭을 직접 끄면 시스템이 "꺼짐" 이벤트를 보내므로,
    /// 그 이벤트에 반응해 다시 상태를 맞추면 끄기 → 이벤트 → 끄기가 무한히 반복된다.
    private static var wanted = false

    static func refresh() {
        setEnabled(PopupController.isOpen || LiveController.wantsKeys)
    }

    private static func setEnabled(_ enabled: Bool) {
        guard enabled != wanted || (enabled && tap == nil) else { return }
        wanted = enabled
        if tap == nil, enabled { create() }
        guard let tap else {
            if enabled { Log.write("키 탭 생성 실패") }
            return
        }
        CGEvent.tapEnable(tap: tap, enable: enabled)
    }

    private static func create() {
        tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { _, type, event, _ in
                // 시스템이 시간 초과로 끈 경우에만, 켜 두려던 상태라면 다시 켠다.
                if type == .tapDisabledByTimeout {
                    if KeyInterceptor.wanted, let tap = KeyInterceptor.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                    return Unmanaged.passUnretained(event)
                }
                if type == .tapDisabledByUserInput { return Unmanaged.passUnretained(event) }
                // 탭은 메인 런루프에 붙어 있으므로 여기서 상태를 바로 읽어도 된다.
                let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
                if PopupController.isOpen {
                    return PopupController.handleKey(keyCode, flags: event.flags) ? nil : Unmanaged.passUnretained(event)
                }
                if LiveController.handleKey(keyCode, flags: event.flags) { return nil }
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
