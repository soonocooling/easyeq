// EasyEq — 한글·영어로 쓴 수식을 유니코드/LaTeX로 바꿔 주는 메뉴바 앱.

import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
