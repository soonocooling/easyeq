// Phase 0 기술 검증 스파이크. 제품 코드가 아니라 버릴 코드다.
// 드래그 → 선택 읽기 → 비활성 패널 → 키 탭 → ⌘V 치환을 앱별로 시험하고
// 결과를 ~/Library/Logs/EasyEqSpike.log 에 남긴다. 선택한 텍스트 자체는 기록하지 않는다.

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import FormulaCore

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

func postCommandKey(_ keyCode: CGKeyCode) {
    let source = CGEventSource(stateID: .combinedSessionState)
    for keyDown in [true, false] {
        let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown)
        event?.flags = .maskCommand
        event?.post(tap: .cghidEventTap)
    }
}

// MARK: 선택 읽기

struct Selection {
    var text: String
    var method: String
    var rect: CGRect?
}

func readViaAccessibility(pid: pid_t) -> (text: String?, rect: CGRect?) {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 0.25)
    // Electron/Chromium 앱의 접근성 트리를 켠다.
    AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)

    var focused: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
          let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return (nil, nil) }
    let element = focused as! AXUIElement

    var value: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value)
    let text = value as? String

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
    postCommandKey(CGKeyCode(kVK_ANSI_C))
    var copied: String?
    for _ in 0..<20 {
        usleep(10_000)
        if pasteboard.changeCount != before {
            copied = pasteboard.string(forType: .string)
            break
        }
    }
    if pasteboard.changeCount != before { restorePasteboard(snapshot) }
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

// MARK: 패널과 키 탭

let engine = FormulaEngine()
let fallbackCandidate = "√2 × √3"

var panel: NSPanel?
var choices: [String] = []
var targetPID: pid_t = 0
var eventTap: CFMachPort?
var mouseDownPoint = NSPoint.zero

func setTap(enabled: Bool) -> Bool {
    if eventTap == nil {
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { _, type, event, _ in
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let eventTap, panel != nil { CGEvent.tapEnable(tap: eventTap, enable: true) }
                    return Unmanaged.passUnretained(event)
                }
                let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
                let digits = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5]
                if let index = digits.firstIndex(of: keyCode) {
                    DispatchQueue.main.async { choose(index, via: "digit") }
                    return nil
                }
                switch keyCode {
                case kVK_Return:
                    DispatchQueue.main.async { choose(0, via: "enter") }
                    return nil
                case kVK_Escape, kVK_ANSI_0:
                    DispatchQueue.main.async { closePanel(reason: "esc/0 (원문 유지)") }
                    return nil
                default:
                    DispatchQueue.main.async { closePanel(reason: "다른 키 → 통과") }
                    return Unmanaged.passUnretained(event)
                }
            },
            userInfo: nil
        )
        if let eventTap {
            let source = CFMachPortCreateRunLoopSource(nil, eventTap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }
    guard let eventTap else { return false }
    CGEvent.tapEnable(tap: eventTap, enable: enabled)
    return true
}

func closePanel(reason: String) {
    guard panel != nil else { return }
    panel?.orderOut(nil)
    panel = nil
    _ = setTap(enabled: false)
    log("  팝업 닫힘: \(reason)")
}

func choose(_ index: Int, via: String) {
    guard panel != nil, index < choices.count else { return }
    let text = choices[index]
    closePanel(reason: "후보 \(index + 1) 선택 (\(via))")
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID else {
        log("  치환 취소: 포커스 앱이 바뀜")
        return
    }
    let pasteboard = NSPasteboard.general
    let snapshot = snapshotPasteboard()
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
    pasteboard.setData(Data(), forType: transientType)
    pasteboard.setData(Data(), forType: concealedType)
    let expected = pasteboard.changeCount
    postCommandKey(CGKeyCode(kVK_ANSI_V))
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
        if pasteboard.changeCount == expected {
            restorePasteboard(snapshot)
            log("  ⌘V 전송, 클립보드 복원 (항목 \(snapshot.count)개)")
        } else {
            log("  ⌘V 전송, 그 사이 클립보드가 바뀌어 복원 생략")
        }
    }
}

func showPanel(_ selection: Selection, mouse: NSPoint) {
    let rows = choices.enumerated().map { "\($0.offset + 1)  \($0.element)" } + ["0  원문 유지 (Esc)"]
    let stack = NSStackView(views: rows.map { row in
        let label = NSTextField(labelWithString: row)
        label.font = .systemFont(ofSize: 15)
        return label
    })
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 4
    stack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)

    let background = NSVisualEffectView()
    background.material = .menu
    background.state = .active
    background.wantsLayer = true
    background.layer?.cornerRadius = 8
    background.addSubview(stack)
    stack.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
        stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
        stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
        stack.topAnchor.constraint(equalTo: background.topAnchor),
        stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
    ])
    let size = stack.fittingSize

    // 접근성 좌표(주 화면 좌상단 원점)를 Cocoa 좌표(좌하단 원점)로 바꾼다.
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    var anchor = NSRect(x: mouse.x, y: mouse.y, width: 1, height: 16)
    if let r = selection.rect {
        anchor = NSRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }
    let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)) } ?? NSScreen.main
    let visible = screen?.visibleFrame ?? .zero
    var origin = NSPoint(x: anchor.minX, y: anchor.maxY + 6)
    if origin.y + size.height > visible.maxY { origin.y = anchor.minY - size.height - 6 }
    origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - size.width - 4)

    let newPanel = NSPanel(
        contentRect: NSRect(origin: origin, size: size),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    newPanel.level = .popUpMenu
    newPanel.isOpaque = false
    newPanel.backgroundColor = .clear
    newPanel.hasShadow = true
    newPanel.hidesOnDeactivate = false
    newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    newPanel.contentView = background
    newPanel.orderFrontRegardless()
    panel = newPanel
}

// MARK: 흐름

func handleSelection(mouse: NSPoint, trigger: String) {
    guard let front = NSWorkspace.shared.frontmostApplication,
          front.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
    let name = front.bundleIdentifier ?? front.localizedName ?? "?"
    if IsSecureEventInputEnabled() {
        log("[\(name)] 보안 입력 모드 → 건너뜀")
        return
    }
    let start = CFAbsoluteTimeGetCurrent()
    guard let selection = readSelection(pid: front.processIdentifier) else {
        log("[\(name)] \(trigger): 선택 읽기 실패 (AX·클립보드 모두)")
        return
    }
    guard selection.text.count <= FormulaEngine.maxInputLength else {
        log("[\(name)] \(trigger): 200자 초과 → 무시")
        return
    }
    let candidates = engine.candidates(for: selection.text).map { $0.text(for: .unicode) }
    // 스파이크에서는 어떤 선택이든 치환까지 시험할 수 있게 고정 후보를 대신 쓴다.
    choices = candidates.isEmpty ? [fallbackCandidate] : candidates
    targetPID = front.processIdentifier
    showPanel(selection, mouse: mouse)
    let tapOK = setTap(enabled: true)
    let elapsed = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
    log("[\(name)] \(trigger): 읽기=\(selection.method) 길이=\(selection.text.count) "
        + "좌표=\(selection.rect == nil ? "마우스 폴백" : "AX") 파서후보=\(candidates.count) "
        + "키탭=\(tapOK ? "OK" : "실패") \(elapsed)ms")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var trustTimer: Timer?
    private var monitors: [Any] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.addItem(withTitle: "로그 열기", action: #selector(openLog), keyEquivalent: "").target = self
        menu.addItem(withTitle: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu

        log("=== EasyEqSpike 시작 (macOS \(ProcessInfo.processInfo.operatingSystemVersionString)) ===")
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        updateTrust(AXIsProcessTrustedWithOptions(options))
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateTrust(AXIsProcessTrusted())
        }
    }

    private func updateTrust(_ trusted: Bool) {
        statusItem.button?.title = trusted ? "√?" : "√✕"
        guard trusted, monitors.isEmpty else { return }
        log("접근성 권한 확인됨 → 감지 시작 (앱 재시작 없음)")
        let down = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { _ in
            mouseDownPoint = NSEvent.mouseLocation
            closePanel(reason: "팝업 밖 클릭")
        }
        let up = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { event in
            let point = NSEvent.mouseLocation
            let moved = hypot(point.x - mouseDownPoint.x, point.y - mouseDownPoint.y)
            guard moved >= 4 || event.clickCount >= 2 else { return }
            let trigger = moved >= 4 ? "드래그" : "\(event.clickCount)번 클릭"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                handleSelection(mouse: point, trigger: trigger)
            }
        }
        monitors = [down, up].compactMap { $0 }
    }

    @objc private func openLog() {
        NSWorkspace.shared.open(logURL)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
