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

    private let defaults = UserDefaults.standard
    private var loading = true
    var monthKey: String { Self.monthFormatter.string(from: month) }
    var current: MonthlyData { months[monthKey] ?? MonthlyData() }
    static let monthFormatter: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyyMM"; return f }()
    static let displayMonth: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "ja_JP"); f.dateFormat = "yyyy年M月"; return f }()

    init() {
        if let data = defaults.data(forKey: "settings"), let value = try? JSONDecoder().decode(SettingsData.self, from: data) { settings = value }
        if let data = defaults.data(forKey: "months"), let value = try? JSONDecoder().decode([String: MonthlyData].self, from: data) { months = value }
        loading = false
    }

    func updateCurrent(_ edit: (inout MonthlyData) -> Void) {
        var value = current; edit(&value); months[monthKey] = value
    }

    func complete(_ value: Int) { updateCurrent { $0.completedSteps.insert(value) }; step = min(4, value + 1) }
    func expenseTotal(_ data: MonthlyData? = nil) -> Int {
        let d = data ?? current
        return settings.rent + d.officeDays * settings.oneWayFare * 2 + d.transactions.filter { $0.decision == .expense }.reduce(0) { $0 + $1.amount }
    }

    func applyRules(to transaction: inout Transaction) {
        let normalized = transaction.merchant.folding(options: [.caseInsensitive, .widthInsensitive], locale: .current)
        guard let rule = settings.rules.first(where: { normalized.localizedCaseInsensitiveContains($0.keyword.folding(options: [.caseInsensitive, .widthInsensitive], locale: .current)) }) else { return }
        if rule.action == .expense { transaction.decision = .expense; transaction.purpose = rule.purpose }
        if rule.action == .excluded { transaction.decision = .excluded }
    }

    func importCSV(url: URL) throws {
        let data = try Data(contentsOf: url)
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .shiftJIS) ?? ""
        var items: [Transaction] = []
        for line in text.components(separatedBy: .newlines) where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            let columns = CSVParser.columns(line)
            guard let dateIndex = columns.firstIndex(where: { CSVParser.date($0) != nil }),
                  let date = CSVParser.date(columns[dateIndex]) else { continue }
            let amountIndex = columns.indices.reversed().first { Int(columns[$0].replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "¥", with: "")) != nil }
            guard let amountIndex, amountIndex != dateIndex, let amount = Int(columns[amountIndex].replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "¥", with: "")) else { continue }
            let merchant = columns.indices.filter { $0 != dateIndex && $0 != amountIndex }.map { columns[$0] }.first { !$0.isEmpty } ?? "不明な加盟店"
            var item = Transaction(date: date, merchant: merchant, amount: abs(amount)); applyRules(to: &item); items.append(item)
        }
        guard !items.isEmpty else { throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "取引を読み取れませんでした。CSV形式を確認してください。"] ) }
        updateCurrent { current in
            let keys = Set(current.transactions.map { "\($0.date.timeIntervalSince1970)|\($0.merchant)|\($0.amount)" })
            current.transactions.append(contentsOf: items.filter { !keys.contains("\($0.date.timeIntervalSince1970)|\($0.merchant)|\($0.amount)") })
        }
        notice = "\(items.count)件の取引を読み込みました。"
    }

    func testConnection() async {
        guard let url = URL(string: settings.scriptURL), !settings.scriptURL.isEmpty else { notice = "Apps Script URLを入力してください。"; return }
        isWorking = true; defer { isWorking = false }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["action": "ping", "token": Keychain.token])
        do { let (_, response) = try await URLSession.shared.data(for: request); guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { throw URLError(.badServerResponse) }; notice = "接続しました。" }
        catch { notice = "接続できませんでした。URLまたはAPI Tokenを確認してください。" }
    }

    func exportToSheet() async {
        guard let url = URL(string: settings.scriptURL), !settings.scriptURL.isEmpty else { notice = "設定でApps Script URLを登録してください。"; return }
        let d = current
        let transactions = d.transactions.filter { $0.decision == .expense }.map { ["id": $0.id.uuidString, "date": ISO8601DateFormatter().string(from: $0.date), "merchant": $0.merchant, "amount": $0.amount, "purpose": $0.purpose] as [String: Any] }
        let body: [String: Any] = ["action": "upsertMonth", "token": Keychain.token, "month": monthKey, "income": ["techBiz": d.techBiz, "helloLinks": d.helloLinks, "kindle": d.kindle], "fixedExpenses": ["rent": settings.rent, "transport": d.officeDays * settings.oneWayFare * 2], "transactions": transactions]
        isWorking = true; defer { isWorking = false }
        do { var request = URLRequest(url: url); request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONSerialization.data(withJSONObject: body); let (_, response) = try await URLSession.shared.data(for: request); guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { throw URLError(.badServerResponse) }; updateCurrent { $0.sheetExported = true; for i in $0.transactions.indices where $0.transactions[i].decision == .expense { $0.transactions[i].exported = true } }; notice = "Google Sheetsへ反映しました。" }
        catch { notice = "反映できませんでした：\(error.localizedDescription)" }
    }

    private func save() { guard !loading else { return }; if let d = try? JSONEncoder().encode(settings) { defaults.set(d, forKey: "settings") }; if let d = try? JSONEncoder().encode(months) { defaults.set(d, forKey: "months") } }
}

enum CSVParser {
    static func columns(_ line: String) -> [String] { var result: [String] = [], field = ""; var quoted = false; for char in line { if char == "\"" { quoted.toggle() } else if char == "," && !quoted { result.append(field.trimmingCharacters(in: .whitespacesAndNewlines)); field = "" } else { field.append(char) } }; result.append(field.trimmingCharacters(in: .whitespacesAndNewlines)); return result }
    static func date(_ value: String) -> Date? { for format in ["yyyy/MM/dd", "yyyy-MM-dd", "yyyy年M月d日", "M/d"] { let f = DateFormatter(); f.locale = Locale(identifier: "ja_JP"); f.dateFormat = format; if let d = f.date(from: value) { return d } }; return nil }
}

enum Keychain {
    private static let service = "com.fumiakiMogi777.luze", account = "apps-script-token"
    static var token: String {
        get { let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true]; var value: CFTypeRef?; guard SecItemCopyMatching(q as CFDictionary, &value) == errSecSuccess, let data = value as? Data else { return "" }; return String(data: data, encoding: .utf8) ?? "" }
        set { let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]; SecItemDelete(q as CFDictionary); guard let data = newValue.data(using: .utf8), !newValue.isEmpty else { return }; var item = q; item[kSecValueData as String] = data; SecItemAdd(item as CFDictionary, nil) }
    }
}
