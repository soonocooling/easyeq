// 메뉴바 아이콘과 전체 상태 (F-01). 설정·권한이 바뀌면 모니터·실시간 모드·단축키를 다시 맞춘다.

import AppKit
import Combine
import FormulaCore

let engine = FormulaEngine()

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings.shared
    private let permission = PermissionState.shared
    private var statusItem: NSStatusItem!
    private var cancellables: Set<AnyCancellable> = []
    private var permissionTimer: Timer?
    private var registeredHotkeys: (Hotkey, Hotkey)?

    private var stateItem: NSMenuItem!
    private var toggleItem: NSMenuItem!
    private var dragItem: NSMenuItem!
    private var liveItem: NSMenuItem!
    private var unicodeItem: NSMenuItem!
    private var latexItem: NSMenuItem!
    private var permissionItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.write("=== EasyEq \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev") 시작 "
            + "(macOS \(ProcessInfo.processInfo.operatingSystemVersionString)) ===")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        buildMenu()

        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.apply() }
            .store(in: &cancellables)
        NotificationCenter.default.addObserver(forName: .hotkeysChanged, object: nil, queue: .main) { [weak self] _ in
            self?.registeredHotkeys = nil
            self?.apply()
        }
        // 권한은 알림이 없어 폴링한다. 허용되면 앱 재시작 없이 바로 동작하고, 취소되면 안내를 보인다.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            let before = self?.permission.trusted
            self?.permission.update()
            if before != self?.permission.trusted {
                Log.write("접근성 권한: \(self?.permission.trusted == true ? "허용" : "없음")")
                self?.apply()
            }
        }
        apply()
        if !permission.trusted || !settings.onboarded { OnboardingWindow.show() }
    }

    // MARK: 상태 반영

    private func apply() {
        let trusted = permission.trusted
        let active = settings.enabled && trusted

        if active { SelectionMonitor.start() } else { SelectionMonitor.stop() }
        if active, settings.liveEnabled { LiveController.start() } else { LiveController.stop() }
        if !settings.dragEnabled { PopupController.close(reason: "드래그 꺼짐") }
        KeyInterceptor.refresh()
        registerHotkeys()
        updateMenu(trusted: trusted)
    }

    private func registerHotkeys() {
        let current = (settings.toggleHotkey, settings.convertHotkey)
        if let registeredHotkeys, registeredHotkeys == current { return }
        HotkeyManager.register(current.0, for: .toggle) { [weak self] in self?.toggle() }
        HotkeyManager.register(current.1, for: .convert) { SelectionMonitor.convertCurrentSelection() }
        registeredHotkeys = current
    }

    @objc private func toggle() {
        settings.enabled.toggle()
        Log.write("켜기/끄기 → \(settings.enabled ? "켜짐" : "꺼짐")")
    }

    // MARK: 메뉴

    private func buildMenu() {
        let menu = NSMenu()
        stateItem = menu.addItem(withTitle: "", action: nil, keyEquivalent: "")
        stateItem.isEnabled = false
        toggleItem = item(menu, "", #selector(toggle))
        menu.addItem(.separator())
        dragItem = item(menu, "드래그하면 후보 보기", #selector(toggleDrag))
        liveItem = item(menu, "입력하는 동안 후보 보기", #selector(toggleLive))
        let formatMenu = NSMenu()
        unicodeItem = item(formatMenu, "유니코드  √2 × √3", #selector(useUnicode))
        latexItem = item(formatMenu, "LaTeX  \\sqrt{2}", #selector(useLatex))
        let formatItem = menu.addItem(withTitle: "출력 형식", action: nil, keyEquivalent: "")
        formatItem.submenu = formatMenu
        menu.addItem(.separator())
        permissionItem = item(menu, "⚠︎ 접근성 권한 허용하기…", #selector(openOnboarding))
        item(menu, "설정…", #selector(openSettings)).keyEquivalent = ","
        item(menu, "사용 설명서", #selector(openManual))
        item(menu, "로그 보기", #selector(openLog))
        menu.addItem(.separator())
        menu.addItem(withTitle: "EasyEq 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @discardableResult
    private func item(_ menu: NSMenu, _ title: String, _ action: Selector) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func updateMenu(trusted: Bool) {
        let symbol: String
        let state: String
        if !trusted {
            symbol = "exclamationmark.triangle"
            state = "EasyEq — 권한 필요"
        } else if settings.enabled {
            symbol = "x.squareroot"
            state = "EasyEq — 켜짐"
        } else {
            symbol = "pause.circle"
            state = "EasyEq — 꺼짐"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: state)
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = state
        stateItem.title = state
        toggleItem.title = (settings.enabled ? "끄기" : "켜기") + "    \(settings.toggleHotkey.display)"
        dragItem.state = settings.dragEnabled ? .on : .off
        liveItem.state = settings.liveEnabled ? .on : .off
        unicodeItem.state = settings.format == .unicode ? .on : .off
        latexItem.state = settings.format == .latex ? .on : .off
        permissionItem.isHidden = trusted
    }

    @objc private func toggleDrag() { settings.dragEnabled.toggle() }
    @objc private func toggleLive() { settings.liveEnabled.toggle() }
    @objc private func useUnicode() { settings.format = .unicode }
    @objc private func useLatex() { settings.format = .latex }
    @objc private func openOnboarding() { OnboardingWindow.show() }
    @objc private func openSettings() { SettingsWindow.show() }
    @objc private func openManual() { ManualWindow.show() }
    @objc private func openLog() { NSWorkspace.shared.open(Log.url) }
}
