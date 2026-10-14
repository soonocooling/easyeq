// 실시간 모드: 입력하는 동안 커서 앞의 글을 계속 살펴, 수식처럼 보이면
// 그 글자 바로 아래에 후보 창을 띄운다. 클릭이나 ⌥1~⌥5로 고르면 그 부분을 바꾼다.

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import FormulaCore

enum LiveMode {
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
    }

    private enum Status: Equatable {
        case idle
        case unreadable
        case secure
        case found([String])
    }

    private(set) static var isActive = false
    private static var panel: NSPanel?
    private static var target: Target?
    private static var status = Status.idle
    private static var pending: DispatchWorkItem?
    private static var lastLogged = ""
    /// Esc로 닫은 수식. 글이 바뀔 때까지 다시 띄우지 않는다.
    private static var dismissedText: String?

    static var wantsKeys: Bool {
        if case .found = status { return isActive }
        return false
    }

    static func start() {
        guard !isActive else { return }
        isActive = true
        status = .idle
        log("실시간 모드 시작")
        scheduleRefresh()
    }

    static func stop() {
        guard isActive else { return }
        isActive = false
        pending?.cancel()
        hidePanel()
        target = nil
        status = .idle
        KeyTap.refresh()
        log("실시간 모드 끝")
    }

    /// 키 입력·클릭 뒤 잠깐 기다렸다가 다시 읽는다 (입력 중 매번 읽지 않도록).
    static func scheduleRefresh() {
        guard isActive else { return }
        pending?.cancel()
        let work = DispatchWorkItem { refresh() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    /// 키 탭에서 부른다. ⌥1~⌥5만 삼키고, Esc는 앱에 그대로 넘기면서 창만 닫는다.
    static func handleKey(_ keyCode: Int, flags: CGEventFlags) -> Bool {
        guard case .found(let choices) = status, isActive else { return false }
        if keyCode == kVK_Escape {
            DispatchQueue.main.async { dismiss() }
            return false
        }
        guard flags.contains(.maskAlternate),
              !flags.contains(.maskCommand), !flags.contains(.maskControl) else { return false }
        let digits = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5]
        guard let index = digits.firstIndex(of: keyCode), index < choices.count else { return false }
        DispatchQueue.main.async { choose(index, via: "⌥\(index + 1)") }
        return true
    }

    // MARK: 읽기

    private static func refresh() {
        guard isActive else { return }
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        let name = front.bundleIdentifier ?? front.localizedName ?? "?"
        if IsSecureEventInputEnabled() {
            update(.secure, target: nil, app: name)
            return
        }
        guard let element = focusedElement(pid: front.processIdentifier),
              let value = stringAttribute(element, kAXValueAttribute),
              let selection = selectedRange(element) else {
            update(.unreadable, target: nil, app: name)
            return
        }
        // 선택 영역이 있으면 입력 중이 아니다.
        guard selection.length == 0 else {
            update(.idle, target: nil, app: name)
            return
        }
        let full = value as NSString
        let caret = selection.location
        guard caret >= 0, caret <= full.length else {
            update(.idle, target: nil, app: name)
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
        for start in starts {
            var end = line.length
            while end > start, isSpace(line.character(at: end - 1)) { end -= 1 }
            guard end > start else { continue }
            let piece = line.substring(with: NSRange(location: start, length: end - start))
            let candidates = engine.candidates(for: piece).map { $0.text(for: .unicode) }
            guard !candidates.isEmpty else { continue }
            let found = Target(
                pid: front.processIdentifier,
                element: element,
                range: CFRange(location: windowStart + start, length: end - start),
                text: piece,
                caret: caret
            )
            update(.found(candidates), target: found, app: name)
            return
        }
        update(.idle, target: nil, app: name)
    }

    private static func isSpace(_ unit: unichar) -> Bool {
        unit == 0x20 || unit == 0x09 || unit == 0xA0 || unit == 0x3000
    }

    private static func update(_ newStatus: Status, target newTarget: Target?, app: String) {
        if let dismissedText, newTarget?.text != dismissedText { self.dismissedText = nil }
        target = newTarget
        status = newStatus
        if case .found(let choices) = newStatus, let newTarget, newTarget.text != dismissedText {
            showPanel(choices, for: newTarget)
        } else {
            hidePanel()
        }
        KeyTap.refresh()

        // 텍스트는 남기지 않고 상태만 기록한다. 같은 상태가 이어지면 한 번만.
        let line: String
        switch newStatus {
        case .idle: line = "대기"
        case .secure: line = "보안 입력 → 쉼"
        case .unreadable: line = "입력 중인 글을 읽을 수 없음 (AX 값 없음)"
        case .found(let c): line = "후보 \(c.count)개 (범위 길이 \(newTarget?.text.count ?? 0))"
        }
        let entry = "[\(app)] 실시간: \(line)"
        if entry != lastLogged {
            log(entry)
            lastLogged = entry
        }
    }

    private static func dismiss() {
        guard let target else { return }
        dismissedText = target.text
        status = .idle
        hidePanel()
        KeyTap.refresh()
        log("  실시간 후보 닫힘: esc")
    }

    // MARK: 바꾸기

    private static func choose(_ index: Int, via: String) {
        guard case .found(let choices) = status, index < choices.count, let target else { return }
        let replacement = choices[index]
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid else {
            log("  실시간 치환 취소: 포커스 앱이 바뀜")
            return
        }
        // 접근성으로 범위를 직접 선택하고, 안 되면 화살표 키로 선택한다.
        let selected = setSelectedRange(target.element, target.range)
            && stringAttribute(target.element, kAXSelectedTextAttribute) == target.text
        if selected {
            log("  실시간 후보 \(index + 1) 선택 (\(via)), 범위선택=AX")
            pasteReplacingSelection(with: replacement)
        } else {
            let trailing = target.caret - (target.range.location + target.range.length)
            for _ in 0..<max(trailing, 0) { postKey(kVK_LeftArrow) }
            for _ in 0..<target.text.count { postKey(kVK_LeftArrow, flags: .maskShift) }
            log("  실시간 후보 \(index + 1) 선택 (\(via)), 범위선택=화살표")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                pasteReplacingSelection(with: replacement)
            }
        }
        self.target = nil
        status = .idle
        hidePanel()
        KeyTap.refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { scheduleRefresh() }
    }

    // MARK: 창

    private static func showPanel(_ choices: [String], for target: Target) {
        var views: [NSView] = [padded(makeLabel("“\(target.text)”", size: 11))]
        views += choices.enumerated().map { index, choice in
            CandidateRow(key: "⌥\(index + 1)", title: choice) { choose(index, via: "클릭") }
        }
        let (content, size) = makePanelContent(views)
        let origin = panelOrigin(size: size, near: anchorRect(for: target), above: false)

        let current = panel ?? makeNonActivatingPanel(frame: .zero)
        current.contentView = content
        current.setFrame(NSRect(origin: origin, size: size), display: true)
        current.orderFrontRegardless()
        panel = current
    }

    private static func hidePanel() {
        panel?.orderOut(nil)
    }

    /// 창을 붙일 위치 (Cocoa 좌표). 바꿀 글자의 화면 위치 → 한 줄짜리 입력 칸 → 마우스 순.
    private static func anchorRect(for target: Target) -> NSRect {
        if let r = boundsForRange(target.element, target.range) ?? boundsForRange(
            target.element, CFRange(location: max(target.caret - 1, 0), length: 1)
        ) {
            return cocoaRect(fromAX: r)
        }
        if let frame = elementFrame(target.element), frame.height <= singleLineHeight {
            return cocoaRect(fromAX: frame)
        }
        let mouse = NSEvent.mouseLocation
        return NSRect(x: mouse.x, y: mouse.y - 8, width: 1, height: 16)
    }

    private static func padded(_ view: NSView) -> NSView {
        let stack = NSStackView(views: [view])
        stack.edgeInsets = NSEdgeInsets(top: 1, left: 8, bottom: 1, right: 8)
        return stack
    }
}
