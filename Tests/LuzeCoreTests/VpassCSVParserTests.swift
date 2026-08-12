import Foundation
import Testing
@testable import LuzeCore

struct VpassCSVParserTests {
    private let parser = VpassCSVParser()

    @Test("正常なヘッダー付きCSVを解析する")
    func parsesNormalCSV() throws {
        let result = try parser.parse(url: fixture("normal-header"), targetMonth: month(2026, 7))
        #expect(result.transactions.count == 2)
        #expect(result.statistics.parsedTransactionCount == 3)
    }

    @Test("ヘッダーなしCSVを解析する")
    func parsesHeaderlessCSV() throws {
        let result = try parser.parse(url: fixture("headerless"), targetMonth: month(2026, 7))
        #expect(result.transactions.count == 2)
        #expect(result.statistics.skippedRowCount == 1)
    }

    @Test("空行を安全にスキップする")
    func skipsEmptyLines() throws {
        let result = try parser.parse(url: fixture("normal-header"), targetMonth: month(2026, 7))
        #expect(result.statistics.skippedRowCount == 2)
    }

    @Test("日本語加盟店名の原文を保持する")
    func preservesJapaneseMerchant() throws {
        let result = try parser.parse(url: fixture("headerless"), targetMonth: month(2026, 7))
        #expect(result.transactions[1].originalMerchantName == "日本語サービス")
    }

    @Test("カンマと通貨記号を含む金額を解析する")
    func parsesAmount() throws {
        let result = try parser.parse(url: fixture("normal-header"), targetMonth: month(2026, 7))
        #expect(result.transactions.map(\.amount) == [770, 1_200])
    }

    @Test("指定月以外を除外する")
    func filtersTargetMonth() throws {
        let result = try parser.parse(url: fixture("normal-header"), targetMonth: month(2026, 8))
        #expect(result.transactions.count == 1)
        #expect(result.transactions[0].originalMerchantName == "翌月ストア")
    }

    @Test("不正行があっても有効行を返す")
    func skipsInvalidRows() throws {
        let result = try parser.parse(url: fixture("normal-header"), targetMonth: month(2026, 7))
        #expect(result.statistics.sourceRowCount == 7)
        #expect(result.statistics.skippedRowCount == 2)
    }

    @Test("空CSVは安全にエラーを返す")
    func rejectsEmptyCSV() {
        #expect(throws: VpassCSVParserError.self) {
            try parser.parse(url: fixture("empty"), targetMonth: month(2026, 7))
        }
    }

    @Test("Shift JISの日本語CSVを解析する")
    func parsesShiftJIS() throws {
        let source = "2026/07/03,日本語加盟店,1234\n"
        let data = try #require(source.data(using: .shiftJIS))
        let result = try parser.parse(data: data, targetMonth: month(2026, 7))
        #expect(result.transactions[0].originalMerchantName == "日本語加盟店")
    }

    @Test("実CSVを環境変数指定時のみ照合する")
    func verifiesRealCSVWhenProvided() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["LUZE_REAL_VPASS_CSV"] else { return }
        let result = try parser.parse(url: URL(fileURLWithPath: path), targetMonth: month(2026, 7))
        if let expected = environment["LUZE_EXPECTED_PARSED"].flatMap(Int.init) {
            #expect(result.statistics.parsedTransactionCount == expected)
        }
        if let expected = environment["LUZE_EXPECTED_SELECTED"].flatMap(Int.init) {
            #expect(result.statistics.selectedTransactionCount == expected)
        }
        if let expected = environment["LUZE_EXPECTED_SKIPPED"].flatMap(Int.init) {
            #expect(result.statistics.skippedRowCount == expected)
        }
    }

    private func fixture(_ name: String) -> URL {
        Bundle.module.url(forResource: name, withExtension: "csv", subdirectory: "Fixtures")!
    }

    private func month(_ year: Int, _ month: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: 1))!
    }
}

struct MerchantNormalizerTests {
    @Test("全半角・大小文字・連続空白を正規化する")
    func normalizesMerchantName() {
        let value = MerchantNormalizer().normalize("  ａｍａｚｏｎ　   M  Store  ")
        #expect(value == "AMAZON M STORE")
    }
}
