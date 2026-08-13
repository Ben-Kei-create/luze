import Foundation
import Testing
@testable import LuzeCore

@Suite("Evidence scanner")
struct EvidenceScannerTests {
    @Test("対象月だけを再帰的に読み、PDFとCSVを分類する")
    func scansOnlyTargetMonthRecursively() throws {
        try withTemporaryRoot { root in
            let target = try makeDirectory(root.appendingPathComponent("202608"))
            let nested = try makeDirectory(target.appendingPathComponent("utilities"))
            try writeFile(nested.appendingPathComponent("KABU＆電気_請求書.PDF"))
            try writeFile(target.appendingPathComponent("vpass_202608.csv"))
            let otherMonth = try makeDirectory(root.appendingPathComponent("202607"))
            try writeFile(otherMonth.appendingPathComponent("KABU&電気.pdf"))

            let rules = [
                ReceiptRule(name: "電気", filenameContains: "KABU&電気", fileType: .pdf),
                ReceiptRule(name: "カード明細", filenameContains: "vpass", fileType: .csv)
            ]
            let result = try EvidenceScanner().scan(rootURL: root, periodKey: "202608", rules: rules)

            #expect(result.monthFolderURL?.standardizedFileURL.path == target.standardizedFileURL.path)
            #expect(result.files.count == 2)
            #expect(result.pdfCount == 1)
            #expect(result.csvCount == 1)
            #expect(result.subfolderCount == 1)
            #expect(result.ruleResults.map(\.status) == [.found, .found])
            #expect(result.ruleResults[0].matches[0].relativePath == "utilities/KABU＆電気_請求書.PDF")
        }
    }

    @Test("一致が0件・1件・複数件の状態を返す")
    func reportsMissingFoundAndMultiple() throws {
        try withTemporaryRoot { root in
            let target = try makeDirectory(root.appendingPathComponent("2026-08"))
            try writeFile(target.appendingPathComponent("gas.pdf"))
            try writeFile(target.appendingPathComponent("adobe_1.pdf"))
            try writeFile(target.appendingPathComponent("ADOBE_2.PDF"))

            let rules = [
                ReceiptRule(name: "電気", filenameContains: "electric", fileType: .pdf),
                ReceiptRule(name: "ガス", filenameContains: "gas", fileType: .pdf),
                ReceiptRule(name: "Adobe", filenameContains: "adobe", fileType: .pdf)
            ]
            let result = try EvidenceScanner().scan(rootURL: root, periodKey: "202608", rules: rules)

            #expect(result.ruleResults.map(\.status) == [.missing, .found, .multiple])
            #expect(result.hasMissingRequiredEvidence)
        }
    }

    @Test("任意ルールの不足は必須不足に含めない")
    func ignoresMissingOptionalRule() throws {
        try withTemporaryRoot { root in
            _ = try makeDirectory(root.appendingPathComponent("202608"))
            let rule = ReceiptRule(
                name: "任意資料",
                filenameContains: "optional",
                fileType: .pdf,
                isRequired: false
            )
            let result = try EvidenceScanner().scan(rootURL: root, periodKey: "202608", rules: [rule])

            #expect(result.ruleResults[0].status == .missing)
            #expect(!result.hasMissingRequiredEvidence)
        }
    }

    @Test("空キーワードは指定形式の全ファイルを候補にする")
    func emptyKeywordMatchesFileType() throws {
        try withTemporaryRoot { root in
            let target = try makeDirectory(root.appendingPathComponent("202608"))
            try writeFile(target.appendingPathComponent("statement.csv"))
            try writeFile(target.appendingPathComponent("receipt.pdf"))
            let rule = ReceiptRule(name: "カード明細", filenameContains: "", fileType: .csv)

            let result = try EvidenceScanner().scan(rootURL: root, periodKey: "202608", rules: [rule])

            #expect(result.ruleResults[0].status == .found)
            #expect(result.ruleResults[0].matches[0].relativePath == "statement.csv")
        }
    }

    @Test("対象月がなければ安全に不足結果を返す")
    func missingMonthFolderIsSafe() throws {
        try withTemporaryRoot { root in
            let rule = ReceiptRule(name: "領収書", filenameContains: "receipt", fileType: .pdf)
            let result = try EvidenceScanner().scan(rootURL: root, periodKey: "202608", rules: [rule])

            #expect(result.monthFolderURL == nil)
            #expect(result.files.isEmpty)
            #expect(result.ruleResults[0].status == .missing)
            #expect(result.hasMissingRequiredEvidence)
        }
    }

    @Test("不正な対象月形式を拒否する")
    func rejectsInvalidPeriod() throws {
        try withTemporaryRoot { root in
            #expect(throws: EvidenceScannerError.invalidPeriod) {
                try EvidenceScanner().scan(rootURL: root, periodKey: "2026-08", rules: [])
            }
        }
    }

    @Test("存在しないルートを拒否する")
    func rejectsUnreadableRoot() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        #expect(throws: EvidenceScannerError.unreadableRoot) {
            try EvidenceScanner().scan(rootURL: missing, periodKey: "202608", rules: [])
        }
    }

    @Test("旧設定の証憑ルールはPDFとして移行する")
    func migratesLegacyReceiptRule() throws {
        let data = Data(#"{"name":"電気","filenameContains":"electric","isRequired":true}"#.utf8)
        let rule = try JSONDecoder().decode(ReceiptRule.self, from: data)
        #expect(rule.fileType == .pdf)
    }

    @Test("Security-Scoped Bookmarkを保存して再起動相当で復元する")
    func persistsSecurityScopedBookmark() throws {
        let suiteName = "luze-evidence-bookmark-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        try withTemporaryRoot { root in
            let writer = EvidenceFolderBookmarkStore(defaults: defaults, key: "bookmark")
            try writer.save(root)

            let restored = try EvidenceFolderBookmarkStore(defaults: defaults, key: "bookmark").restore()

            #expect(restored.standardizedFileURL.path == root.standardizedFileURL.path)
            #expect(defaults.data(forKey: "bookmark")?.isEmpty == false)
        }
    }

    private func withTemporaryRoot(_ operation: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("luze-evidence-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try operation(root)
    }

    @discardableResult
    private func makeDirectory(_ url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeFile(_ url: URL) throws {
        try Data("test".utf8).write(to: url)
    }
}
