// 키 이벤트 탭 (F-06). 팝업이 열렸거나 실시간 후보가 있을 때만 켜고, 그 밖에는 꺼 둔다.

import AppKit

enum KeyInterceptor {
    private static var tap: CFMachPort?

    static func refresh() {
        setEnabled(PopupController.isOpen || LiveController.wantsKeys)
    }

    private static func setEnabled(_ enabled: Bool) {
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
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    DispatchQueue.main.async { KeyInterceptor.refresh() }
                    return Unmanaged.passUnretained(event)
                }
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
