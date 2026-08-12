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

enum MonthlyFieldKind: String, Codable, CaseIterable {
    case income
    case attendanceDays

    var unit: String { self == .income ? "円" : "日" }
}

struct MonthlyFieldDefinition: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var kind: MonthlyFieldKind
    var exportKey: String
}

extension MonthlyFieldDefinition {
    static let techBizID = UUID(uuidString: "3B3B5D22-078F-4FC2-966D-000000000001")!
    static let helloLinksID = UUID(uuidString: "3B3B5D22-078F-4FC2-966D-000000000002")!
    static let kindleID = UUID(uuidString: "3B3B5D22-078F-4FC2-966D-000000000003")!
    static let officeDaysID = UUID(uuidString: "3B3B5D22-078F-4FC2-966D-000000000004")!

    static let defaults: [Self] = [
        .init(id: techBizID, name: "TechBiz", kind: .income, exportKey: "techBiz"),
        .init(id: helloLinksID, name: "HelloLinks", kind: .income, exportKey: "helloLinks"),
        .init(id: kindleID, name: "Kindle", kind: .income, exportKey: "kindle"),
        .init(id: officeDaysID, name: "出社日数", kind: .attendanceDays, exportKey: "officeDays")
    ]
}

struct ReceiptRule: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var filenameContains: String
    var isRequired = true
}

struct StatementSource: Codable, Hashable {
    var importerID: String
    var displayName: String
    static let vpass = Self(importerID: "vpass", displayName: "三井住友カード / Vpass")
}

struct MerchantRule: Identifiable, Codable, Hashable {
    enum Action: String, Codable, CaseIterable { case expense = "自動経費", excluded = "自動除外", review = "毎回確認" }
    var id = UUID()
    var keyword: String
    var action: Action
    var purpose: String = ""
}

struct MonthlyData: Codable {
    var fieldValues: [UUID: Int] = [:]
    var completedSteps: Set<Int> = []
    var transactions: [Transaction] = []
    var sheetExported = false

    func value(for fieldID: UUID) -> Int { fieldValues[fieldID, default: 0] }
    mutating func setValue(_ value: Int, for fieldID: UUID) { fieldValues[fieldID] = value }

    private enum CodingKeys: String, CodingKey {
        case fieldValues, completedSteps, transactions, sheetExported
        case techBiz, helloLinks, kindle, officeDays
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fieldValues = try container.decodeIfPresent([UUID: Int].self, forKey: .fieldValues) ?? [:]
        if fieldValues.isEmpty {
            fieldValues[MonthlyFieldDefinition.techBizID] = try container.decodeIfPresent(Int.self, forKey: .techBiz) ?? 0
            fieldValues[MonthlyFieldDefinition.helloLinksID] = try container.decodeIfPresent(Int.self, forKey: .helloLinks) ?? 0
            fieldValues[MonthlyFieldDefinition.kindleID] = try container.decodeIfPresent(Int.self, forKey: .kindle) ?? 0
            fieldValues[MonthlyFieldDefinition.officeDaysID] = try container.decodeIfPresent(Int.self, forKey: .officeDays) ?? 0
        }
        completedSteps = try container.decodeIfPresent(Set<Int>.self, forKey: .completedSteps) ?? []
        transactions = try container.decodeIfPresent([Transaction].self, forKey: .transactions) ?? []
        sheetExported = try container.decodeIfPresent(Bool.self, forKey: .sheetExported) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fieldValues, forKey: .fieldValues)
        try container.encode(completedSteps, forKey: .completedSteps)
        try container.encode(transactions, forKey: .transactions)
        try container.encode(sheetExported, forKey: .sheetExported)
    }
}

struct SettingsData: Codable {
    var hasCompletedOnboarding: Bool? = nil
    var recipient = "", email = "", sheetURL = "", scriptURL = "", dropboxURL = ""
    var rootFolder = "", rent = 86860, oneWayFare = 345
    var monthlyFields = MonthlyFieldDefinition.defaults
    var statementSource = StatementSource.vpass
    var receiptRules: [ReceiptRule] = []
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
    var rules: [MerchantRule] = Self.defaultMerchantRules

    private static let defaultMerchantRules: [MerchantRule] = [
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

    private enum CodingKeys: String, CodingKey {
        case hasCompletedOnboarding, recipient, email, sheetURL, scriptURL, dropboxURL
        case rootFolder, rent, oneWayFare, monthlyFields, statementSource, receiptRules
        case subjectTemplate, bodyTemplate, rules
    }

    init() {}

    init(from decoder: Decoder) throws {
        let defaults = Self()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding)
        recipient = try container.decodeIfPresent(String.self, forKey: .recipient) ?? defaults.recipient
        email = try container.decodeIfPresent(String.self, forKey: .email) ?? defaults.email
        sheetURL = try container.decodeIfPresent(String.self, forKey: .sheetURL) ?? defaults.sheetURL
        scriptURL = try container.decodeIfPresent(String.self, forKey: .scriptURL) ?? defaults.scriptURL
        dropboxURL = try container.decodeIfPresent(String.self, forKey: .dropboxURL) ?? defaults.dropboxURL
        rootFolder = try container.decodeIfPresent(String.self, forKey: .rootFolder) ?? defaults.rootFolder
        rent = try container.decodeIfPresent(Int.self, forKey: .rent) ?? defaults.rent
        oneWayFare = try container.decodeIfPresent(Int.self, forKey: .oneWayFare) ?? defaults.oneWayFare
        monthlyFields = try container.decodeIfPresent([MonthlyFieldDefinition].self, forKey: .monthlyFields) ?? defaults.monthlyFields
        statementSource = try container.decodeIfPresent(StatementSource.self, forKey: .statementSource) ?? defaults.statementSource
        receiptRules = try container.decodeIfPresent([ReceiptRule].self, forKey: .receiptRules) ?? defaults.receiptRules
        subjectTemplate = try container.decodeIfPresent(String.self, forKey: .subjectTemplate) ?? defaults.subjectTemplate
        bodyTemplate = try container.decodeIfPresent(String.self, forKey: .bodyTemplate) ?? defaults.bodyTemplate
        rules = try container.decodeIfPresent([MerchantRule].self, forKey: .rules) ?? defaults.rules
    }
}
