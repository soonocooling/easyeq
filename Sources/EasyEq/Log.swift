// 이벤트 로그. 선택·입력한 텍스트는 절대 기록하지 않는다 (F-11). 앱 이름, 방식, 길이, 개수만.

import Foundation

enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/EasyEq.log")

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    /// 로그 파일이 이보다 커지면 처음부터 다시 쓴다.
    private static let maxBytes: UInt64 = 2_000_000

    static func write(_ message: String) {
        let line = "\(formatter.string(from: Date())) \(message)\n"
        #if DEBUG
        print(line, terminator: "")
        #endif
        guard let data = line.data(using: .utf8) else { return }
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attributes[.size] as? UInt64, size > maxBytes {
            try? FileManager.default.removeItem(at: url)
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}
