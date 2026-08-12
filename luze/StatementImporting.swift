import Foundation

struct ImportedStatementTransaction: Identifiable, Hashable {
    var id: UUID
    var transactionDate: Date
    var originalMerchantName: String
    var normalizedMerchantName: String
    var amount: Int
}

struct StatementImportStatistics: Equatable {
    var sourceRowCount: Int
    var parsedTransactionCount: Int
    var selectedTransactionCount: Int
    var skippedRowCount: Int
}

struct StatementImportResult {
    var transactions: [ImportedStatementTransaction]
    var statistics: StatementImportStatistics
}

protocol StatementImporter {
    var id: String { get }
    var displayName: String { get }
    var allowedFileExtensions: Set<String> { get }
    func importTransactions(from url: URL, targetMonth: Date) throws -> StatementImportResult
}

struct VpassTransaction: Identifiable, Hashable {
    var id: UUID
    var transactionDate: Date
    var originalMerchantName: String
    var normalizedMerchantName: String
    var amount: Int
}

struct VpassCSVParseResult {
    var transactions: [VpassTransaction]
    var statistics: StatementImportStatistics
}

enum VpassCSVParserError: LocalizedError {
    case unsupportedEncoding
    case noTransactions
    case targetMonthNotFound(detectedMonths: [String])

    var errorDescription: String? {
        switch self {
        case .unsupportedEncoding:
            "CSVの文字コードを判定できません。"
        case .noTransactions:
            "Vpass CSVから利用明細を読み取れませんでした。"
        case .targetMonthNotFound(let months):
            "対象月の利用明細がありません。検出月: \(months.joined(separator: ", "))"
        }
    }
}

struct MerchantNormalizer {
    func normalize(_ value: String) -> String {
        value
            .precomposedStringWithCompatibilityMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .uppercased(with: Locale(identifier: "en_US_POSIX"))
    }
}

struct VpassCSVParser {
    private static let dateHeaders = ["利用日", "ご利用日", "利用年月日", "ご利用年月日", "取引日", "日付"]
    private static let merchantHeaders = ["利用店名", "ご利用店名", "利用先", "利用内容", "店名", "加盟店名"]
    private static let amountHeaders = ["利用金額", "ご利用金額", "金額", "支払金額", "ご利用金額円", "利用金額円"]

    private let calendar: Calendar
    private let normalizer = MerchantNormalizer()

    init(calendar: Calendar = Calendar(identifier: .gregorian)) {
        self.calendar = calendar
    }

    func parse(url: URL, targetMonth: Date) throws -> VpassCSVParseResult {
        try parse(data: Data(contentsOf: url), targetMonth: targetMonth)
    }

    func parse(data: Data, targetMonth: Date) throws -> VpassCSVParseResult {
        let text = try decode(data)
        let rows = CSVReader.parse(text)
        let header = findHeader(in: rows)
        let dateIndex = header?.dateIndex ?? 0
        let merchantIndex = header?.merchantIndex ?? 1
        let amountIndex = header?.amountIndex ?? 2
        let dataRows = header.map { Array(rows.dropFirst($0.rowIndex + 1)) } ?? rows
        let maximumIndex = max(dateIndex, merchantIndex, amountIndex)

        var parsed: [VpassTransaction] = []
        var skipped = 0
        var detectedMonths: Set<String> = []

        for row in dataRows {
            guard maximumIndex < row.count,
                  let date = parseDate(row[dateIndex]),
                  !row[merchantIndex].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let amount = parseAmount(row[amountIndex]) else {
                skipped += 1
                continue
            }
            let originalMerchantName = row[merchantIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            let components = calendar.dateComponents([.year, .month], from: date)
            detectedMonths.insert(String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0))
            parsed.append(.init(
                id: UUID(),
                transactionDate: date,
                originalMerchantName: originalMerchantName,
                normalizedMerchantName: normalizer.normalize(originalMerchantName),
                amount: amount
            ))
        }

        guard !parsed.isEmpty else { throw VpassCSVParserError.noTransactions }
        let target = calendar.dateComponents([.year, .month], from: targetMonth)
        let selected = parsed.filter {
            let value = calendar.dateComponents([.year, .month], from: $0.transactionDate)
            return value.year == target.year && value.month == target.month
        }
        guard !selected.isEmpty else {
            throw VpassCSVParserError.targetMonthNotFound(detectedMonths: detectedMonths.sorted())
        }
        return .init(
            transactions: selected,
            statistics: .init(
                sourceRowCount: rows.count,
                parsedTransactionCount: parsed.count,
                selectedTransactionCount: selected.count,
                skippedRowCount: skipped
            )
        )
    }

    private func decode(_ data: Data) throws -> String {
        var bytes = data
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes.removeFirst(3) }
        if let text = String(data: bytes, encoding: .utf8) { return text }
        if let text = String(data: bytes, encoding: .shiftJIS) { return text }
        throw VpassCSVParserError.unsupportedEncoding
    }

    private func cleanHeader(_ value: String) -> String {
        let removable = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "()（）【】[]・/\\_-"))
        return value.components(separatedBy: removable).joined().lowercased()
    }

    private func findHeader(in rows: [[String]]) -> (rowIndex: Int, dateIndex: Int, merchantIndex: Int, amountIndex: Int)? {
        let dates = Set(Self.dateHeaders.map(cleanHeader))
        let merchants = Set(Self.merchantHeaders.map(cleanHeader))
        let amounts = Set(Self.amountHeaders.map(cleanHeader))
        for (rowIndex, row) in rows.prefix(30).enumerated() {
            let cleaned = row.map(cleanHeader)
            if let dateIndex = cleaned.firstIndex(where: dates.contains),
               let merchantIndex = cleaned.firstIndex(where: merchants.contains),
               let amountIndex = cleaned.firstIndex(where: amounts.contains) {
                return (rowIndex, dateIndex, merchantIndex, amountIndex)
            }
        }
        return nil
    }

    private func parseAmount(_ value: String) -> Int? {
        let normalized = value.precomposedStringWithCompatibilityMapping
        let filtered = normalized.filter { $0.isNumber || $0 == "-" }
        guard !filtered.isEmpty, filtered != "-" else { return nil }
        return Int(filtered)
    }

    private func parseDate(_ value: String) -> Date? {
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
        for format in ["yyyy/MM/dd", "yyyy-MM-dd", "yy/MM/dd", "MM/dd"] {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.isLenient = false
            formatter.dateFormat = format
            guard let date = formatter.date(from: raw) else { continue }
            if format == "MM/dd" {
                var components = calendar.dateComponents([.month, .day], from: date)
                components.year = calendar.component(.year, from: Date())
                return calendar.date(from: components)
            }
            return date
        }

        let pattern = #"^(?:(\d{2,4})[年/.-])?(\d{1,2})[月/.-](\d{1,2})日?"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)) else { return nil }
        func integer(at index: Int) -> Int? {
            let range = match.range(at: index)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: raw) else { return nil }
            return Int(raw[swiftRange])
        }
        var year = integer(at: 1) ?? calendar.component(.year, from: Date())
        if year < 100 { year += 2000 }
        return calendar.date(from: DateComponents(year: year, month: integer(at: 2), day: integer(at: 3)))
    }
}

struct VpassStatementImporter: StatementImporter {
    let id = "vpass"
    let displayName = "三井住友カード / Vpass"
    let allowedFileExtensions: Set<String> = ["csv"]

    func importTransactions(from url: URL, targetMonth: Date) throws -> StatementImportResult {
        let result = try VpassCSVParser().parse(url: url, targetMonth: targetMonth)
        return .init(
            transactions: result.transactions.map {
                .init(
                    id: $0.id,
                    transactionDate: $0.transactionDate,
                    originalMerchantName: $0.originalMerchantName,
                    normalizedMerchantName: $0.normalizedMerchantName,
                    amount: $0.amount
                )
            },
            statistics: result.statistics
        )
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

enum CSVReader {
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            if character == "\"" {
                if quoted, next < text.endIndex, text[next] == "\"" {
                    field.append("\"")
                    index = text.index(after: next)
                    continue
                }
                quoted.toggle()
            } else if character == ",", !quoted {
                row.append(field)
                field = ""
            } else if character.isNewline, !quoted {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else {
                field.append(character)
            }
            index = text.index(after: index)
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}
