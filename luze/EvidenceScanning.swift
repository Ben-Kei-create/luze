import Foundation

enum EvidenceFileType: String, Codable, CaseIterable, Hashable {
    case pdf
    case csv
    case any

    var displayName: String {
        switch self {
        case .pdf: "PDF"
        case .csv: "CSV"
        case .any: "すべて"
        }
    }

    func matches(_ url: URL) -> Bool {
        self == .any || url.pathExtension.localizedCaseInsensitiveCompare(rawValue) == .orderedSame
    }
}

enum EvidenceMatchStatus: String, Hashable {
    case found
    case multiple
    case missing

    var symbol: String {
        switch self {
        case .found: "✓"
        case .multiple: "△"
        case .missing: "!"
        }
    }
}

struct EvidenceFile: Identifiable, Hashable {
    var id: String { url.path }
    let url: URL
    let relativePath: String
    let isDirectory: Bool
}

struct EvidenceRuleResult: Identifiable, Hashable {
    var id: UUID { rule.id }
    let rule: ReceiptRule
    let matches: [EvidenceFile]

    var status: EvidenceMatchStatus {
        switch matches.count {
        case 0: .missing
        case 1: .found
        default: .multiple
        }
    }
}

struct EvidenceScanResult: Hashable {
    let periodKey: String
    let rootURL: URL
    let monthFolderURL: URL?
    let topLevelItems: [EvidenceFile]
    let files: [EvidenceFile]
    let ruleResults: [EvidenceRuleResult]

    var pdfCount: Int { files.filter { EvidenceFileType.pdf.matches($0.url) }.count }
    var csvCount: Int { files.filter { EvidenceFileType.csv.matches($0.url) }.count }
    var subfolderCount: Int { topLevelItems.filter(\.isDirectory).count }
    var hasMissingRequiredEvidence: Bool {
        monthFolderURL == nil || ruleResults.contains { $0.rule.isRequired && $0.status == .missing }
    }
}

enum EvidenceScannerError: LocalizedError, Equatable {
    case invalidPeriod
    case unreadableRoot

    var errorDescription: String? {
        switch self {
        case .invalidPeriod: "対象月の形式が正しくありません。"
        case .unreadableRoot: "証憑フォルダを読み取れません。設定から選び直してください。"
        }
    }
}

protocol EvidenceScanning {
    func scan(rootURL: URL, periodKey: String, rules: [ReceiptRule]) throws -> EvidenceScanResult
}

enum EvidenceFolderBookmarkError: LocalizedError {
    case missing

    var errorDescription: String? { "保存済みの証憑フォルダがありません。" }
}

struct EvidenceFolderBookmarkStore {
    static let defaultKey = "evidenceFolderSecurityScopedBookmark"

    let defaults: UserDefaults
    let key: String

    init(defaults: UserDefaults = .standard, key: String = Self.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    func save(_ url: URL) throws {
        let bookmark = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        defaults.set(bookmark, forKey: key)
    }

    func restore() throws -> URL {
        guard let bookmark = defaults.data(forKey: key) else {
            throw EvidenceFolderBookmarkError.missing
        }
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        if isStale { try save(url) }
        return url
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}

struct EvidenceScanner: EvidenceScanning {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func scan(rootURL: URL, periodKey: String, rules: [ReceiptRule]) throws -> EvidenceScanResult {
        guard periodKey.count == 6, periodKey.allSatisfy(\.isNumber) else {
            throw EvidenceScannerError.invalidPeriod
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw EvidenceScannerError.unreadableRoot
        }

        guard let monthFolderURL = resolveMonthFolder(in: rootURL, periodKey: periodKey) else {
            return EvidenceScanResult(
                periodKey: periodKey,
                rootURL: rootURL,
                monthFolderURL: nil,
                topLevelItems: [],
                files: [],
                ruleResults: rules.map { EvidenceRuleResult(rule: $0, matches: []) }
            )
        }

        let topLevelItems = try contents(of: monthFolderURL)
        let files = recursiveFiles(in: monthFolderURL)
        let ruleResults = rules.map { rule in
            let keyword = normalized(rule.filenameContains.trimmingCharacters(in: .whitespacesAndNewlines))
            let matches = files.filter { file in
                rule.fileType.matches(file.url)
                    && (keyword.isEmpty || normalized(file.relativePath).contains(keyword))
            }
            return EvidenceRuleResult(rule: rule, matches: matches)
        }

        return EvidenceScanResult(
            periodKey: periodKey,
            rootURL: rootURL,
            monthFolderURL: monthFolderURL,
            topLevelItems: topLevelItems,
            files: files,
            ruleResults: ruleResults
        )
    }

    private func resolveMonthFolder(in rootURL: URL, periodKey: String) -> URL? {
        let splitIndex = periodKey.index(periodKey.startIndex, offsetBy: 4)
        let hyphenated = "\(periodKey[..<splitIndex])-\(periodKey[splitIndex...])"
        for name in [periodKey, hyphenated] {
            let candidate = rootURL.appendingPathComponent(name, isDirectory: true)
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return candidate.standardizedFileURL
            }
        }
        return nil
    }

    private func contents(of folderURL: URL) throws -> [EvidenceFile] {
        try fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        .map { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            return EvidenceFile(
                url: url,
                relativePath: url.lastPathComponent,
                isDirectory: values?.isDirectory == true
            )
        }
        .sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }

    private func recursiveFiles(in monthFolderURL: URL) -> [EvidenceFile] {
        guard let enumerator = fileManager.enumerator(
            at: monthFolderURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return [] }

        var result: [EvidenceFile] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
            guard values?.isRegularFile == true else { continue }
            let rootComponents = monthFolderURL.standardizedFileURL.pathComponents
            let fileComponents = url.standardizedFileURL.pathComponents
            let relativePath = fileComponents.count > rootComponents.count
                ? fileComponents.dropFirst(rootComponents.count).joined(separator: "/")
                : url.lastPathComponent
            result.append(EvidenceFile(url: url, relativePath: relativePath, isDirectory: false))
        }
        return result.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }

    private func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "ja_JP"))
    }
}
