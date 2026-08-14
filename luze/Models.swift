import Foundation

enum SidebarItem: String, CaseIterable, Identifiable {
    case monthly = "今月の処理", receipts = "証憑", history = "判断履歴", mail = "メール", settings = "設定", help = "ヘルプ"
    var id: String { rawValue }
    var icon: String {
        switch self { case .monthly: "checklist"; case .receipts: "folder"; case .history: "clock.arrow.circlepath"; case .mail: "envelope"; case .settings: "gearshape"; case .help: "questionmark.circle" }
    }
}

enum Decision: String, Codable, CaseIterable { case expense = "経費", pending = "保留", excluded = "除外" }

enum ClassificationSource: String, Codable {
    case automaticExpense
    case automaticExclusion
    case decisionHistory
    case permanentExclusion
    case review
}

struct Transaction: Identifiable, Codable, Hashable {
    var id = UUID()
    var date: Date
    var merchant: String
    var amount: Int
    var decision: Decision = .pending
    var purpose = ""
    var exported = false
    var classificationSource: ClassificationSource = .review

    private enum CodingKeys: String, CodingKey {
        case id, date, merchant, amount, decision, purpose, exported, classificationSource
    }

    init(
        id: UUID = UUID(),
        date: Date,
        merchant: String,
        amount: Int,
        decision: Decision = .pending,
        purpose: String = "",
        exported: Bool = false,
        classificationSource: ClassificationSource = .review
    ) {
        self.id = id
        self.date = date
        self.merchant = merchant
        self.amount = amount
        self.decision = decision
        self.purpose = purpose
        self.exported = exported
        self.classificationSource = classificationSource
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try container.decode(Date.self, forKey: .date)
        merchant = try container.decode(String.self, forKey: .merchant)
        amount = try container.decode(Int.self, forKey: .amount)
        decision = try container.decodeIfPresent(Decision.self, forKey: .decision) ?? .pending
        purpose = try container.decodeIfPresent(String.self, forKey: .purpose) ?? ""
        exported = try container.decodeIfPresent(Bool.self, forKey: .exported) ?? false
        classificationSource = try container.decodeIfPresent(ClassificationSource.self, forKey: .classificationSource) ?? .review
    }
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
    var fileType: EvidenceFileType = .pdf
    var isRequired = true

    private enum CodingKeys: String, CodingKey {
        case id, name, filenameContains, fileType, isRequired
    }

    init(
        id: UUID = UUID(),
        name: String,
        filenameContains: String,
        fileType: EvidenceFileType = .pdf,
        isRequired: Bool = true
    ) {
        self.id = id
        self.name = name
        self.filenameContains = filenameContains
        self.fileType = fileType
        self.isRequired = isRequired
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        filenameContains = try container.decode(String.self, forKey: .filenameContains)
        fileType = try container.decodeIfPresent(EvidenceFileType.self, forKey: .fileType) ?? .pdf
        isRequired = try container.decodeIfPresent(Bool.self, forKey: .isRequired) ?? true
    }
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
    var isProtected = false

    private enum CodingKeys: String, CodingKey { case id, keyword, action, purpose, isProtected }

    init(id: UUID = UUID(), keyword: String, action: Action, purpose: String = "", isProtected: Bool = false) {
        self.id = id
        self.keyword = keyword
        self.action = action
        self.purpose = purpose
        self.isProtected = isProtected
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        keyword = try container.decode(String.self, forKey: .keyword)
        action = try container.decode(MerchantRule.Action.self, forKey: .action)
        purpose = try container.decodeIfPresent(String.self, forKey: .purpose) ?? ""
        isProtected = try container.decodeIfPresent(Bool.self, forKey: .isProtected)
            ?? MerchantProtection.isProtected(keyword)
    }
}

struct PermanentMerchantExclusion: Identifiable, Codable, Hashable {
    var id = UUID()
    var normalizedMerchantName: String
    var originalMerchantName: String
    var createdAt = Date()
}

struct DecisionRecord: Identifiable, Codable, Hashable {
    var id = UUID()
    var transactionFingerprint: String
    var period: String
    var date: Date
    var merchant: String
    var amount: Int
    var decision: Decision
    var purpose: String
    var createdAt = Date()
    var updatedAt = Date()
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
    var recipient = "", email = "", sheetURL = "", scriptURL = "", evidenceShareURL = ""
    var rootFolder = "", rent = 86860, oneWayFare = 345
    var monthlyFields = MonthlyFieldDefinition.defaults
    var statementSource = StatementSource.vpass
    var receiptRules: [ReceiptRule] = []
    var subjectTemplate = "{year}年{month}月分 経理資料の共有"
    var bodyTemplate = Self.defaultBodyTemplate

    static let defaultBodyTemplate = """
    {recipient} 様

    お世話になっております。
    {year}年{month}月分の経理資料を共有いたします。

    ■ 証憑フォルダ
    {evidence_share_url}

    ■ Google Spreadsheet
    {sheet_url}

    収入合計：{income_total}円
    支出合計：{expense_total}円

    よろしくお願いいたします。
    """
    var rules: [MerchantRule] = Self.defaultMerchantRules
    var permanentMerchantExclusions: [PermanentMerchantExclusion] = []
    var spreadsheetEnvironment = SpreadsheetEnvironment.test

    static let defaultMerchantRules: [MerchantRule] = [
        .init(keyword: "OPENAI.*CHATGPT", action: .expense, purpose: "ChatGPT"),
        .init(keyword: "ANTHROPIC|CLAUDE", action: .expense, purpose: "Claude"),
        .init(keyword: "GOOGLE.*GOOGLE.?ONE|GOOGLE.?ONE", action: .expense, purpose: "Google One"),
        .init(keyword: "ADOBE|アドビ", action: .expense, purpose: "編集ツール"),
        .init(keyword: "CANVA", action: .expense, purpose: "デザインツール"),
        .init(keyword: "ソフトバンク.*M|SOFTBANK.*M", action: .expense, purpose: "携帯料金"),
        .init(keyword: "AMAZON", action: .review, purpose: "要確認", isProtected: true),
        .init(keyword: "APPLE.?COM.?BILL", action: .review, purpose: "要確認", isProtected: true),
        .init(keyword: "PASMO", action: .excluded, purpose: "チャージ"),
        .init(keyword: "SBI証券.*投信|SBI.*投信", action: .excluded, purpose: "投資")
    ]

    private enum CodingKeys: String, CodingKey {
        case hasCompletedOnboarding, recipient, email, sheetURL, scriptURL
        case evidenceShareURL, dropboxURL
        case rootFolder, rent, oneWayFare, monthlyFields, statementSource, receiptRules
        case subjectTemplate, bodyTemplate, rules, permanentMerchantExclusions, spreadsheetEnvironment
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
        evidenceShareURL = try container.decodeIfPresent(String.self, forKey: .evidenceShareURL)
            ?? container.decodeIfPresent(String.self, forKey: .dropboxURL)
            ?? defaults.evidenceShareURL
        rootFolder = try container.decodeIfPresent(String.self, forKey: .rootFolder) ?? defaults.rootFolder
        rent = try container.decodeIfPresent(Int.self, forKey: .rent) ?? defaults.rent
        oneWayFare = try container.decodeIfPresent(Int.self, forKey: .oneWayFare) ?? defaults.oneWayFare
        monthlyFields = try container.decodeIfPresent([MonthlyFieldDefinition].self, forKey: .monthlyFields) ?? defaults.monthlyFields
        statementSource = try container.decodeIfPresent(StatementSource.self, forKey: .statementSource) ?? defaults.statementSource
        receiptRules = try container.decodeIfPresent([ReceiptRule].self, forKey: .receiptRules) ?? defaults.receiptRules
        subjectTemplate = try container.decodeIfPresent(String.self, forKey: .subjectTemplate) ?? defaults.subjectTemplate
        let decodedBodyTemplate = try container.decodeIfPresent(String.self, forKey: .bodyTemplate) ?? defaults.bodyTemplate
        bodyTemplate = Self.migrateLegacyDefaultBodyTemplate(decodedBodyTemplate)
        let decodedRules = try container.decodeIfPresent([MerchantRule].self, forKey: .rules)
        rules = Self.isLegacyDefaultRules(decodedRules) ? defaults.rules : (decodedRules ?? defaults.rules)
        permanentMerchantExclusions = try container.decodeIfPresent([PermanentMerchantExclusion].self, forKey: .permanentMerchantExclusions) ?? []
        spreadsheetEnvironment = try container.decodeIfPresent(SpreadsheetEnvironment.self, forKey: .spreadsheetEnvironment) ?? .test
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(hasCompletedOnboarding, forKey: .hasCompletedOnboarding)
        try container.encode(recipient, forKey: .recipient)
        try container.encode(email, forKey: .email)
        try container.encode(sheetURL, forKey: .sheetURL)
        try container.encode(scriptURL, forKey: .scriptURL)
        try container.encode(evidenceShareURL, forKey: .evidenceShareURL)
        try container.encode(rootFolder, forKey: .rootFolder)
        try container.encode(rent, forKey: .rent)
        try container.encode(oneWayFare, forKey: .oneWayFare)
        try container.encode(monthlyFields, forKey: .monthlyFields)
        try container.encode(statementSource, forKey: .statementSource)
        try container.encode(receiptRules, forKey: .receiptRules)
        try container.encode(subjectTemplate, forKey: .subjectTemplate)
        try container.encode(bodyTemplate, forKey: .bodyTemplate)
        try container.encode(rules, forKey: .rules)
        try container.encode(permanentMerchantExclusions, forKey: .permanentMerchantExclusions)
        try container.encode(spreadsheetEnvironment, forKey: .spreadsheetEnvironment)
    }

    private static let legacyDefaultBodyTemplates = [
        """
        {recipient} 様

        お世話になっております。
        {year}年{month}月分の資料を共有いたします。

        ■ Dropbox
        {dropbox_url}

        ■ Google Spreadsheet
        {sheet_url}

        収入：{income_total}円
        支出：{expense_total}円
        """,
        """
        {recipient} 様

        お世話になっております。
        {year}年{month}月分の資料を共有いたします。

        ■ 証憑フォルダ
        {evidence_folder_url}

        ■ Google Spreadsheet
        {sheet_url}

        収入：{income_total}円
        支出：{expense_total}円
        """
    ]

    private static func migrateLegacyDefaultBodyTemplate(_ template: String) -> String {
        let normalized = template.replacingOccurrences(of: "\r\n", with: "\n")
        return legacyDefaultBodyTemplates.contains(normalized) ? defaultBodyTemplate : template
    }

    private static func isLegacyDefaultRules(_ rules: [MerchantRule]?) -> Bool {
        guard let rules else { return false }
        let legacy = ["Adobe", "SoftBank", "Google One", "Anthropic", "OpenAI", "ChatGPT", "Canva", "PASMO", "SBI", "Amazon", "Apple"]
        return rules.map(\.keyword) == legacy
    }
}

enum SpreadsheetEnvironment: String, Codable, CaseIterable {
    case test
    case production

    var displayName: String {
        switch self {
        case .test: "テスト専用"
        case .production: "本番（未対応）"
        }
    }
}
