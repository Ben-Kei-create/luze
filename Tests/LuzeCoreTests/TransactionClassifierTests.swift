import Foundation
import Testing
@testable import LuzeCore

struct TransactionClassifierTests {
    private let classifier = TransactionClassifier()
    private let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 7, day: 14))!

    @Test("自動経費ルールを適用する")
    func automaticExpense() {
        let result = classify("ＡＤＯＢＥ")
        #expect(result.decision == .expense)
        #expect(result.source == .automaticExpense)
        #expect(result.purpose == "編集ツール")
    }

    @Test("自動除外ルールを適用する")
    func automaticExclusion() {
        let result = classify("モバイルＰＡＳＭＯ")
        #expect(result.decision == .excluded)
        #expect(result.source == .automaticExclusion)
    }

    @Test("未登録加盟店は要確認にする")
    func unknownMerchantNeedsReview() {
        #expect(classify("未登録ストア").decision == .pending)
    }

    @Test("確定済み判断履歴を再利用する")
    func reusesDecisionHistory() {
        let transaction = imported("履歴ストア")
        let fingerprint = TransactionFingerprint.make(date: date, normalizedMerchantName: transaction.normalizedMerchantName, amount: 770)
        let record = DecisionRecord(
            transactionFingerprint: fingerprint,
            period: "202607",
            date: date,
            merchant: "履歴ストア",
            amount: 770,
            decision: .expense,
            purpose: "書籍"
        )
        let result = classifier.classify(transaction: transaction, rules: SettingsData.defaultMerchantRules, history: [record], permanentExclusions: [])
        #expect(result.decision == .expense)
        #expect(result.purpose == "書籍")
        #expect(result.source == .decisionHistory)
    }

    @Test("保留履歴は保留のまま再確認する")
    func pendingHistoryIsReviewedAgain() {
        let transaction = imported("ADOBE")
        let fingerprint = TransactionFingerprint.make(date: date, normalizedMerchantName: transaction.normalizedMerchantName, amount: 770)
        let record = DecisionRecord(
            transactionFingerprint: fingerprint,
            period: "202607",
            date: date,
            merchant: "ADOBE",
            amount: 770,
            decision: .pending,
            purpose: ""
        )
        let result = classifier.classify(transaction: transaction, rules: SettingsData.defaultMerchantRules, history: [record], permanentExclusions: [])
        #expect(result.decision == .pending)
        #expect(result.source == .decisionHistory)
    }

    @Test("同一CSV内のFingerprint重複でも加盟店ルールを適用する")
    func fingerprintCollisionStillAppliesMerchantRule() {
        let result = classifier.classify(
            transaction: imported("ADOBE"),
            rules: SettingsData.defaultMerchantRules,
            history: [],
            permanentExclusions: [],
            hasFingerprintCollision: true
        )
        #expect(result.decision == .expense)
    }

    @Test("判断履歴のFingerprint衝突時は自動再利用しない")
    func duplicateDecisionHistoryNeedsReview() {
        let transaction = imported("履歴ストア")
        let fingerprint = TransactionFingerprint.make(date: date, normalizedMerchantName: transaction.normalizedMerchantName, amount: 770)
        let record = DecisionRecord(transactionFingerprint: fingerprint, period: "202607", date: date, merchant: "履歴ストア", amount: 770, decision: .expense, purpose: "資料")
        let result = classifier.classify(transaction: transaction, rules: [], history: [record, record], permanentExclusions: [])
        #expect(result.decision == .pending)
    }

    @Test("AmazonとAppleは恒久除外できない", arguments: ["AMAZON.CO.JP", "APPLE COM BILL"])
    func protectedMerchantCannotBeRemembered(_ merchant: String) {
        var exclusions: [PermanentMerchantExclusion] = []
        #expect(throws: PermanentExclusionError.self) {
            try PermanentExclusionMemory.remember(merchant: merchant, in: &exclusions)
        }
        #expect(exclusions.isEmpty)
    }

    @Test("恒久自動除外を登録・解除できる")
    func remembersAndForgetsPermanentExclusion() throws {
        var exclusions: [PermanentMerchantExclusion] = []
        try PermanentExclusionMemory.remember(merchant: "個人利用ストア", in: &exclusions)
        #expect(exclusions.count == 1)
        #expect(classifier.classify(transaction: imported("個人利用ストア"), rules: SettingsData.defaultMerchantRules, history: [], permanentExclusions: exclusions).decision == .excluded)
        PermanentExclusionMemory.forget(id: exclusions[0].id, in: &exclusions)
        #expect(exclusions.isEmpty)
    }

    @Test("除外判断を保留へ変更して履歴へ保存する")
    func changesExcludedDecisionToPending() {
        var records: [DecisionRecord] = []
        var transaction = Transaction(date: date, merchant: "個人利用ストア", amount: 770, decision: .excluded)
        DecisionHistory.upsert(transaction: transaction, period: "202607", records: &records)
        transaction.decision = .pending
        DecisionHistory.upsert(transaction: transaction, period: "202607", records: &records)
        #expect(records.count == 1)
        #expect(records[0].decision == .pending)
    }

    @Test("判断履歴はCodableで再起動後に復元できる")
    func decisionHistoryPersists() throws {
        var records: [DecisionRecord] = []
        let transaction = Transaction(date: date, merchant: "履歴ストア", amount: 770, decision: .expense, purpose: "資料")
        DecisionHistory.upsert(transaction: transaction, period: "202607", records: &records)
        let restored = try JSONDecoder().decode([DecisionRecord].self, from: JSONEncoder().encode(records))
        #expect(restored == records)
    }

    @Test("旧設定データを分類機能付きモデルへ移行できる")
    func migratesLegacySettings() throws {
        let legacy = """
        {
          "rules": [
            {"id":"00000000-0000-0000-0000-000000000001","keyword":"Amazon","action":"毎回確認","purpose":""}
          ]
        }
        """
        let settings = try JSONDecoder().decode(SettingsData.self, from: Data(legacy.utf8))
        #expect(settings.rules[0].isProtected)
        #expect(settings.permanentMerchantExclusions.isEmpty)
    }

    @Test("旧取引データをclassificationSourceなしで復元できる")
    func migratesLegacyTransaction() throws {
        let dateText = ISO8601DateFormatter().string(from: date)
        let legacy = """
        {"id":"00000000-0000-0000-0000-000000000002","date":"\(dateText)","merchant":"旧ストア","amount":770,"decision":"保留","purpose":"","exported":false}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let transaction = try decoder.decode(Transaction.self, from: Data(legacy.utf8))
        #expect(transaction.classificationSource == .review)
    }

    @Test("実CSVの分類件数を環境変数指定時のみ照合する")
    func verifiesRealCSVClassificationWhenProvided() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["LUZE_REAL_VPASS_CSV"] else { return }
        let month = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 7, day: 1))!
        let parsed = try VpassCSVParser().parse(url: URL(fileURLWithPath: path), targetMonth: month)
        let results = parsed.transactions.map {
            classifier.classify(
                transaction: .init(id: $0.id, transactionDate: $0.transactionDate, originalMerchantName: $0.originalMerchantName, normalizedMerchantName: $0.normalizedMerchantName, amount: $0.amount),
                rules: SettingsData.defaultMerchantRules,
                history: [],
                permanentExclusions: []
            )
        }
        #expect(results.count == 50)
        #expect(results.filter { $0.source == .automaticExpense }.count == 6)
        #expect(results.filter { $0.source == .automaticExclusion }.count == 25)
        #expect(results.filter { $0.decision == .pending }.count == 19)
    }

    private func classify(_ merchant: String) -> ClassificationResult {
        classifier.classify(transaction: imported(merchant), rules: SettingsData.defaultMerchantRules, history: [], permanentExclusions: [])
    }

    private func imported(_ merchant: String) -> ImportedStatementTransaction {
        .init(
            id: UUID(),
            transactionDate: date,
            originalMerchantName: merchant,
            normalizedMerchantName: MerchantNormalizer().normalize(merchant),
            amount: 770
        )
    }
}
