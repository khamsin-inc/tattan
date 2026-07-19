import Foundation

/// テンプレート変数の AST ノード（D-3 / §9.2）。
enum TemplateNode: Equatable, Sendable {
    case text(String)
    case date(offsetDays: Int, format: String?)
    case day
    case time(format: String?)
    case datetime(format: String?)
    case ask(label: String, defaultValue: String?)
    case choose(options: [String])
    case clipboard
    case cursor
    case uuid

    /// ペースト前にユーザー入力 UI（§9.3）が必要なノードか
    var isInteractive: Bool {
        switch self {
        case .ask, .choose:
            return true
        default:
            return false
        }
    }
}
