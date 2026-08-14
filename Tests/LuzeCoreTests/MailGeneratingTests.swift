import Foundation
import Testing
@testable import LuzeCore

struct MailGeneratingTests {
    @Test("Spreadsheet URLを本文へ置換する")
    func spreadsheetURLReplacement() {
        let content = render(body: "Sheet: {sheet_url}")
        #expect(content.body == "Sheet: https://docs.google.com/test-sheet")
    }

    @Test("証憑共有URLを本文へ置換する")
    func evidenceShareURLReplacement() {
        let content = render(body: "証憑: {evidence_share_url}")
        #expect(content.body == "証憑: https://example.com/evidence")
    }

    @Test("宛名を本文へ置換する")
    func recipientReplacement() {
        let content = render(body: "{recipient} 様")
        #expect(content.body == "経理担当 様")
    }

    @Test("金額と保留件数を本文へ置換する")
    func amountAndPendingReplacement() {
        let content = render(body: "収入 {income_total} / 支出 {expense_total} / 保留 {pending_count}")
        #expect(content.body == "収入 470028 / 支出 108069 / 保留 3")
    }

    @Test("証憑共有URL未設定時はセクションごと削除する")
    func removesEmptyEvidenceSection() {
        var context = context()
        context.evidenceShareURL = ""
        let content = render(body: SettingsData.defaultBodyTemplate, context: context)

        #expect(!content.body.contains("■ 証憑フォルダ"))
        #expect(!content.body.contains("{evidence_share_url}"))
        #expect(content.body.contains("■ Google Spreadsheet"))
    }

    @Test("両URL未設定時は両方の空セクションを削除する")
    func removesBothEmptyURLSections() {
        var context = context()
        context.evidenceShareURL = ""
        context.spreadsheetURL = ""
        let content = render(body: SettingsData.defaultBodyTemplate, context: context)

        #expect(!content.body.contains("■ 証憑フォルダ"))
        #expect(!content.body.contains("■ Google Spreadsheet"))
        #expect(content.body.contains("収入合計：470028円"))
    }

    @Test("旧dropbox_urlを証憑共有URLのaliasとして置換する")
    func legacyDropboxAlias() {
        let content = render(body: "■ Dropbox\n{dropbox_url}")
        #expect(content.body == "■ Dropbox\nhttps://example.com/evidence")
    }

    @Test("既知の旧Dropbox標準テンプレートだけを新標準へ移行する")
    func migratesLegacyDefaultTemplate() throws {
        let legacy = """
        {recipient} 様

        お世話になっております。
        {year}年{month}月分の資料を共有いたします。

        ■ Dropbox
        {dropbox_url}

        ■ Google Spreadsheet
        {sheet_url}

        収入：{income_total}円
        支出：{expense_total}円
        """
        let data = try JSONSerialization.data(withJSONObject: ["bodyTemplate": legacy])
        let settings = try JSONDecoder().decode(SettingsData.self, from: data)

        #expect(settings.bodyTemplate == SettingsData.defaultBodyTemplate)
        #expect(settings.bodyTemplate.contains("{evidence_share_url}"))
    }

    @Test("ユーザー独自テンプレートを移行時に上書きしない")
    func preservesCustomTemplate() throws {
        let custom = "独自の文章\n■ Dropbox\n{dropbox_url}\n備考を残す"
        let data = try JSONSerialization.data(withJSONObject: ["bodyTemplate": custom])
        let settings = try JSONDecoder().decode(SettingsData.self, from: data)

        #expect(settings.bodyTemplate == custom)
    }

    @Test("設定変更で生成済み本文をstaleとして判定する")
    func settingsChangeMakesDraftStale() {
        var draft = MailDraftState()
        let original = source()
        draft.regenerate(from: original)
        var changed = original
        changed.context.spreadsheetURL = "https://docs.google.com/updated"

        #expect(draft.isStale(comparedTo: changed))
        #expect(draft.body.contains("https://docs.google.com/test-sheet"))
    }

    @Test("再生成で最新設定を本文へ反映する")
    func regenerationUsesLatestSettings() {
        var draft = MailDraftState()
        let original = source()
        draft.regenerate(from: original)
        var changed = original
        changed.context.evidenceShareURL = "https://example.com/latest"

        let regenerated = draft.regenerate(from: changed)
        #expect(regenerated)
        #expect(draft.body.contains("https://example.com/latest"))
        #expect(!draft.isStale(comparedTo: changed))
    }

    @Test("本文手編集後は明示許可なしの再生成を拒否する")
    func protectsManuallyEditedBody() {
        var draft = MailDraftState()
        let original = source()
        draft.regenerate(from: original)
        draft.body += "\n手入力の追記"
        var changed = original
        changed.context.incomeTotal = 999

        let protected = draft.regenerate(from: changed)
        #expect(!protected)
        #expect(draft.body.contains("手入力の追記"))
        let overwritten = draft.regenerate(from: changed, overwriteEditedBody: true)
        #expect(overwritten)
        #expect(!draft.body.contains("手入力の追記"))
        #expect(draft.body.contains("999"))
    }

    @Test("Clipboardへ指定文字列を渡す")
    func clipboard() {
        let writer = RecordingClipboard()
        let result = MailClipboard(writer: writer).copy("本文です")

        #expect(result)
        #expect(writer.value == "本文です")
    }

    @Test("Gmailは送信APIではなくブラウザ作成画面URLだけを生成する")
    func gmailComposeURL() throws {
        let url = try #require(GmailComposeURLBuilder().build(
            recipient: "accounting@example.com",
            subject: "2026年7月分",
            body: "確認用本文"
        ))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        #expect(components.scheme == "https")
        #expect(components.host == "mail.google.com")
        #expect(items["view"] == "cm")
        #expect(items["to"] == "accounting@example.com")
        #expect(items["su"] == "2026年7月分")
        #expect(items["body"] == "確認用本文")
    }

    @Test("宛名未設定時は空の敬称行を作らない")
    func missingRecipientDoesNotCreateEmptySalutation() {
        var context = context()
        context.recipientName = ""
        let content = render(body: SettingsData.defaultBodyTemplate, context: context)

        #expect(!content.body.contains(" 様"))
        #expect(content.body.hasPrefix("お世話になっております。"))
    }

    @Test("未知のテンプレート変数は壊さず保持する")
    func unknownTemplateVariableIsSafe() {
        let content = render(body: "既知 {year} / 未知 {future_variable}")
        #expect(content.body == "既知 2026 / 未知 {future_variable}")
    }

    @Test("旧dropboxURL設定を新しい証憑共有URLへ移行して再保存する")
    func migratesLegacyEvidenceURLKey() throws {
        let data = Data(#"{"dropboxURL":"https://dropbox.example/legacy"}"#.utf8)
        let settings = try JSONDecoder().decode(SettingsData.self, from: data)
        let encoded = try JSONEncoder().encode(settings)
        let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        #expect(settings.evidenceShareURL == "https://dropbox.example/legacy")
        #expect(json["evidenceShareURL"] as? String == "https://dropbox.example/legacy")
        #expect(json["dropboxURL"] == nil)
    }

    private func render(
        subject: String = "{year}年{month}月分",
        body: String,
        context: MailTemplateContext? = nil
    ) -> GeneratedMailContent {
        MailTemplateRenderer().render(.init(
            subjectTemplate: subject,
            bodyTemplate: body,
            context: context ?? self.context()
        ))
    }

    private func source() -> MailGenerationSource {
        .init(
            subjectTemplate: "{year}年{month}月分 経理資料の共有",
            bodyTemplate: SettingsData.defaultBodyTemplate,
            context: context()
        )
    }

    private func context() -> MailTemplateContext {
        .init(
            recipientName: "経理担当",
            recipientEmail: "accounting@example.com",
            year: 2026,
            month: 7,
            spreadsheetURL: "https://docs.google.com/test-sheet",
            evidenceShareURL: "https://example.com/evidence",
            incomeTotal: 470_028,
            expenseTotal: 108_069,
            pendingCount: 3
        )
    }
}

private final class RecordingClipboard: ClipboardWriting {
    var value: String?

    func write(_ value: String) -> Bool {
        self.value = value
        return true
    }
}
