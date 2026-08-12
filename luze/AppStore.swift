import AppKit
import Combine
import Foundation
import Security

@MainActor final class AppStore: ObservableObject {
    @Published var selection: SidebarItem = .monthly
    @Published var step = 0
    @Published var month = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: .now)) ?? .now
    @Published var settings = SettingsData() { didSet { save() } }
    @Published var months: [String: MonthlyData] = [:] { didSet { save() } }
    @Published var notice = ""
    @Published var isWorking = false
    @Published var lastImportStatistics: StatementImportStatistics?
    @Published var lastClassificationSummary: ClassificationSummary?
    @Published var decisionRecords: [DecisionRecord] = [] { didSet { save() } }

    private let defaults = UserDefaults.standard
    private var loading = true
    var monthKey: String { Self.monthFormatter.string(from: month) }
    var current: MonthlyData { months[monthKey] ?? MonthlyData() }
    static let monthFormatter: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyyMM"; return f }()
    static let displayMonth: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "ja_JP"); f.dateFormat = "yyyy年M月"; return f }()

    init() {
        if let data = defaults.data(forKey: "settings"), let value = try? JSONDecoder().decode(SettingsData.self, from: data) { settings = value }
        if let data = defaults.data(forKey: "months"), let value = try? JSONDecoder().decode([String: MonthlyData].self, from: data) { months = value }
        if let data = defaults.data(forKey: "decisionRecords"), let value = try? JSONDecoder().decode([DecisionRecord].self, from: data) { decisionRecords = value }
        loading = false
    }

    func updateCurrent(_ edit: (inout MonthlyData) -> Void) {
        var value = current; edit(&value); months[monthKey] = value
    }

    func complete(_ value: Int) { updateCurrent { $0.completedSteps.insert(value) }; step = min(4, value + 1) }
    func incomeTotal(_ data: MonthlyData? = nil) -> Int {
        let monthlyData = data ?? current
        return settings.monthlyFields.filter { $0.kind == .income }.reduce(0) { $0 + monthlyData.value(for: $1.id) }
    }
    func attendanceDays(_ data: MonthlyData? = nil) -> Int {
        let monthlyData = data ?? current
        return settings.monthlyFields.filter { $0.kind == .attendanceDays }.reduce(0) { $0 + monthlyData.value(for: $1.id) }
    }
    func expenseTotal(_ data: MonthlyData? = nil) -> Int {
        let d = data ?? current
        return settings.rent + attendanceDays(d) * settings.oneWayFare * 2 + d.transactions.filter { $0.decision == .expense }.reduce(0) { $0 + $1.amount }
    }

    func applyRules(to transaction: inout Transaction) {
        let normalized = transaction.merchant.folding(options: [.caseInsensitive, .widthInsensitive], locale: .current)
        guard let rule = settings.rules.first(where: { normalized.localizedCaseInsensitiveContains($0.keyword.folding(options: [.caseInsensitive, .widthInsensitive], locale: .current)) }) else { return }
        if rule.action == .expense { transaction.decision = .expense; transaction.purpose = rule.purpose }
        if rule.action == .excluded { transaction.decision = .excluded }
    }

    func importCSV(url: URL) throws {
        let importer = StatementImporterRegistry.importer(for: settings.statementSource)
        let result = try importer.importTransactions(from: url, targetMonth: month)
        let classifier = TransactionClassifier()
        let classified = result.transactions.map { imported -> Transaction in
            let classification = classifier.classify(
                transaction: imported,
                rules: settings.rules,
                history: decisionRecords,
                permanentExclusions: settings.permanentMerchantExclusions
            )
            return Transaction(
                id: imported.id,
                date: imported.transactionDate,
                merchant: imported.originalMerchantName,
                amount: imported.amount,
                decision: classification.decision,
                purpose: classification.purpose,
                classificationSource: classification.source
            )
        }
        var appended: [Transaction] = []
        updateCurrent { current in
            let keys = Set(current.transactions.map { "\($0.date.timeIntervalSince1970)|\($0.merchant)|\($0.amount)" })
            appended = classified.filter { !keys.contains("\($0.date.timeIntervalSince1970)|\($0.merchant)|\($0.amount)") }
            current.transactions.append(contentsOf: appended)
        }
        for transaction in appended {
            DecisionHistory.upsert(transaction: transaction, period: monthKey, records: &decisionRecords)
        }
        lastImportStatistics = result.statistics
        lastClassificationSummary = .init(
            total: classified.count,
            automaticExpenses: classified.filter { $0.classificationSource == .automaticExpense }.count,
            automaticExclusions: classified.filter { $0.classificationSource == .automaticExclusion || $0.classificationSource == .permanentExclusion }.count,
            reviews: classified.filter { $0.decision == .pending }.count
        )
        notice = "\(result.statistics.selectedTransactionCount)件の取引を読み込みました。"
    }

    func setDecision(transactionID: UUID, decision: Decision, purpose: String? = nil) {
        var updated: Transaction?
        updateCurrent { current in
            guard let index = current.transactions.firstIndex(where: { $0.id == transactionID }) else { return }
            current.transactions[index].decision = decision
            current.transactions[index].classificationSource = .decisionHistory
            if let purpose { current.transactions[index].purpose = purpose }
            if decision != .expense { current.transactions[index].purpose = "" }
            updated = current.transactions[index]
        }
        if let updated {
            DecisionHistory.upsert(transaction: updated, period: monthKey, records: &decisionRecords)
        }
    }

    func setPurpose(transactionID: UUID, purpose: String) {
        guard let transaction = current.transactions.first(where: { $0.id == transactionID }) else { return }
        setDecision(transactionID: transactionID, decision: transaction.decision, purpose: purpose)
    }

    func rememberPermanentExclusion(transactionID: UUID) throws {
        guard let transaction = current.transactions.first(where: { $0.id == transactionID }) else { return }
        try PermanentExclusionMemory.remember(merchant: transaction.merchant, in: &settings.permanentMerchantExclusions)
    }

    func forgetPermanentExclusion(id: UUID) {
        PermanentExclusionMemory.forget(id: id, in: &settings.permanentMerchantExclusions)
    }

    func spreadsheetPayload() -> SpreadsheetExportPayload {
        let data = current
        let transport = attendanceDays(data) * settings.oneWayFare * 2
        var calculatedExpenses: [SpreadsheetCalculatedExpense] = []
        if settings.rent > 0 {
            calculatedExpenses.append(.init(
                stableKey: "fixed-expense:rent",
                company: "固定費",
                content: "家賃",
                amount: settings.rent,
                source: .fixedExpense
            ))
        }
        if transport > 0 {
            calculatedExpenses.append(.init(
                stableKey: "calculated-expense:commute",
                company: "交通費",
                content: "通勤交通費",
                amount: transport,
                source: .commute
            ))
        }
        return SpreadsheetExportPayloadBuilder().build(
            month: month,
            monthlyFields: settings.monthlyFields,
            monthlyData: data,
            calculatedExpenses: calculatedExpenses
        )
    }

    func testConnection() async {
        guard isHTTPSURL(settings.sheetURL), isHTTPSURL(settings.scriptURL) else {
            notice = "Spreadsheet URLとApps Script URLを確認してください。"
            return
        }
        guard !Keychain.token.isEmpty else {
            notice = "API Tokenを入力してください。"
            return
        }
        isWorking = true; defer { isWorking = false }
        let destination = MockSpreadsheetDestination()
        do {
            _ = try await destination.testConnection()
            let payload = spreadsheetPayload()
            try await destination.validate(payload)
            _ = try await destination.submit(payload)
            notice = "接続設定とMock通信契約を確認しました。本番Sheetには送信していません。"
        } catch {
            notice = "接続契約を確認できませんでした。設定または送信内容を確認してください。"
        }
    }

    private func isHTTPSURL(_ value: String) -> Bool {
        guard let url = URL(string: value), url.scheme == "https", url.host != nil else { return false }
        return true
    }

    private func save() { guard !loading else { return }; if let d = try? JSONEncoder().encode(settings) { defaults.set(d, forKey: "settings") }; if let d = try? JSONEncoder().encode(months) { defaults.set(d, forKey: "months") }; if let d = try? JSONEncoder().encode(decisionRecords) { defaults.set(d, forKey: "decisionRecords") } }
}

enum Keychain {
    private static let service = "com.fumiakiMogi777.luze", account = "apps-script-token"
    static var token: String {
        get { let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true]; var value: CFTypeRef?; guard SecItemCopyMatching(q as CFDictionary, &value) == errSecSuccess, let data = value as? Data else { return "" }; return String(data: data, encoding: .utf8) ?? "" }
        set { let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]; SecItemDelete(q as CFDictionary); guard let data = newValue.data(using: .utf8), !newValue.isEmpty else { return }; var item = q; item[kSecValueData as String] = data; SecItemAdd(item as CFDictionary, nil) }
    }
}
