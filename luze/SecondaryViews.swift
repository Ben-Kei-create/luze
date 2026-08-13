import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ReceiptsView: View {
    @EnvironmentObject var store: AppStore
    var scan: EvidenceScanResult? { store.evidenceScanResult }

    var body: some View {
        Page(title: "証憑") {
            MonthSelector(month: $store.month)
            if store.evidenceFolderURL == nil {
                ContentUnavailableView(
                    "証憑フォルダが未選択です",
                    systemImage: "folder.badge.questionmark",
                    description: Text("Dropbox、iCloud Drive、Google Drive、OneDrive、またはローカルフォルダを選択できます。")
                )
            } else if scan?.monthFolderURL == nil {
                ContentUnavailableView(
                    "対象月フォルダがありません",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("証憑フォルダ直下に \(store.monthKey) または yyyy-MM 形式のフォルダを用意してください。")
                )
            } else if scan?.topLevelItems.isEmpty != false {
                ContentUnavailableView("ファイルがありません", systemImage: "folder")
            } else {
                List(scan?.topLevelItems ?? []) { item in
                    HStack {
                        Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                            .foregroundStyle(item.isDirectory ? .blue : .secondary)
                        Text(item.relativePath)
                        Spacer()
                        Button("開く") { store.openEvidenceURL(item.url) }.buttonStyle(.link)
                    }
                }
                .frame(minHeight: 300)
            }
            HStack {
                Button(store.evidenceFolderURL == nil ? "証憑フォルダを選択" : "証憑フォルダを変更") { chooseFolder() }
                if let folder = scan?.monthFolderURL ?? store.evidenceFolderURL {
                    Button("Finderで開く") { store.openEvidenceURL(folder) }
                }
            }
        }
        .onAppear { store.refreshEvidenceScan() }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.folder]
        panel.allowsMultipleSelection = false
        panel.directoryURL = store.evidenceFolderURL
            ?? FileManager.default.homeDirectoryForCurrentUser
        panel.prompt = "証憑フォルダを選択"
        if panel.runModal() == .OK, let url = panel.url {
            do { try store.selectEvidenceFolder(url) }
            catch { store.notice = "証憑フォルダの権限を保存できませんでした。\n\(error.localizedDescription)" }
        }
    }
}

struct HistoryView: View {
    @EnvironmentObject var store: AppStore
    var body: some View { Page(title: "判断履歴") { MonthSelector(month: $store.month); if store.current.transactions.isEmpty { ContentUnavailableView("履歴がありません", systemImage: "clock") } else { Table(store.current.transactions) { TableColumn("日付") { Text($0.date.formatted(date: .numeric, time: .omitted)) }.width(110); TableColumn("加盟店", value: \.merchant); TableColumn("金額") { Text($0.amount, format: .currency(code: "JPY")) }.width(110); TableColumn("判断") { item in Picker("", selection: binding(item.id)) { ForEach(Decision.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.labelsHidden() }.width(110); TableColumn("用途", value: \.purpose) } } } }
    func binding(_ id: UUID) -> Binding<Decision> { Binding(get: { store.current.transactions.first(where: { $0.id == id })?.decision ?? .pending }, set: { value in let wasExported = store.current.transactions.first(where: { $0.id == id })?.exported == true; store.setDecision(transactionID: id, decision: value); if wasExported { store.notice = "この取引はSpreadsheetへ同期済みです。変更は次回の月次同期で反映されます。" } }) }
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
    func render(_ template: String) -> String { let parts = Calendar.current.dateComponents([.year, .month], from: store.month); let values = ["{recipient}": store.settings.recipient, "{year}": "\(parts.year ?? 0)", "{month}": "\(parts.month ?? 0)", "{sheet_url}": store.settings.sheetURL, "{evidence_folder_url}": store.settings.evidenceFolderShareURL, "{dropbox_url}": store.settings.evidenceFolderShareURL, "{income_total}": "\(store.incomeTotal())", "{expense_total}": "\(store.expenseTotal())"]; return values.reduce(template) { $0.replacingOccurrences(of: $1.key, with: $1.value) } }
    func openGmail() { var c = URLComponents(string: "https://mail.google.com/mail/")!; c.queryItems = [.init(name: "view", value: "cm"), .init(name: "to", value: store.settings.email), .init(name: "su", value: subject), .init(name: "body", value: messageBody)]; if let url = c.url { NSWorkspace.shared.open(url) } }
}

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var token = ""

    var body: some View {
        Page(title: "設定") {
            TabView {
                Form {
                    Section("提出先") {
                        TextField("宛名", text: $store.settings.recipient)
                        TextField("メール", text: $store.settings.email)
                    }
                }
                .padding()
                .tabItem { Label("一般", systemImage: "person") }

                Form {
                    Section("Google Sheets") {
                        LabeledContent("接続先", value: store.settings.spreadsheetEnvironment.displayName)
                        TextField("Spreadsheet URL", text: $store.settings.sheetURL)
                        TextField("Apps Script Web App URL", text: $store.settings.scriptURL)
                        SecureField("API Token", text: $token)
                            .onChange(of: token) { _, value in Keychain.token = value }
                        Button(store.isWorking ? "確認中…" : "接続テスト") {
                            Task { await store.testConnection() }
                        }
                        .disabled(store.isWorking)
                        Text("接続テストはhealth確認だけを行い、データを変更しません。Milestone 4Bではテスト専用Sheetだけに同期できます。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .tabItem { Label("Google Sheets", systemImage: "tablecells") }

                Form {
                    Section("証憑フォルダ") {
                        Text(store.evidenceFolderURL?.path ?? "未選択")
                            .textSelection(.enabled)
                        Button(store.evidenceFolderURL == nil ? "選択" : "変更") { chooseFolder() }
                        Text("Dropbox、iCloud Drive、Google Drive、OneDrive、またはローカルフォルダを選択できます。権限はこのMacに保存されます。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Section("必要な証憑") {
                        if store.settings.receiptRules.isEmpty {
                            Text("ルールは未設定です。必要なPDFまたはCSVを追加してください。")
                                .foregroundStyle(.secondary)
                        }
                        ForEach($store.settings.receiptRules) { $rule in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    TextField("名称", text: $rule.name)
                                    Picker("種類", selection: $rule.fileType) {
                                        ForEach(EvidenceFileType.allCases, id: \.self) { type in
                                            Text(type.displayName).tag(type)
                                        }
                                    }
                                    .frame(width: 150)
                                    Toggle("必須", isOn: $rule.isRequired)
                                        .toggleStyle(.checkbox)
                                    Button(role: .destructive) {
                                        store.settings.receiptRules.removeAll { $0.id == rule.id }
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                }
                                TextField("ファイル名に含む文字（空欄なら種類だけで判定）", text: $rule.filenameContains)
                            }
                            .padding(.vertical, 4)
                        }
                        Button("証憑ルールを追加") {
                            store.settings.receiptRules.append(
                                .init(name: "新しい証憑", filenameContains: "", fileType: .pdf)
                            )
                        }
                    }
                }
                .padding()
                .tabItem { Label("証憑フォルダ", systemImage: "folder") }

                Form {
                    Section("固定費・交通費") {
                        TextField("家賃", value: $store.settings.rent, format: .number)
                        TextField("片道交通費", value: $store.settings.oneWayFare, format: .number)
                    }
                    Section("加盟店ルール") {
                        ForEach($store.settings.rules) { $rule in
                            HStack {
                                TextField("キーワード", text: $rule.keyword).disabled(rule.isProtected)
                                Picker("", selection: $rule.action) {
                                    ForEach(MerchantRule.Action.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                                }
                                .frame(width: 130)
                                .disabled(rule.isProtected)
                                if rule.isProtected { Image(systemName: "lock.fill").foregroundStyle(.secondary) }
                                Button(role: .destructive) {
                                    store.settings.rules.removeAll { $0.id == rule.id }
                                } label: { Image(systemName: "trash") }
                                .disabled(rule.isProtected)
                            }
                        }
                        Button("ルールを追加") {
                            store.settings.rules.append(.init(keyword: "新しい加盟店", action: .review))
                        }
                    }
                    Section("恒久自動除外") {
                        if store.settings.permanentMerchantExclusions.isEmpty {
                            Text("登録なし").foregroundStyle(.secondary)
                        }
                        ForEach(store.settings.permanentMerchantExclusions) { memory in
                            HStack {
                                Text(memory.originalMerchantName)
                                Spacer()
                                Button("解除") { store.forgetPermanentExclusion(id: memory.id) }
                            }
                        }
                    }
                }
                .padding()
                .tabItem { Label("経理ルール", systemImage: "list.bullet.rectangle") }

                Form {
                    TextField("件名テンプレート", text: $store.settings.subjectTemplate)
                    TextEditor(text: $store.settings.bodyTemplate).frame(minHeight: 220)
                    Text("利用可能: {recipient} {year} {month} {sheet_url} {evidence_folder_url} {income_total} {expense_total}")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .tabItem { Label("メール", systemImage: "envelope") }
            }
            .onAppear { token = Keychain.token }
        }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.folder]
        panel.allowsMultipleSelection = false
        panel.directoryURL = store.evidenceFolderURL
            ?? FileManager.default.homeDirectoryForCurrentUser
        panel.prompt = "証憑フォルダを選択"
        if panel.runModal() == .OK, let url = panel.url {
            do { try store.selectEvidenceFolder(url) }
            catch { store.notice = "証憑フォルダの権限を保存できませんでした。\n\(error.localizedDescription)" }
        }
    }
}

struct HelpView: View {
    var body: some View {
        Page(title: "ヘルプ") {
            Text("Luzeは月次経理の準備を5ステップで進めるMacアプリです。").font(.title3)
            GroupBox("使い方") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("1. 設定でテストSpreadsheet、証憑フォルダ、提出先を登録します。")
                    Text("2. 今月の処理で収入と出社日数を入力します。")
                    Text("3. 証憑とVpass CSVを確認し、取引を分類します。")
                    Text("4. Spreadsheetへ送る内容を確認し、明示的に同期します。")
                    Text("5. メール本文をコピーし、Gmailで送信します。")
                }
                .padding()
            }
            Text("証憑フォルダは読み取り専用です。Luzeがファイルを移動・改名・削除することはありません。")
                .foregroundStyle(.secondary)
        }
    }
}
