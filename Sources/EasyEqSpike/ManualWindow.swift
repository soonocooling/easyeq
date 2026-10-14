// 메뉴의 "사용 설명서" 창. 시스템 언어가 한국어면 manual.html, 아니면 manual.en.html.

import AppKit
import WebKit

enum ManualWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let webView = WKWebView()
            if let url = manualURL() {
                webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            } else {
                webView.loadHTMLString("<p>설명서 파일(manual.html)을 찾지 못했습니다.</p>", baseURL: nil)
            }
            let newWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 720),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            newWindow.title = "EasyEq 사용 설명서"
            newWindow.contentView = webView
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            window = newWindow
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// .app으로 실행하면 번들 안, `swift run`으로 실행하면 저장소의 docs/ 폴더.
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
