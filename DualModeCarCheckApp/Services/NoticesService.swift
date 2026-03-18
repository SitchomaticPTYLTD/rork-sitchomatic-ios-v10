import SwiftUI
import Observation

enum NoticeSource {
    case ppsr
    case proxy
    case general
}

struct AppNotice: Identifiable {
    let id: UUID = UUID()
    let date: Date = Date()
    let message: String
    let source: NoticeSource
    let autoRetried: Bool
    var isRead: Bool = false
}

@Observable
class NoticesService {
    static let shared = NoticesService()

    var notices: [AppNotice] = []

    var unreadCount: Int {
        notices.filter { !$0.isRead }.count
    }

    func addNotice(message: String, source: NoticeSource, autoRetried: Bool = false) {
        let notice = AppNotice(message: message, source: source, autoRetried: autoRetried)
        notices.insert(notice, at: 0)
        if notices.count > 200 {
            notices = Array(notices.prefix(200))
        }
    }

    func markAllRead() {
        for i in notices.indices {
            notices[i].isRead = true
        }
    }

    func clearAll() {
        notices.removeAll()
    }
}
