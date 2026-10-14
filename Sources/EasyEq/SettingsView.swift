// 설정 창 (F-10). 바꾸면 즉시 반영된다.

import AppKit
import FormulaCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = Settings.shared

    var body: some View {
        Form {
            Section("동작") {
                Toggle("EasyEq 켜기", isOn: $settings.enabled)
                Toggle("드래그하면 후보 보기", isOn: $settings.dragEnabled)
                Toggle("입력 칸에서 드래그할 때만", isOn: $settings.editableOnly)
                    .disabled(!settings.dragEnabled)
                    .padding(.leading, 18)
                Toggle("입력하는 동안 후보 보기 (실시간)", isOn: $settings.liveEnabled)
                Toggle("로그인 시 자동으로 시작", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.launchAtLogin = $0 }
                ))
            }

            Section("후보") {
                Picker("출력 형식", selection: $settings.format) {
                    Text("유니코드 (√2 × √3)").tag(OutputFormat.unicode)
                    Text("LaTeX (\\sqrt{2} \\times \\sqrt{3})").tag(OutputFormat.latex)
                }
                Stepper("최대 후보 수: \(settings.maxCandidates)개", value: $settings.maxCandidates, in: 1...5)
                Toggle("연산자 양옆 공백 정리 (x+1 → x + 1)", isOn: $settings.normalizeSpacing)
                Toggle("숫자 키 1~5로 고르기 (드래그 팝업)", isOn: $settings.numberKeys)
            }

            Section("단축키") {
                HotkeyRow(title: "켜기/끄기", hotkey: $settings.toggleHotkey, defaultValue: .defaultToggle)
                HotkeyRow(title: "선택한 글 바로 변환", hotkey: $settings.convertHotkey, defaultValue: .defaultConvert)
            }

            Section {
                ExcludedAppsView(apps: $settings.excludedApps)
            } header: {
                Text("제외 앱")
            } footer: {
                Text("이 앱들에서는 아무것도 읽지 않습니다. 비밀번호 관리자는 기본으로 들어 있습니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 640)
    }
}

/// 단축키 표시와 녹화. 녹화 중에는 기존 단축키를 잠시 해제한다.
struct HotkeyRow: View {
    let title: String
    @Binding var hotkey: Hotkey
    let defaultValue: Hotkey
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Button(recording ? "새 단축키를 누르십시오…" : hotkey.display) {
                recording ? stop() : start()
            }
            .frame(minWidth: 130)
            if hotkey != defaultValue {
                Button("기본값") { hotkey = defaultValue }
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        HotkeyManager.unregisterAll()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Esc: 취소
                stop()
                return nil
            }
            if let new = Hotkey(event: event) {
                hotkey = new
                stop()
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording {
            recording = false
            NotificationCenter.default.post(name: .hotkeysChanged, object: nil)
        }
    }
}

extension Notification.Name {
    static let hotkeysChanged = Notification.Name("EasyEqHotkeysChanged")
}

struct ExcludedAppsView: View {
    @Binding var apps: [String]

    var body: some View {
        ForEach(apps, id: \.self) { bundleID in
            HStack {
                if let icon = icon(for: bundleID) {
                    Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                }
                Text(name(for: bundleID))
                Text(bundleID).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    apps.removeAll { $0 == bundleID }
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
            }
        }
        HStack {
            Menu("실행 중인 앱에서 추가") {
                ForEach(runningApps(), id: \.self) { bundleID in
                    Button(name(for: bundleID)) { add(bundleID) }
                }
            }
            Button("응용 프로그램에서 고르기…") { pickApp() }
        }
    }

    private func runningApps() -> [String] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap(\.bundleIdentifier)
            .filter { !apps.contains($0) && $0 != Bundle.main.bundleIdentifier }
            .sorted { name(for: $0) < name(for: $1) }
    }

    private func add(_ bundleID: String) {
        if !apps.contains(bundleID) { apps.append(bundleID) }
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier { add(id) }
        }
    }

    private func appURL(_ bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    private func name(for bundleID: String) -> String {
        guard let url = appURL(bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private func icon(for bundleID: String) -> NSImage? {
        appURL(bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
}

enum SettingsWindow {
    static func show() {
        WindowPresenter.show("settings", title: "EasyEq 설정", size: NSSize(width: 500, height: 640)) {
            NSHostingController(rootView: SettingsView())
        }
    }
}
