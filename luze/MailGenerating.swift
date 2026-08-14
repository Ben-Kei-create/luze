import Foundation

struct MailTemplateContext: Equatable, Sendable {
    var recipientName: String
    var recipientEmail: String
    var year: Int
    var month: Int
    var spreadsheetURL: String
    var evidenceShareURL: String
    var incomeTotal: Int
    var expenseTotal: Int
    var pendingCount: Int
}

struct MailGenerationSource: Equatable, Sendable {
    var subjectTemplate: String
    var bodyTemplate: String
    var context: MailTemplateContext
}

struct GeneratedMailContent: Equatable, Sendable {
    var subject: String
    var body: String
}

struct MailTemplateRenderer {
    func render(_ source: MailGenerationSource) -> GeneratedMailContent {
        .init(
            subject: replaceVariables(in: source.subjectTemplate, context: source.context),
            body: renderBody(source.bodyTemplate, context: source.context)
        )
    }

    private func renderBody(_ template: String, context: MailTemplateContext) -> String {
        var prepared = template.replacingOccurrences(of: "\r\n", with: "\n")

        if context.evidenceShareURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            prepared = removingOptionalSection(
                from: prepared,
                headings: ["■ 証憑フォルダ", "■ Dropbox"],
                placeholders: ["{evidence_share_url}", "{evidence_folder_url}", "{dropbox_url}"]
            )
        }
        if context.spreadsheetURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            prepared = removingOptionalSection(
                from: prepared,
                headings: ["■ Google Spreadsheet"],
                placeholders: ["{sheet_url}"]
            )
        }
        if context.recipientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            prepared = removingEmptyRecipientLine(from: prepared)
        }

        return replaceVariables(in: prepared, context: context)
            .trimmingCharacters(in: .newlines)
    }

    private func replaceVariables(in template: String, context: MailTemplateContext) -> String {
        let values = [
            "{recipient}": context.recipientName,
            "{year}": String(context.year),
            "{month}": String(context.month),
            "{sheet_url}": context.spreadsheetURL,
            "{evidence_share_url}": context.evidenceShareURL,
            "{evidence_folder_url}": context.evidenceShareURL,
            "{dropbox_url}": context.evidenceShareURL,
            "{income_total}": String(context.incomeTotal),
            "{expense_total}": String(context.expenseTotal),
            "{pending_count}": String(context.pendingCount)
        ]
        return values.reduce(template) { result, value in
            result.replacingOccurrences(of: value.key, with: value.value)
        }
    }

    private func removingOptionalSection(
        from template: String,
        headings: Set<String>,
        placeholders: Set<String>
    ) -> String {
        var lines = template.components(separatedBy: "\n")
        var index = 0

        while index < lines.count {
            guard headings.contains(lines[index].trimmingCharacters(in: .whitespaces)) else {
                index += 1
                continue
            }

            var placeholderIndex = index + 1
            while placeholderIndex < lines.count,
                  lines[placeholderIndex].trimmingCharacters(in: .whitespaces).isEmpty {
                placeholderIndex += 1
            }
            guard placeholderIndex < lines.count,
                  placeholders.contains(lines[placeholderIndex].trimmingCharacters(in: .whitespaces)) else {
                index += 1
                continue
            }

            var endIndex = placeholderIndex + 1
            while endIndex < lines.count,
                  lines[endIndex].trimmingCharacters(in: .whitespaces).isEmpty {
                endIndex += 1
            }
            lines.removeSubrange(index..<endIndex)
        }
        return lines.joined(separator: "\n")
    }

    private func removingEmptyRecipientLine(from template: String) -> String {
        let removable = Set(["{recipient}", "{recipient}様", "{recipient} 様"])
        return template.components(separatedBy: "\n")
            .filter { !removable.contains($0.trimmingCharacters(in: .whitespaces)) }
            .joined(separator: "\n")
    }
}

struct MailDraftState: Equatable {
    var subject = ""
    var body = ""
    private(set) var generatedSource: MailGenerationSource?
    private(set) var generatedSubject = ""
    private(set) var generatedBody = ""

    var isBodyEdited: Bool {
        generatedSource != nil && body != generatedBody
    }

    func isStale(comparedTo source: MailGenerationSource) -> Bool {
        generatedSource != nil && generatedSource != source
    }

    @discardableResult
    mutating func regenerate(
        from source: MailGenerationSource,
        renderer: MailTemplateRenderer = .init(),
        overwriteEditedBody: Bool = false
    ) -> Bool {
        guard overwriteEditedBody || !isBodyEdited else { return false }
        let content = renderer.render(source)
        subject = content.subject
        body = content.body
        generatedSubject = content.subject
        generatedBody = content.body
        generatedSource = source
        return true
    }
}

protocol ClipboardWriting {
    @discardableResult
    func write(_ value: String) -> Bool
}

struct MailClipboard {
    private let writer: any ClipboardWriting

    init(writer: any ClipboardWriting) {
        self.writer = writer
    }

    @discardableResult
    func copy(_ value: String) -> Bool {
        writer.write(value)
    }
}

struct GmailComposeURLBuilder {
    func build(recipient: String, subject: String, body: String) -> URL? {
        var components = URLComponents(string: "https://mail.google.com/mail/")
        components?.queryItems = [
            .init(name: "view", value: "cm"),
            .init(name: "to", value: recipient),
            .init(name: "su", value: subject),
            .init(name: "body", value: body)
        ]
        return components?.url
    }
}
