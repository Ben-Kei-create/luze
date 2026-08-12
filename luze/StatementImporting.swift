import Foundation

struct ImportedStatementTransaction: Hashable {
    var transactionDate: Date
    var originalMerchantName: String
    var amount: Int
}

protocol StatementImporter {
    var id: String { get }
    var displayName: String { get }
    var allowedFileExtensions: Set<String> { get }
    func importTransactions(from url: URL, targetMonth: Date?) throws -> [ImportedStatementTransaction]
}

struct VpassStatementImporter: StatementImporter {
    let id = "vpass"
    let displayName = "三井住友カード / Vpass"
    let allowedFileExtensions: Set<String> = ["csv"]

    // Generalization Refactor 0では既存挙動を維持する。対象月抽出を含む本実装はMilestone 2で置き換える。
    func importTransactions(from url: URL, targetMonth: Date?) throws -> [ImportedStatementTransaction] {
        let data = try Data(contentsOf: url)
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .shiftJIS) ?? ""
        var items: [ImportedStatementTransaction] = []
        for line in text.components(separatedBy: .newlines) where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            let columns = CSVParser.columns(line)
            guard let dateIndex = columns.firstIndex(where: { CSVParser.date($0) != nil }),
                  let date = CSVParser.date(columns[dateIndex]) else { continue }
            let amountIndex = columns.indices.reversed().first {
                Int(columns[$0].replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "¥", with: "")) != nil
            }
            guard let amountIndex, amountIndex != dateIndex,
                  let amount = Int(columns[amountIndex].replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "¥", with: "")) else { continue }
            let merchant = columns.indices.filter { $0 != dateIndex && $0 != amountIndex }.map { columns[$0] }.first { !$0.isEmpty } ?? "不明な加盟店"
            items.append(.init(transactionDate: date, originalMerchantName: merchant, amount: abs(amount)))
        }
        guard !items.isEmpty else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "取引を読み取れませんでした。CSV形式を確認してください。"])
        }
        return items
    }
}

enum StatementImporterRegistry {
    static func importer(for source: StatementSource) -> any StatementImporter {
        switch source.importerID {
        case "vpass": VpassStatementImporter()
        default: VpassStatementImporter()
        }
    }
}

enum CSVParser {
    static func columns(_ line: String) -> [String] {
        var result: [String] = [], field = ""
        var quoted = false
        for char in line {
            if char == "\"" { quoted.toggle() }
            else if char == "," && !quoted { result.append(field.trimmingCharacters(in: .whitespacesAndNewlines)); field = "" }
            else { field.append(char) }
        }
        result.append(field.trimmingCharacters(in: .whitespacesAndNewlines))
        return result
    }

    static func date(_ value: String) -> Date? {
        for format in ["yyyy/MM/dd", "yyyy-MM-dd", "yyyy年M月d日", "M/d"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ja_JP")
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}
