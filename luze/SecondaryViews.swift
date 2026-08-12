import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ReceiptsView: View {
    @EnvironmentObject var store: AppStore
    var folder: URL? { store.settings.rootFolder.isEmpty ? nil : URL(fileURLWithPath: store.settings.rootFolder).appendingPathComponent(store.monthKey) }
    var files: [URL] { guard let folder else { return [] }; return ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? []).sorted { $0.lastPathComponent < $1.lastPathComponent } }
    var body: some View { Page(title: "証憑") { DatePicker("対象月", selection: $store.month, displayedComponents: [.date]).frame(width: 260); if files.isEmpty { ContentUnavailableView("ファイルがありません", systemImage: "folder", description: Text("設定で経理ルートフォルダを選択してください。")) } else { List(files, id: \.self) { url in HStack { Image(systemName: url.hasDirectoryPath ? "folder.fill" : "doc.fill").foregroundStyle(url.hasDirectoryPath ? .blue : .secondary); Text(url.lastPathComponent); Spacer(); Button("開く") { NSWorkspace.shared.open(url) }.buttonStyle(.link) } }.frame(minHeight: 300) }; HStack { Button("フォルダを選択") { chooseFolder() }; if let folder { Button("Finderで開く") { NSWorkspace.shared.open(folder) } } } } }
    func chooseFolder() { let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; if panel.runModal() == .OK, let url = panel.url { store.settings.rootFolder = url.path } }
}

struct HistoryView: View {
    @EnvironmentObject var store: AppStore
    var body: some View { Page(title: "判断履歴") { DatePicker("対象月", selection: $store.month, displayedComponents: [.date]).frame(width: 260); if store.current.transactions.isEmpty { ContentUnavailableView("履歴がありません", systemImage: "clock") } else { Table(store.current.transactions) { TableColumn("日付") { Text($0.date.formatted(date: .numeric, time: .omitted)) }.width(110); TableColumn("加盟店", value: \.merchant); TableColumn("金額") { Text($0.amount, format: .currency(code: "JPY")) }.width(110); TableColumn("判断") { item in Picker("", selection: binding(item.id)) { ForEach(Decision.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.labelsHidden() }.width(110); TableColumn("用途", value: \.purpose) } } } }
    func binding(_ id: UUID) -> Binding<Decision> { Binding(get: { store.current.transactions.first(where: { $0.id == id })?.decision ?? .pending }, set: { value in let wasExported = store.current.transactions.first(where: { $0.id == id })?.exported == true; store.updateCurrent { if let i = $0.transactions.firstIndex(where: { $0.id == id }) { $0.transactions[i].decision = value } }; if wasExported { store.notice = "この取引はGoogle Spreadsheetへ登録済みです。Luzeは既存行を自動削除しないため、Spreadsheetも確認してください。" } }) }
}

struct MailView: View {
    @EnvironmentObject var store: AppStore
    @State private var subject = ""
    @State private var messageBody = ""
    @State private var loadedKey = ""
    var generatedSubject: String { render(store.settings.subjectTemplate) }
    var generatedBody: String { render(store.settings.bodyTemplate) }
    var body: some View { Page(title: "メール") { TextField("宛先", text: $store.settings.email); TextField("件名", text: $subject); TextEditor(text: $messageBody).font(.body).frame(minHeight: 280).padding(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator)); HStack { Button("本文をコピー") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(messageBody, forType: .string); store.notice = "本文をコピーしました。" }; Spacer(); Button("Gmailを開く") { openGmail() }.buttonStyle(.borderedProminent) } }.onAppear { reloadIfNeeded() }.onChange(of: store.monthKey) { _, _ in reloadIfNeeded(force: true) } }
    func reloadIfNeeded(force: Bool = false) { if force || loadedKey != store.monthKey { subject = generatedSubject; messageBody = generatedBody; loadedKey = store.monthKey } }
    func render(_ template: String) -> String { let parts = Calendar.current.dateComponents([.year, .month], from: store.month); let values = ["{recipient}": store.settings.recipient, "{year}": "\(parts.year ?? 0)", "{month}": "\(parts.month ?? 0)", "{sheet_url}": store.settings.sheetURL, "{dropbox_url}": store.settings.dropboxURL, "{income_total}": "\(store.current.incomeTotal)", "{expense_total}": "\(store.expenseTotal())"]; return values.reduce(template) { $0.replacingOccurrences(of: $1.key, with: $1.value) } }
    func openGmail() { var c = URLComponents(string: "https://mail.google.com/mail/")!; c.queryItems = [.init(name: "view", value: "cm"), .init(name: "to", value: store.settings.email), .init(name: "su", value: subject), .init(name: "body", value: messageBody)]; if let url = c.url { NSWorkspace.shared.open(url) } }
}

struct SettingsView: View {
    @EnvironmentObject var store: AppStore; @State private var token = ""; @State private var newKeyword = ""
    var body: some View { Page(title: "設定") { TabView { Form { Section("提出先") { TextField("宛名", text: $store.settings.recipient); TextField("メール", text: $store.settings.email) } }.padding().tabItem { Label("一般", systemImage: "person") }; Form { Section("Google Sheets") { TextField("Spreadsheet URL", text: $store.settings.sheetURL); TextField("Apps Script URL", text: $store.settings.scriptURL); SecureField("API Token", text: $token).onChange(of: token) { _, value in Keychain.token = value }; Button(store.isWorking ? "確認中…" : "接続テスト") { Task { await store.testConnection() } }.disabled(store.isWorking) } }.padding().tabItem { Label("Google Sheets", systemImage: "tablecells") }; Form { Section("経理フォルダ") { Text(store.settings.rootFolder.isEmpty ? "未選択" : store.settings.rootFolder).textSelection(.enabled); Button("変更") { chooseFolder() } } }.padding().tabItem { Label("Dropbox", systemImage: "folder") }; Form { Section("固定費・交通費") { TextField("家賃", value: $store.settings.rent, format: .number); TextField("片道交通費", value: $store.settings.oneWayFare, format: .number) }; Section("加盟店ルール") { ForEach($store.settings.rules) { $rule in HStack { TextField("キーワード", text: $rule.keyword); Picker("", selection: $rule.action) { ForEach(MerchantRule.Action.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.frame(width: 130); Button(role: .destructive) { store.settings.rules.removeAll { $0.id == rule.id } } label: { Image(systemName: "trash") } } }; Button("ルールを追加") { store.settings.rules.append(.init(keyword: "新しい加盟店", action: .review)) } } }.padding().tabItem { Label("経理ルール", systemImage: "list.bullet.rectangle") }; Form { TextField("件名テンプレート", text: $store.settings.subjectTemplate); TextEditor(text: $store.settings.bodyTemplate).frame(minHeight: 220); Text("利用可能: {recipient} {year} {month} {sheet_url} {dropbox_url} {income_total} {expense_total}").font(.caption).foregroundStyle(.secondary) }.padding().tabItem { Label("メール", systemImage: "envelope") } }.onAppear { token = Keychain.token } } }
    func chooseFolder() { let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; if panel.runModal() == .OK, let url = panel.url { store.settings.rootFolder = url.path } }
}

struct HelpView: View { var body: some View { Page(title: "ヘルプ") { Text("Luzeは月次経理の準備を5ステップで進めるMacアプリです。").font(.title3); GroupBox("使い方") { VStack(alignment: .leading, spacing: 12) { Text("1. 設定で経理フォルダ、Google Sheets、提出先を登録します。"); Text("2. 今月の処理で収入と出社日数を入力します。"); Text("3. 証憑とVpass CSVを確認し、取引を分類します。"); Text("4. 内容を確認してGoogle Sheetsへ反映します。"); Text("5. メール本文をコピーし、Gmailで送信します。") }.padding() }; Text("Luze自身がメールを送信することはありません。").foregroundStyle(.secondary) } } }
