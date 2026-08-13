import Foundation
import Testing
@testable import LuzeCore

struct SpreadsheetExportTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let builder = SpreadsheetExportPayloadBuilder()

    @Test("汎用月次収入をincome rowへ変換する")
    func genericMonthlyIncome() {
        let field = field(name: "業務委託A", kind: .income, suffix: 1)
        let payload = build(fields: [field], values: [field.id: 470_000])

        #expect(payload.apiVersion == 2)
        #expect(payload.month == "2026-07")
        #expect(payload.incomes.count == 1)
        #expect(payload.incomes[0].company == "業務委託A")
        #expect(payload.incomes[0].content == "業務委託A")
        #expect(payload.incomes[0].amount == 470_000)
        #expect(payload.incomes[0].source == .monthlyInput)
        #expect(payload.incomes[0].date == "2026-07-31")
    }

    @Test("固定費をexpense rowへ変換する")
    func fixedExpense() {
        let payload = build(calculatedExpenses: [
            .init(stableKey: "office-rent", company: "固定費", content: "事務所賃料", amount: 86_860, source: .fixedExpense)
        ])

        #expect(payload.expenses.count == 1)
        #expect(payload.expenses[0].source == .fixedExpense)
        #expect(payload.expenses[0].amount == 86_860)
    }

    @Test("交通費をexpense rowへ変換する")
    func commuteExpense() {
        let payload = build(calculatedExpenses: [
            .init(stableKey: "commute", company: "交通費", content: "通勤交通費", amount: 6_900, source: .commute)
        ])

        #expect(payload.expenses.count == 1)
        #expect(payload.expenses[0].source == .commute)
        #expect(payload.expenses[0].amount == 6_900)
    }

    @Test("expense判断済みカード取引だけをexpense rowへ変換する")
    func decidedCardExpense() {
        let transaction = Transaction(
            date: date(day: 11),
            merchant: "Adobe",
            amount: 1_180,
            decision: .expense,
            purpose: "編集ツール"
        )
        let payload = build(transactions: [transaction])

        #expect(payload.expenses.count == 1)
        #expect(payload.expenses[0].company == "Adobe")
        #expect(payload.expenses[0].content == "編集ツール")
        #expect(payload.expenses[0].date == "2026-07-11")
        #expect(payload.expenses[0].source == .cardStatement)
    }

    @Test("pending取引はExportしない")
    func pendingIsNotExported() {
        #expect(build(transactions: [transaction(decision: .pending)]).expenses.isEmpty)
    }

    @Test("excluded取引はExportしない")
    func excludedIsNotExported() {
        #expect(build(transactions: [transaction(decision: .excluded)]).expenses.isEmpty)
    }

    @Test("autoExcluded取引はExportしない")
    func automaticallyExcludedIsNotExported() {
        var item = transaction(decision: .excluded)
        item.classificationSource = .automaticExclusion
        #expect(build(transactions: [item]).expenses.isEmpty)
    }

    @Test("stableIDは同じ入力から毎回同じ値になる")
    func stableIDIsReproducible() {
        let first = build(transactions: [transaction(decision: .expense)])
        let second = build(transactions: [transaction(decision: .expense)])

        #expect(first.expenses[0].stableID == second.expenses[0].stableID)
        #expect(first.expenses[0].stableID == "luze_v2_7c675fcd8dbaa281d21445766fe89aa4806f92252456bcfde85d059f3b1d4b1e")
    }

    @Test("同一カード取引の判断変更でも別取引のstableIDを変えない")
    func duplicateCardOccurrenceIsStableAcrossDecisionChanges() {
        let firstDuplicate = transaction(decision: .pending)
        let secondDuplicate = transaction(decision: .expense)
        let before = build(transactions: [firstDuplicate, secondDuplicate])
        let after = build(transactions: [transaction(decision: .expense), secondDuplicate])

        #expect(before.expenses[0].stableID == after.expenses[1].stableID)
    }

    @Test("同じ入力から同じPayloadを生成する")
    func payloadIsDeterministic() {
        let field = field(name: "出版収入", kind: .income, suffix: 2)
        let first = build(fields: [field], values: [field.id: 28], transactions: [transaction(decision: .expense)])
        let second = build(fields: [field], values: [field.id: 28], transactions: [transaction(decision: .expense)])

        #expect(first == second)
    }

    @Test("収入・支出合計を計算する")
    func totals() {
        let first = field(name: "業務委託A", kind: .income, suffix: 3)
        let second = field(name: "出版収入", kind: .income, suffix: 4)
        let payload = build(
            fields: [first, second],
            values: [first.id: 470_000, second.id: 28],
            transactions: [transaction(decision: .expense)],
            calculatedExpenses: [.init(stableKey: "rent", company: "固定費", content: "家賃", amount: 86_860, source: .fixedExpense)]
        )

        #expect(payload.incomeTotal == 470_028)
        #expect(payload.expenseTotal == 87_630)
    }

    @Test("空月は空Payloadとして安全に生成する")
    func emptyMonth() async throws {
        let payload = build()

        #expect(payload.incomes.isEmpty)
        #expect(payload.expenses.isEmpty)
        try SpreadsheetPayloadValidator.validate(payload)
    }

    @Test("Mock送信成功時にPayloadを保持する")
    func mockSubmissionSucceeds() async throws {
        let destination = MockSpreadsheetDestination()
        let payload = build(transactions: [transaction(decision: .expense)])

        let result = try await destination.submit(payload)
        let received = await destination.receivedPayloads()

        #expect(result.success)
        #expect(result.acceptedRowCount == 1)
        #expect(received == [payload])
    }

    @Test("Mock通信失敗を安全に返す")
    func mockSubmissionFails() async {
        let destination = MockSpreadsheetDestination(behavior: .failure)

        await #expect(throws: SpreadsheetDestinationError.self) {
            try await destination.submit(build(transactions: [transaction(decision: .expense)]))
        }
    }

    @Test("Apps Scriptの不正レスポンスを安全に拒否する")
    func malformedResponseFails() async {
        let destination = AppsScriptSpreadsheetDestination(
            webAppURL: URL(string: "https://example.invalid/exec")!,
            apiToken: "test-token",
            transport: StubSpreadsheetTransport(response: .init(body: Data("not-json".utf8), statusCode: 200))
        )

        await #expect(throws: SpreadsheetDestinationError.self) {
            try await destination.testConnection()
        }
    }

    @Test("Apps Script v2のUPSERTレスポンスを解析する")
    func parsesV2SyncResponse() async throws {
        let response = """
        {
          "ok": true,
          "spreadsheetID": "test-sheet-id",
          "month": "2026-07",
          "income": {"inserted": 2, "updated": 0, "skipped": 1},
          "expense": {"inserted": 8, "updated": 1, "skipped": 2}
        }
        """
        let destination = AppsScriptSpreadsheetDestination(
            webAppURL: URL(string: "https://example.invalid/exec")!,
            apiToken: "test-token",
            expectedSpreadsheetID: "test-sheet-id",
            transport: StubSpreadsheetTransport(response: .init(body: Data(response.utf8), statusCode: 200))
        )

        let result = try await destination.submit(build(transactions: [transaction(decision: .expense)]))

        #expect(result.month == "2026-07")
        #expect(result.spreadsheetID == "test-sheet-id")
        #expect(result.insertedRowCount == 10)
        #expect(result.updatedRowCount == 1)
        #expect(result.totalSkippedRowCount == 3)
        #expect(result.acceptedRowCount == 14)
    }

    @Test("設定したSpreadsheetとApps Scriptの接続先不一致を拒否する")
    func rejectsDestinationMismatch() async {
        let response = #"{"ok":true,"spreadsheetID":"different-sheet"}"#
        let destination = AppsScriptSpreadsheetDestination(
            webAppURL: URL(string: "https://example.invalid/exec")!,
            apiToken: "test-token",
            expectedSpreadsheetID: "configured-test-sheet",
            transport: StubSpreadsheetTransport(response: .init(body: Data(response.utf8), statusCode: 200))
        )

        await #expect(throws: SpreadsheetDestinationError.destinationMismatch) {
            try await destination.testConnection()
        }
    }

    @Test("Apps Scriptエラーレスポンスを型付きエラーへ変換する")
    func parsesAppsScriptError() async {
        let destination = AppsScriptSpreadsheetDestination(
            webAppURL: URL(string: "https://example.invalid/exec")!,
            apiToken: "bad-token",
            transport: StubSpreadsheetTransport(response: .init(
                body: Data(#"{"ok":false,"error":"unauthorized"}"#.utf8),
                statusCode: 200
            ))
        )

        await #expect(throws: SpreadsheetDestinationError.rejected("unauthorized")) {
            try await destination.testConnection()
        }
    }

    @Test("専用テストSheetへSwift通信層から接続できる")
    func liveAppsScriptV2Connection() async throws {
        guard
            let endpoint = ProcessInfo.processInfo.environment["LUZE_TEST_APPS_SCRIPT_URL"],
            let token = ProcessInfo.processInfo.environment["LUZE_TEST_APPS_SCRIPT_TOKEN"],
            let url = URL(string: endpoint)
        else { return }

        let destination = AppsScriptSpreadsheetDestination(
            webAppURL: url,
            apiToken: token,
            expectedSpreadsheetID: "1Ng1Q4JA9C8thFdKn4zBWertpcOWmH4Tk6KW2w28Pu0A"
        )

        let health = try await destination.testConnection()
        #expect(health.success)
        #expect(health.spreadsheetID == "1Ng1Q4JA9C8thFdKn4zBWertpcOWmH4Tk6KW2w28Pu0A")

        let payload = SpreadsheetExportPayload(
            month: "2026-08",
            incomes: [.init(
                stableID: "luze_v2_acceptance_income_001",
                date: "2026-08-31",
                company: "匿名テスト会社A",
                content: "匿名テスト業務・修正版",
                amount: 120_000,
                source: .monthlyInput
            )],
            expenses: [
                .init(
                    stableID: "luze_v2_acceptance_expense_001",
                    date: "2026-08-12",
                    company: "匿名テスト店舗A",
                    content: "匿名テスト経費",
                    amount: 1_200,
                    source: .cardStatement
                ),
                .init(
                    stableID: "luze_v2_acceptance_expense_002",
                    date: "2026-08-13",
                    company: "匿名テスト店舗B",
                    content: "匿名テスト備品",
                    amount: 2_500,
                    source: .cardStatement
                )
            ]
        )
        let sync = try await destination.submit(payload)
        #expect(sync.insertedRowCount == 0)
        #expect(sync.updatedRowCount == 0)
        #expect(sync.totalSkippedRowCount == 3)
    }

    @Test("API Tokenを説明・レスポンス・エラーへ平文出力しない")
    func tokenIsRedacted() async throws {
        let token = "never-print-this-token"
        let response = """
        {"ok":true,"message":"accepted \(token)","acceptedRowCount":0,"skippedRowCount":0}
        """
        let destination = AppsScriptSpreadsheetDestination(
            webAppURL: URL(string: "https://example.invalid/exec")!,
            apiToken: token,
            transport: StubSpreadsheetTransport(response: .init(body: Data(response.utf8), statusCode: 200))
        )

        let result = try await destination.testConnection()

        #expect(!destination.description.contains(token))
        #expect(result.message == "accepted <redacted>")
        #expect(!SpreadsheetDestinationError.transportFailure.localizedDescription.contains(token))
    }

    private func build(
        fields: [MonthlyFieldDefinition] = [],
        values: [UUID: Int] = [:],
        transactions: [Transaction] = [],
        calculatedExpenses: [SpreadsheetCalculatedExpense] = []
    ) -> SpreadsheetExportPayload {
        var data = MonthlyData()
        data.fieldValues = values
        data.transactions = transactions
        return builder.build(
            month: date(day: 1),
            monthlyFields: fields,
            monthlyData: data,
            calculatedExpenses: calculatedExpenses
        )
    }

    private func field(name: String, kind: MonthlyFieldKind, suffix: Int) -> MonthlyFieldDefinition {
        MonthlyFieldDefinition(
            id: UUID(uuidString: String(format: "11111111-1111-1111-1111-%012d", suffix))!,
            name: name,
            kind: kind,
            exportKey: "legacy-key-is-not-used"
        )
    }

    private func transaction(decision: Decision) -> Transaction {
        Transaction(date: date(day: 14), merchant: "Example Store", amount: 770, decision: decision, purpose: "資料")
    }

    private func date(day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: day))!
    }
}

private struct StubSpreadsheetTransport: SpreadsheetHTTPTransport {
    var response: SpreadsheetHTTPResponse
    func send(_ request: URLRequest) async throws -> SpreadsheetHTTPResponse { response }
}
