import Foundation

enum SidebarItem: String, CaseIterable, Identifiable {
    case monthly = "今月の処理", receipts = "証憑", history = "判断履歴", mail = "メール", settings = "設定", help = "ヘルプ"
    var id: String { rawValue }
    var icon: String {
        switch self { case .monthly: "checklist"; case .receipts: "folder"; case .history: "clock.arrow.circlepath"; case .mail: "envelope"; case .settings: "gearshape"; case .help: "questionmark.circle" }
    }
}

enum Decision: String, Codable, CaseIterable { case expense = "経費", pending = "保留", excluded = "除外" }

struct Transaction: Identifiable, Codable, Hashable {
    var id = UUID()
    var date: Date
    var merchant: String
    var amount: Int
    var decision: Decision = .pending
    var purpose = ""
    var exported = false
}

struct MerchantRule: Identifiable, Codable, Hashable {
    enum Action: String, Codable, CaseIterable { case expense = "自動経費", excluded = "自動除外", review = "毎回確認" }
    var id = UUID()
    var keyword: String
    var action: Action
    var purpose: String = ""
}

struct MonthlyData: Codable {
    var techBiz = 0, helloLinks = 0, kindle = 0, officeDays = 0
    var completedSteps: Set<Int> = []
    var transactions: [Transaction] = []
    var sheetExported = false
    var incomeTotal: Int { techBiz + helloLinks + kindle }
}

struct SettingsData: Codable {
    var hasCompletedOnboarding: Bool? = nil
    var recipient = "", email = "", sheetURL = "", scriptURL = "", dropboxURL = ""
    var rootFolder = "", rent = 86860, oneWayFare = 345
    var subjectTemplate = "{year}年{month}月分 経理資料の共有"
    var bodyTemplate = """
    {recipient} 様

    お世話になっております。
    {year}年{month}月分の資料を共有いたします。

    ■ Dropbox
    {dropbox_url}

    ■ Google Spreadsheet
    {sheet_url}

    収入：{income_total}円
    支出：{expense_total}円
    """
    var rules: [MerchantRule] = [
        .init(keyword: "Adobe", action: .expense, purpose: "デザインツール"),
        .init(keyword: "SoftBank", action: .expense, purpose: "携帯料金"),
        .init(keyword: "Google One", action: .expense, purpose: "クラウドストレージ"),
        .init(keyword: "Anthropic", action: .expense, purpose: "AIツール"),
        .init(keyword: "OpenAI", action: .expense, purpose: "AIツール"),
        .init(keyword: "ChatGPT", action: .expense, purpose: "AIツール"),
        .init(keyword: "Canva", action: .expense, purpose: "デザインツール"),
        .init(keyword: "PASMO", action: .excluded),
        .init(keyword: "SBI", action: .excluded),
        .init(keyword: "Amazon", action: .review),
        .init(keyword: "Apple", action: .review)
    ]
}
