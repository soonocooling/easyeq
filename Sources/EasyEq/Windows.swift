// 일반 창(설정·권한 안내·설명서) 띄우기. 메뉴바 앱이라 창을 열 때 앱을 앞으로 가져온다.

import AppKit
import SwiftUI
import WebKit

enum WindowPresenter {
    private static var windows: [String: NSWindow] = [:]

    static func show(_ id: String, title: String, size: NSSize, make: () -> NSViewController) {
        let window = windows[id] ?? {
            let window = NSWindow(contentViewController: make())
            window.title = title
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(size)
            window.isReleasedWhenClosed = false
            window.center()
            windows[id] = window
            return window
        }()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    static func close(_ id: String) {
        windows[id]?.close()
    }
}

enum ManualWindow {
    static func show() {
        WindowPresenter.show("manual", title: "EasyEq 사용 설명서", size: NSSize(width: 680, height: 760)) {
            let controller = NSViewController()
            let webView = WKWebView()
            if let url = manualURL() {
                webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            } else {
                webView.loadHTMLString("<p>설명서 파일(manual.html)을 찾지 못했습니다.</p>", baseURL: nil)
            }
            controller.view = webView
            return controller
        }
    }

    /// 시스템 언어가 한국어면 한국어판. .app 번들 안, 없으면 저장소의 docs/ 폴더.
    private static func manualURL() -> URL? {
        let korean = Locale.preferredLanguages.first?.hasPrefix("ko") ?? true
        let name = korean ? "manual" : "manual.en"
        if let bundled = Bundle.main.url(forResource: name, withExtension: "html") { return bundled }
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let local = repo.appendingPathComponent("docs/\(name).html")
        return FileManager.default.fileExists(atPath: local.path) ? local : nil
    }
}
