// 실시간 입력 모드: 입력하는 동안 커서 앞의 글을 살펴, 수식처럼 보이면
// 그 글자 바로 아래에 후보 창을 띄운다. 클릭이나 ⌥1~⌥5로 고르면 그 부분만 바꾼다.

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import FormulaCore

enum LiveController {
    /// 커서 앞에서 살펴볼 최대 길이 (UTF-16).
    private static let lookback = 80
    /// 이보다 높은 입력 칸(본문 편집기 등)은 칸 아래가 아니라 마우스 근처에 띄운다.
    private static let singleLineHeight: CGFloat = 120

    private struct Target {
        let pid: pid_t
        let element: AXUIElement
        /// 바꿀 부분 (AX 텍스트 범위, UTF-16).
        let range: CFRange
        let text: String
        let caret: Int
        let candidates: [Candidate]
        let format: OutputFormat
    }

    private static var running = false
    private static var panel: NSPanel?
    private static var target: Target?
    private static var pending: DispatchWorkItem?
    private static var lastLogged = ""
    /// Esc로 닫은 수식. 글이 바뀔 때까지 다시 띄우지 않는다.
    private static var dismissedText: String?

    static var wantsKeys: Bool { running && target != nil && panel?.isVisible == true }

    static func start() {
        guard !running else { return }
        running = true
        Log.write("실시간 모드 켜짐")
        scheduleRefresh()
    }

    static func stop() {
        guard running else { return }
        running = false
        pending?.cancel()
        target = nil
        panel?.orderOut(nil)
        KeyInterceptor.refresh()
        Log.write("실시간 모드 꺼짐")
    }

    /// 키 입력·클릭 뒤 잠깐 기다렸다가 다시 읽는다 (입력 중 매번 읽지 않도록).
    static func scheduleRefresh() {
        guard running else { return }
        pending?.cancel()
        let work = DispatchWorkItem { refresh() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    /// 키 탭에서 부른다. ⌥1~⌥5만 삼키고, Esc는 앱에 그대로 넘기면서 창만 닫는다.
    static func handleKey(_ keyCode: Int, flags: CGEventFlags) -> Bool {
        guard wantsKeys, let target else { return false }
        if keyCode == kVK_Escape {
            DispatchQueue.main.async { dismiss() }
            return false
        }
        guard flags.contains(.maskAlternate),
              !flags.contains(.maskCommand), !flags.contains(.maskControl) else { return false }
        let digits = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5]
        guard let index = digits.firstIndex(of: keyCode), index < target.candidates.count else { return false }
        DispatchQueue.main.async { choose(index, via: "⌥\(index + 1)") }
        return true
    }

    // MARK: 읽기

    private static func refresh() {
        guard running else { return }
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        let name = front.bundleIdentifier ?? front.localizedName ?? "?"
        if Settings.shared.isExcluded(front.bundleIdentifier) {
            update(nil, app: name, state: "제외 앱")
            return
        }
        if IsSecureEventInputEnabled() {
            update(nil, app: name, state: "보안 입력 → 쉼")
            return
        }
        guard let element = AX.focusedElement(pid: front.processIdentifier),
              let value = AX.string(element, kAXValueAttribute),
              let selection = AX.selectedRange(element) else {
            update(nil, app: name, state: "입력 중인 글을 읽을 수 없음")
            return
        }
        // 선택 영역이 있으면 입력 중이 아니다.
        let full = value as NSString
        let caret = selection.location
        guard selection.length == 0, caret >= 0, caret <= full.length else {
            update(nil, app: name, state: "대기")
            return
        }

        // 커서가 있는 줄의 앞부분만 본다.
        var lineStart = 0
        let newline = full.rangeOfCharacter(
            from: .newlines, options: .backwards, range: NSRange(location: 0, length: caret)
        )
        if newline.location != NSNotFound { lineStart = newline.location + newline.length }
        let windowStart = max(lineStart, caret - lookback)
        let line = full.substring(with: NSRange(location: windowStart, length: caret - windowStart)) as NSString

        // 가장 긴 것부터: 줄 처음, 그리고 공백 뒤의 각 단어 시작에서 끝까지.
        var starts = [0]
        for i in 1..<max(line.length, 1) where isSpace(line.character(at: i - 1)) && !isSpace(line.character(at: i)) {
            starts.append(i)
        }
        let settings = Settings.shared
        for start in starts {
            var end = line.length
            while end > start, isSpace(line.character(at: end - 1)) { end -= 1 }
            guard end > start else { continue }
            let piece = line.substring(with: NSRange(location: start, length: end - start))
            let candidates = engine.candidates(for: piece, format: settings.format, options: settings.engineOptions)
            guard !candidates.isEmpty else { continue }
            let found = Target(
                pid: front.processIdentifier,
                element: element,
                range: CFRange(location: windowStart + start, length: end - start),
                text: piece,
                caret: caret,
                candidates: candidates,
                format: settings.format
            )
            update(found, app: name, state: "후보 \(candidates.count)개")
            return
        }
        update(nil, app: name, state: "대기")
    }

    private static func isSpace(_ unit: unichar) -> Bool {
        unit == 0x20 || unit == 0x09 || unit == 0xA0 || unit == 0x3000
    }

    private static func update(_ newTarget: Target?, app: String, state: String) {
        if let dismissedText, newTarget?.text != dismissedText { self.dismissedText = nil }
        target = newTarget
        if let newTarget, newTarget.text != dismissedText, !PopupController.isOpen {
            showPanel(for: newTarget)
        } else {
            panel?.orderOut(nil)
        }
        KeyInterceptor.refresh()

        // 텍스트는 남기지 않고 상태만 기록한다. 같은 상태가 이어지면 한 번만.
        let entry = "[\(app)] 실시간: \(state)"
        if entry != lastLogged {
            Log.write(entry)
            lastLogged = entry
        }
    }

    private static func dismiss() {
        guard let target else { return }
        dismissedText = target.text
        panel?.orderOut(nil)
        KeyInterceptor.refresh()
        Log.write("  실시간 후보 닫힘: esc")
    }

    // MARK: 바꾸기

    private static func choose(_ index: Int, via: String) {
        guard let target, index < target.candidates.count else { return }
        let replacement = target.candidates[index].text(for: target.format)
        self.target = nil
        panel?.orderOut(nil)
        KeyInterceptor.refresh()
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid else {
            Log.write("  실시간 치환 취소: 포커스 앱이 바뀜")
            return
        }
        // 접근성으로 범위를 직접 선택하고, 안 되면 화살표 키로 선택한다.
        let selected = AX.setSelectedRange(target.element, target.range)
            && AX.string(target.element, kAXSelectedTextAttribute) == target.text
        if selected {
            Log.write("  실시간 후보 \(index + 1) 선택 (\(via)), 범위 선택=AX")
            TextInserter.replaceSelection(with: replacement)
        } else {
            let trailing = target.caret - (target.range.location + target.range.length)
            for _ in 0..<max(trailing, 0) { Keyboard.post(kVK_LeftArrow) }
            for _ in 0..<target.text.count { Keyboard.post(kVK_LeftArrow, flags: .maskShift) }
            Log.write("  실시간 후보 \(index + 1) 선택 (\(via)), 범위 선택=화살표")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                TextInserter.replaceSelection(with: replacement)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { scheduleRefresh() }
    }

    // MARK: 창

    private static func showPanel(for target: Target) {
        var views: [NSView] = [PanelFactory.label("“\(target.text)”")]
        views += target.candidates.enumerated().map { index, candidate in
            PanelFactory.row(candidate, key: "⌥\(index + 1)", format: target.format) { choose(index, via: "클릭") }
        }
        let (content, size) = PanelFactory.content(views)
        let origin = PanelFactory.origin(size: size, near: anchorRect(for: target), above: false)
        let current = panel ?? PanelFactory.panel()
        current.contentView = content
        current.setFrame(NSRect(origin: origin, size: size), display: true)
        current.orderFrontRegardless()
        panel = current
    }

    /// 창을 붙일 위치 (Cocoa 좌표). 바꿀 글자의 화면 위치 → 한 줄짜리 입력 칸 → 마우스 순.
    private static func anchorRect(for target: Target) -> NSRect {
        if let r = AX.bounds(target.element, target.range) ?? AX.bounds(
            target.element, CFRange(location: max(target.caret - 1, 0), length: 1)
        ) {
            return cocoaRect(fromAX: r)
        }
        if let frame = AX.frame(target.element), frame.height <= singleLineHeight {
            return cocoaRect(fromAX: frame)
        }
        let mouse = NSEvent.mouseLocation
        return NSRect(x: mouse.x, y: mouse.y - 8, width: 1, height: 16)
    }
}
