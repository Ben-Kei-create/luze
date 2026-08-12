import CryptoKit
import Foundation

enum SpreadsheetExportSource: String, Codable, CaseIterable, Sendable {
    case monthlyInput
    case fixedExpense
    case commute
    case cardStatement
}

struct SpreadsheetExportRow: Codable, Equatable, Identifiable, Sendable {
    var stableID: String
    var date: String
    var company: String
    var content: String
    var amount: Int
    var source: SpreadsheetExportSource

    var id: String { stableID }
}

struct SpreadsheetExportPayload: Codable, Equatable, Sendable {
    var apiVersion: Int
    var month: String
    var incomes: [SpreadsheetExportRow]
    var expenses: [SpreadsheetExportRow]

    init(
        apiVersion: Int = 2,
        month: String,
        incomes: [SpreadsheetExportRow] = [],
        expenses: [SpreadsheetExportRow] = []
    ) {
        self.apiVersion = apiVersion
        self.month = month
        self.incomes = incomes
        self.expenses = expenses
    }

    var incomeTotal: Int { incomes.reduce(0) { $0 + $1.amount } }
    var expenseTotal: Int { expenses.reduce(0) { $0 + $1.amount } }
}

struct SpreadsheetCalculatedExpense: Equatable, Sendable {
    var stableKey: String
    var company: String
    var content: String
    var amount: Int
    var source: SpreadsheetExportSource

    init(
        stableKey: String,
        company: String,
        content: String,
        amount: Int,
        source: SpreadsheetExportSource
    ) {
        self.stableKey = stableKey
        self.company = company
        self.content = content
        self.amount = amount
        self.source = source
    }
}

enum SpreadsheetStableID {
    static func make(
        month: String,
        source: SpreadsheetExportSource,
        stableKey: String
    ) -> String {
        let canonical = [
            "v2",
            month,
            source.rawValue,
            stableKey
        ].joined(separator: "\u{1F}")
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return "luze_v2_" + digest.map { String(format: "%02x", $0) }.joined()
    }
}

struct SpreadsheetExportPayloadBuilder: Sendable {
    private var calendar: Calendar

    init(calendar: Calendar = Calendar(identifier: .gregorian)) {
        self.calendar = calendar
    }

    func build(
        month: Date,
        monthlyFields: [MonthlyFieldDefinition],
        monthlyData: MonthlyData,
        calculatedExpenses: [SpreadsheetCalculatedExpense]
    ) -> SpreadsheetExportPayload {
        let monthString = formatMonth(month)
        let closingDate = formatDate(lastDay(of: month))

        let incomes = monthlyFields.compactMap { field -> SpreadsheetExportRow? in
            guard field.kind == .income else { return nil }
            let amount = monthlyData.value(for: field.id)
            guard amount > 0 else { return nil }
            return row(
                month: monthString,
                stableKey: "monthly-field:\(field.id.uuidString.lowercased())",
                date: closingDate,
                company: field.name,
                content: field.name,
                amount: amount,
                source: .monthlyInput
            )
        }

        var expenses = calculatedExpenses.compactMap { expense -> SpreadsheetExportRow? in
            guard expense.amount > 0 else { return nil }
            return row(
                month: monthString,
                stableKey: expense.stableKey,
                date: closingDate,
                company: expense.company,
                content: expense.content,
                amount: expense.amount,
                source: expense.source
            )
        }

        var occurrences: [String: Int] = [:]
        for transaction in monthlyData.transactions {
            let normalizedMerchant = MerchantNormalizer().normalize(transaction.merchant)
            let fingerprint = TransactionFingerprint.make(
                date: transaction.date,
                normalizedMerchantName: normalizedMerchant,
                amount: transaction.amount,
                calendar: calendar
            )
            let occurrence = occurrences[fingerprint, default: 0]
            occurrences[fingerprint] = occurrence + 1
            guard transaction.decision == .expense, transaction.amount > 0 else { continue }
            expenses.append(row(
                month: monthString,
                stableKey: "card:\(fingerprint):\(occurrence)",
                date: formatDate(transaction.date),
                company: transaction.merchant,
                content: transaction.purpose.isEmpty ? "カード利用" : transaction.purpose,
                amount: transaction.amount,
                source: .cardStatement
            ))
        }

        return SpreadsheetExportPayload(month: monthString, incomes: incomes, expenses: expenses)
    }

    private func row(
        month: String,
        stableKey: String,
        date: String,
        company: String,
        content: String,
        amount: Int,
        source: SpreadsheetExportSource
    ) -> SpreadsheetExportRow {
        SpreadsheetExportRow(
            stableID: SpreadsheetStableID.make(
                month: month,
                source: source,
                stableKey: stableKey
            ),
            date: date,
            company: company,
            content: content,
            amount: amount,
            source: source
        )
    }

    private func lastDay(of month: Date) -> Date {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let day = calendar.date(byAdding: .day, value: -1, to: interval.end)
        else { return month }
        return day
    }

    private func formatMonth(_ date: Date) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }

    private func formatDate(_ date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

struct SpreadsheetDestinationResult: Codable, Equatable, Sendable {
    var success: Bool
    var message: String?
    var acceptedRowCount: Int?
    var skippedRowCount: Int?
}

enum SpreadsheetDestinationError: LocalizedError, Equatable {
    case invalidConfiguration
    case invalidPayload(String)
    case transportFailure
    case httpFailure(Int)
    case invalidResponse
    case rejected

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            "Spreadsheet接続設定を確認してください。"
        case .invalidPayload(let reason):
            "送信内容を確認してください（\(reason)）。"
        case .transportFailure:
            "Spreadsheetへ接続できませんでした。"
        case .httpFailure(let status):
            "Spreadsheet接続でHTTP \(status)エラーが発生しました。"
        case .invalidResponse:
            "Spreadsheetからの応答を確認できませんでした。"
        case .rejected:
            "Spreadsheetがリクエストを受け付けませんでした。"
        }
    }
}

protocol SpreadsheetDestination: Sendable {
    func testConnection() async throws -> SpreadsheetDestinationResult
    func validate(_ payload: SpreadsheetExportPayload) async throws
    func submit(_ payload: SpreadsheetExportPayload) async throws -> SpreadsheetDestinationResult
}

enum SpreadsheetPayloadValidator {
    nonisolated static func validate(_ payload: SpreadsheetExportPayload) throws {
        guard payload.apiVersion == 2 else {
            throw SpreadsheetDestinationError.invalidPayload("apiVersion")
        }
        let monthPattern = /^\d{4}-\d{2}$/
        guard payload.month.wholeMatch(of: monthPattern) != nil else {
            throw SpreadsheetDestinationError.invalidPayload("対象月")
        }
        let rows = payload.incomes + payload.expenses
        guard Set(rows.map(\.stableID)).count == rows.count else {
            throw SpreadsheetDestinationError.invalidPayload("stableID重複")
        }
        guard rows.allSatisfy({
            !$0.stableID.isEmpty && !$0.company.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.amount > 0
        }) else {
            throw SpreadsheetDestinationError.invalidPayload("行データ")
        }
    }
}

struct SpreadsheetHTTPResponse: Sendable {
    var body: Data
    var statusCode: Int
}

protocol SpreadsheetHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> SpreadsheetHTTPResponse
}

struct URLSessionSpreadsheetHTTPTransport: SpreadsheetHTTPTransport {
    func send(_ request: URLRequest) async throws -> SpreadsheetHTTPResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SpreadsheetDestinationError.invalidResponse
        }
        return .init(body: data, statusCode: http.statusCode)
    }
}

struct AppsScriptSpreadsheetDestination: SpreadsheetDestination, CustomStringConvertible {
    private let webAppURL: URL
    private let apiToken: String
    private let transport: any SpreadsheetHTTPTransport

    init(
        webAppURL: URL,
        apiToken: String,
        transport: any SpreadsheetHTTPTransport = URLSessionSpreadsheetHTTPTransport()
    ) {
        self.webAppURL = webAppURL
        self.apiToken = apiToken
        self.transport = transport
    }

    var description: String {
        "AppsScriptSpreadsheetDestination(host: \(webAppURL.host ?? "unknown"), apiToken: <redacted>)"
    }

    func testConnection() async throws -> SpreadsheetDestinationResult {
        try validateConfiguration()
        let request = try request(action: "health", payload: Optional<SpreadsheetExportPayload>.none)
        return try await execute(request)
    }

    func validate(_ payload: SpreadsheetExportPayload) async throws {
        try validateConfiguration()
        try SpreadsheetPayloadValidator.validate(payload)
    }

    func submit(_ payload: SpreadsheetExportPayload) async throws -> SpreadsheetDestinationResult {
        try await validate(payload)
        let request = try request(action: "upsertMonth", payload: payload)
        return try await execute(request)
    }

    private func validateConfiguration() throws {
        guard webAppURL.scheme == "https", !apiToken.isEmpty else {
            throw SpreadsheetDestinationError.invalidConfiguration
        }
    }

    private func request<Payload: Encodable>(action: String, payload: Payload?) throws -> URLRequest {
        var request = URLRequest(url: webAppURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(AppsScriptRequest(
            apiVersion: 2,
            action: action,
            token: apiToken,
            payload: payload
        ))
        return request
    }

    private func execute(_ request: URLRequest) async throws -> SpreadsheetDestinationResult {
        let response: SpreadsheetHTTPResponse
        do {
            response = try await transport.send(request)
        } catch let error as SpreadsheetDestinationError {
            throw error
        } catch {
            throw SpreadsheetDestinationError.transportFailure
        }
        guard 200..<300 ~= response.statusCode else {
            throw SpreadsheetDestinationError.httpFailure(response.statusCode)
        }
        guard let decoded = try? JSONDecoder().decode(AppsScriptResponse.self, from: response.body) else {
            throw SpreadsheetDestinationError.invalidResponse
        }
        guard decoded.ok else { throw SpreadsheetDestinationError.rejected }
        return .init(
            success: true,
            message: redact(decoded.message),
            acceptedRowCount: decoded.acceptedRowCount,
            skippedRowCount: decoded.skippedRowCount
        )
    }

    private func redact(_ message: String?) -> String? {
        guard let message, !apiToken.isEmpty else { return message }
        return message.replacingOccurrences(of: apiToken, with: "<redacted>")
    }
}

private struct AppsScriptRequest<Payload: Encodable>: Encodable {
    var apiVersion: Int
    var action: String
    var token: String
    var payload: Payload?
}

private struct AppsScriptResponse: Decodable {
    var ok: Bool
    var message: String?
    var acceptedRowCount: Int?
    var skippedRowCount: Int?
}

enum MockSpreadsheetDestinationBehavior: Sendable {
    case success
    case failure
}

actor MockSpreadsheetDestination: SpreadsheetDestination {
    private let behavior: MockSpreadsheetDestinationBehavior
    private var submittedPayloads: [SpreadsheetExportPayload] = []

    init(behavior: MockSpreadsheetDestinationBehavior = .success) {
        self.behavior = behavior
    }

    func testConnection() async throws -> SpreadsheetDestinationResult {
        try result()
    }

    func validate(_ payload: SpreadsheetExportPayload) async throws {
        try SpreadsheetPayloadValidator.validate(payload)
    }

    func submit(_ payload: SpreadsheetExportPayload) async throws -> SpreadsheetDestinationResult {
        try await validate(payload)
        switch behavior {
        case .failure:
            throw SpreadsheetDestinationError.transportFailure
        case .success:
            break
        }
        submittedPayloads.append(payload)
        return .init(
            success: true,
            message: "Mock accepted",
            acceptedRowCount: payload.incomes.count + payload.expenses.count,
            skippedRowCount: 0
        )
    }

    func receivedPayloads() -> [SpreadsheetExportPayload] {
        submittedPayloads
    }

    private func result() throws -> SpreadsheetDestinationResult {
        switch behavior {
        case .success:
            return .init(success: true, message: "Mock connected", acceptedRowCount: nil, skippedRowCount: nil)
        case .failure:
            throw SpreadsheetDestinationError.transportFailure
        }
    }
}
