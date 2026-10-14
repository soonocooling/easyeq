// Phase 0 기술 검증 스파이크. 제품 코드가 아니라 버릴 코드다.
// 드래그 모드와 실시간 모드에서 선택 읽기 → 비활성 패널 → 키 탭 → ⌘V 치환을 앱별로 시험하고
// 결과를 ~/Library/Logs/EasyEqSpike.log 에 남긴다. 선택하거나 입력한 텍스트 자체는 기록하지 않는다.

import AppKit
import ApplicationServices
import FormulaCore

let engine = FormulaEngine()

enum Mode: String {
    /// 드래그하면 그 자리에 후보 팝업.
    case drag
    /// 입력하는 동안 떠 있는 창에 후보를 계속 보여 줌.
    case live
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let modeKey = "mode"
    private static let anyTextKey = "dragAnyText"

    private var statusItem: NSStatusItem!
    private var trustTimer: Timer?
    private var monitors: [Any] = []
    private var mouseDownPoint = NSPoint.zero
    private var trusted = false
    private var dragItem: NSMenuItem!
    private var liveItem: NSMenuItem!
    private var editableItem: NSMenuItem!

    private var mode = Mode(rawValue: UserDefaults.standard.string(forKey: AppDelegate.modeKey) ?? "") ?? .drag {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        dragItem = menu.addItem(withTitle: "드래그 모드", action: #selector(selectDrag), keyEquivalent: "")
        dragItem.target = self
        liveItem = menu.addItem(withTitle: "실시간 입력 모드", action: #selector(selectLive), keyEquivalent: "")
        liveItem.target = self
        menu.addItem(.separator())
        editableItem = menu.addItem(
            withTitle: "드래그: 입력 칸에서만 띄우기", action: #selector(toggleEditableOnly), keyEquivalent: ""
        )
        editableItem.target = self
        DragMode.onlyEditable = !UserDefaults.standard.bool(forKey: Self.anyTextKey)
        editableItem.state = DragMode.onlyEditable ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: "사용 설명서", action: #selector(openManual), keyEquivalent: "").target = self
        menu.addItem(withTitle: "로그 열기", action: #selector(openLog), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu

        log("=== EasyEqSpike 시작 (macOS \(ProcessInfo.processInfo.operatingSystemVersionString)) 모드=\(mode.rawValue) ===")
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        updateTrust(AXIsProcessTrustedWithOptions(options))
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateTrust(AXIsProcessTrusted())
        }
        applyMode()
    }

    private func updateTrust(_ isTrusted: Bool) {
        trusted = isTrusted
        updateTitle()
        guard isTrusted, monitors.isEmpty else { return }
        log("접근성 권한 확인됨 → 감지 시작 (앱 재시작 없음)")
        let down = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            self?.mouseDownPoint = NSEvent.mouseLocation
            DragMode.close(reason: "팝업 밖 클릭")
        }
        let up = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            guard let self else { return }
            if self.mode == .live {
                // 클릭으로 커서를 옮겼을 수 있으니 다시 읽는다.
                LiveMode.scheduleRefresh()
                return
            }
            let point = NSEvent.mouseLocation
            let moved = hypot(point.x - self.mouseDownPoint.x, point.y - self.mouseDownPoint.y)
            guard moved >= 4 || event.clickCount >= 2 else { return }
            let trigger = moved >= 4 ? "드래그" : "\(event.clickCount)번 클릭"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                DragMode.handleSelection(mouse: point, trigger: trigger)
            }
        }
        let keys = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
            if self?.mode == .live { LiveMode.scheduleRefresh() }
        }
        monitors = [down, up, keys].compactMap { $0 }
        applyMode()
    }

    private func applyMode() {
        dragItem.state = mode == .drag ? .on : .off
        liveItem.state = mode == .live ? .on : .off
        updateTitle()
        if mode == .live, trusted {
            DragMode.close(reason: "실시간 모드로 전환")
            LiveMode.start()
        } else {
            LiveMode.stop()
        }
    }

    private func updateTitle() {
        guard trusted else {
            statusItem.button?.title = "√✕"
            return
        }
        statusItem.button?.title = mode == .live ? "√⌨" : "√?"
    }

    @objc private func selectDrag() {
        mode = .drag
        applyMode()
    }

    @objc private func selectLive() {
        mode = .live
        applyMode()
    }

    @objc private func toggleEditableOnly() {
        DragMode.onlyEditable.toggle()
        UserDefaults.standard.set(!DragMode.onlyEditable, forKey: Self.anyTextKey)
        editableItem.state = DragMode.onlyEditable ? .on : .off
        log("설정: 드래그 입력 칸에서만=\(DragMode.onlyEditable)")
    }

    @objc private func openManual() {
        ManualWindow.show()
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
