// 최초 실행 온보딩: 접근성 권한 안내와 허용 여부 실시간 표시.

import AppKit
import ApplicationServices
import SwiftUI

final class PermissionState: ObservableObject {
    static let shared = PermissionState()
    @Published private(set) var trusted = AXIsProcessTrusted()

    /// 앱 델리게이트의 타이머가 1초마다 부른다.
    func update() {
        let now = AXIsProcessTrusted()
        if now != trusted { trusted = now }
    }
}

struct OnboardingView: View {
    @ObservedObject var permission = PermissionState.shared
    @ObservedObject var settings = Settings.shared
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("EasyEq 시작하기")
                .font(.title2.bold())
            Text("한글·영어로 쓴 수식을 드래그하거나 입력하면, 그 자리에서 √2 × √3 같은 수식으로 바꿔 줍니다.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            GroupBox {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: permission.trusted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(permission.trusted ? .green : .orange)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("손쉬운 사용(접근성) 권한")
                            .font(.headline)
                        Text(permission.trusted
                             ? "허용되었습니다. 앱을 다시 시작할 필요 없이 바로 사용할 수 있습니다."
                             : "선택한 글을 읽고 그 자리에 수식을 넣으려면 이 권한이 필요합니다. "
                               + "아래 버튼으로 시스템 설정을 열고 EasyEq를 켜십시오.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !permission.trusted {
                            Button("시스템 설정 열기") { openAccessibilitySettings() }
                                .padding(.top, 2)
                        }
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("선택하거나 입력한 글은 이 Mac 밖으로 나가지 않으며 어디에도 저장되지 않습니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Button("사용 설명서") { ManualWindow.show() }
                Spacer()
                Button(permission.trusted ? "시작하기" : "나중에") {
                    settings.onboarded = permission.trusted
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private func openAccessibilitySettings() {
        // 권한 요청 목록에 앱을 올리고, 해당 설정 화면을 연다.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

enum OnboardingWindow {
    static func show() {
        WindowPresenter.show("onboarding", title: "EasyEq", size: NSSize(width: 480, height: 360)) {
            NSHostingController(rootView: OnboardingView { WindowPresenter.close("onboarding") })
        }
    }
}
