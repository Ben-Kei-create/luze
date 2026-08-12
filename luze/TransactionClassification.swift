import Foundation

struct ClassificationResult: Equatable {
    var decision: Decision
    var purpose: String
    var source: ClassificationSource
}

struct ClassificationSummary: Equatable {
    var total: Int
    var automaticExpenses: Int
    var automaticExclusions: Int
    var reviews: Int
}

enum MerchantProtection {
    static func isProtected(_ merchant: String) -> Bool {
        let normalized = MerchantNormalizer().normalize(merchant)
        return normalized.contains("AMAZON")
            || (normalized.contains("APPLE") && (normalized.contains("BILL") || normalized.contains("COM")))
    }
}

enum TransactionFingerprint {
    static func make(date: Date, normalizedMerchantName: String, amount: Int, calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let day = String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
        return "\(day)|\(normalizedMerchantName)|\(amount)"
    }
}

protocol TransactionClassifying {
    func classify(
        transaction: ImportedStatementTransaction,
        rules: [MerchantRule],
        history: [DecisionRecord],
        permanentExclusions: [PermanentMerchantExclusion],
        hasFingerprintCollision: Bool
    ) -> ClassificationResult
}

struct TransactionClassifier: TransactionClassifying {
    func classify(
        transaction: ImportedStatementTransaction,
        rules: [MerchantRule],
        history: [DecisionRecord],
        permanentExclusions: [PermanentMerchantExclusion],
        hasFingerprintCollision: Bool = false
    ) -> ClassificationResult {
        let fingerprint = TransactionFingerprint.make(
            date: transaction.transactionDate,
            normalizedMerchantName: transaction.normalizedMerchantName,
            amount: transaction.amount
        )
        let historyMatches = history.filter { $0.transactionFingerprint == fingerprint }
        if !hasFingerprintCollision, historyMatches.count == 1, let record = historyMatches.first {
            return .init(decision: record.decision, purpose: record.purpose, source: .decisionHistory)
        }
        if historyMatches.count > 1 {
            return .init(decision: .pending, purpose: "", source: .review)
        }

        if MerchantProtection.isProtected(transaction.normalizedMerchantName) {
            return .init(decision: .pending, purpose: "", source: .review)
        }

        if permanentExclusions.contains(where: { $0.normalizedMerchantName == transaction.normalizedMerchantName }) {
            return .init(decision: .excluded, purpose: "", source: .permanentExclusion)
        }

        for rule in rules where matches(rule: rule, merchant: transaction.normalizedMerchantName) {
            if rule.isProtected {
                return .init(decision: .pending, purpose: "", source: .review)
            }
            switch rule.action {
            case .expense:
                return .init(decision: .expense, purpose: rule.purpose, source: .automaticExpense)
            case .excluded:
                return .init(decision: .excluded, purpose: "", source: .automaticExclusion)
            case .review:
                return .init(decision: .pending, purpose: "", source: .review)
            }
        }
        return .init(decision: .pending, purpose: "", source: .review)
    }

    private func matches(rule: MerchantRule, merchant: String) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: rule.keyword, options: [.caseInsensitive]) else {
            return merchant.localizedCaseInsensitiveContains(rule.keyword)
        }
        return expression.firstMatch(in: merchant, range: NSRange(merchant.startIndex..., in: merchant)) != nil
    }
}

enum DecisionHistory {
    static func upsert(
        transaction: Transaction,
        period: String,
        records: inout [DecisionRecord],
        now: Date = Date()
    ) {
        let normalized = MerchantNormalizer().normalize(transaction.merchant)
        let fingerprint = TransactionFingerprint.make(date: transaction.date, normalizedMerchantName: normalized, amount: transaction.amount)
        if let index = records.firstIndex(where: { $0.period == period && $0.transactionFingerprint == fingerprint }) {
            records[index].decision = transaction.decision
            records[index].purpose = transaction.purpose
            records[index].updatedAt = now
        } else {
            records.append(.init(
                transactionFingerprint: fingerprint,
                period: period,
                date: transaction.date,
                merchant: transaction.merchant,
                amount: transaction.amount,
                decision: transaction.decision,
                purpose: transaction.purpose,
                createdAt: now,
                updatedAt: now
            ))
        }
    }
}

enum PermanentExclusionError: LocalizedError {
    case protectedMerchant

    var errorDescription: String? {
        switch self {
        case .protectedMerchant: "この加盟店は安全保護されているため、恒久自動除外にはできません。"
        }
    }
}

enum PermanentExclusionMemory {
    static func remember(merchant: String, in exclusions: inout [PermanentMerchantExclusion]) throws {
        guard !MerchantProtection.isProtected(merchant) else { throw PermanentExclusionError.protectedMerchant }
        let normalized = MerchantNormalizer().normalize(merchant)
        guard !exclusions.contains(where: { $0.normalizedMerchantName == normalized }) else { return }
        exclusions.append(.init(normalizedMerchantName: normalized, originalMerchantName: merchant))
    }

    static func forget(id: UUID, in exclusions: inout [PermanentMerchantExclusion]) {
        exclusions.removeAll { $0.id == id }
    }
}
