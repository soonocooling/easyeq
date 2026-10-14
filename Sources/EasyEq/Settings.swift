// 사용자 설정 (F-10). UserDefaults에 저장하고, 바뀌면 즉시 반영한다.

import AppKit
import Carbon.HIToolbox
import Combine
import FormulaCore
import ServiceManagement

/// 전역 단축키 (Carbon 가상 키 코드 + Carbon 수식키).
struct Hotkey: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    /// 메뉴·설정에 보일 키 이름 (`M`).
    var key: String

    static let defaultToggle = Hotkey(keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(controlKey | optionKey), key: "M")
    static let defaultConvert = Hotkey(keyCode: UInt32(kVK_ANSI_E), modifiers: UInt32(controlKey | optionKey), key: "E")

    var display: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + key
    }

    /// 설정 창에서 누른 키로 만든다. ⌃·⌥·⌘ 중 하나는 있어야 한다.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var mods: UInt32 = 0
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        guard mods & UInt32(controlKey | optionKey | cmdKey) != 0,
              let chars = event.charactersIgnoringModifiers, !chars.isEmpty else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: mods, key: chars.uppercased())
    }

    init(keyCode: UInt32, modifiers: UInt32, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }
}

final class Settings: ObservableObject {
    static let shared = Settings()

    /// 비밀번호 관리자 등 기본 제외 앱.
    static let defaultExcludedApps = [
        "com.apple.keychainaccess",
        "com.apple.Passwords",
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "com.nprotect.nosmain",
    ]

    private let defaults = UserDefaults.standard

    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: "enabled") } }
    @Published var dragEnabled: Bool { didSet { defaults.set(dragEnabled, forKey: "dragEnabled") } }
    @Published var liveEnabled: Bool { didSet { defaults.set(liveEnabled, forKey: "liveEnabled") } }
    /// 드래그는 입력 칸에서만 (웹 본문·받은 메시지 제외).
    @Published var editableOnly: Bool { didSet { defaults.set(editableOnly, forKey: "editableOnly") } }
    @Published var format: OutputFormat { didSet { defaults.set(format.rawValue, forKey: "format") } }
    @Published var normalizeSpacing: Bool { didSet { defaults.set(normalizeSpacing, forKey: "normalizeSpacing") } }
    @Published var numberKeys: Bool { didSet { defaults.set(numberKeys, forKey: "numberKeys") } }
    @Published var maxCandidates: Int { didSet { defaults.set(maxCandidates, forKey: "maxCandidates") } }
    @Published var excludedApps: [String] { didSet { defaults.set(excludedApps, forKey: "excludedApps") } }
    @Published var toggleHotkey: Hotkey { didSet { save(toggleHotkey, "toggleHotkey") } }
    @Published var convertHotkey: Hotkey { didSet { save(convertHotkey, "convertHotkey") } }
    @Published var onboarded: Bool { didSet { defaults.set(onboarded, forKey: "onboarded") } }

    /// 로그인 시 시작은 시스템(SMAppService)이 진짜 상태를 가진다.
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                Log.write("로그인 시 시작 변경 실패: \(error.localizedDescription)")
            }
            objectWillChange.send()
        }
    }

    var engineOptions: EngineOptions {
        EngineOptions(normalizeSpacing: normalizeSpacing, maxCandidates: maxCandidates)
    }

    private init() {
        defaults.register(defaults: [
            "enabled": true,
            "dragEnabled": true,
            "liveEnabled": true,
            "editableOnly": true,
            "format": OutputFormat.unicode.rawValue,
            "normalizeSpacing": true,
            "numberKeys": true,
            "maxCandidates": 5,
            "excludedApps": Self.defaultExcludedApps,
            "onboarded": false,
        ])
        enabled = defaults.bool(forKey: "enabled")
        dragEnabled = defaults.bool(forKey: "dragEnabled")
        liveEnabled = defaults.bool(forKey: "liveEnabled")
        editableOnly = defaults.bool(forKey: "editableOnly")
        format = OutputFormat(rawValue: defaults.string(forKey: "format") ?? "") ?? .unicode
        normalizeSpacing = defaults.bool(forKey: "normalizeSpacing")
        numberKeys = defaults.bool(forKey: "numberKeys")
        maxCandidates = min(max(defaults.integer(forKey: "maxCandidates"), 1), 5)
        excludedApps = defaults.stringArray(forKey: "excludedApps") ?? Self.defaultExcludedApps
        toggleHotkey = Self.load("toggleHotkey", from: defaults) ?? .defaultToggle
        convertHotkey = Self.load("convertHotkey", from: defaults) ?? .defaultConvert
        onboarded = defaults.bool(forKey: "onboarded")
    }

    func isExcluded(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return excludedApps.contains(bundleID)
    }

    private func save(_ hotkey: Hotkey, _ key: String) {
        defaults.set(try? JSONEncoder().encode(hotkey), forKey: key)
    }

    private static func load(_ key: String, from defaults: UserDefaults) -> Hotkey? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Hotkey.self, from: data)
    }
}
