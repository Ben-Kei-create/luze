import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        NavigationSplitView {
            List(selection: $store.selection) {
                Section { ForEach(SidebarItem.allCases.filter { $0 != .help }) { item in Label(item.rawValue, systemImage: item.icon).tag(item) } }
                Section { Label(SidebarItem.help.rawValue, systemImage: SidebarItem.help.icon).tag(SidebarItem.help) }
            }.navigationTitle("Luze")
        } detail: {
            Group {
                switch store.selection {
                case .monthly: MonthlyFlowView()
                case .receipts: ReceiptsView()
                case .history: HistoryView()
                case .mail: MailView()
                case .settings: SettingsView()
                case .help: HelpView()
                }
            }.frame(minWidth: 680, minHeight: 560)
        }
        .alert("Luze", isPresented: Binding(get: { !store.notice.isEmpty }, set: { if !$0 { store.notice = "" } })) { Button("OK") { store.notice = "" } } message: { Text(store.notice) }
    }
}

struct Page<Content: View>: View {
    let title: String; @ViewBuilder var content: Content
    var body: some View { VStack(alignment: .leading, spacing: 22) { Text(title).font(.largeTitle.bold()); content; Spacer() }.padding(32) }
}

struct MonthlyFlowView: View {
    @EnvironmentObject var store: AppStore
    var body: some View { Group { if store.step == 0 { MonthOverview() } else if store.step == 1 { InputStep() } else if store.step == 2 { ReceiptStep() } else if store.step == 3 { VpassStep() } else { SummaryStep() } } }
}

struct MonthOverview: View {
    @EnvironmentObject var store: AppStore
    let steps = [("入力", "基本情報を入力します"), ("証憑チェック", "証憑の存在を確認します"), ("Vpass確認", "取引の内容を判断します"), ("集計", "経費を集計・確認します"), ("メール", "経理資料を共有します")]
    var body: some View { Page(title: "\(AppStore.displayMonth.string(from: store.month))の処理") { Text("5ステップで完了します").foregroundStyle(.secondary); DatePicker("対象月", selection: $store.month, displayedComponents: [.date]).datePickerStyle(.compact).frame(width: 240); VStack(spacing: 0) { ForEach(steps.indices, id: \.self) { i in Button { if i == 4 { store.selection = .mail } else { store.step = i + 1 } } label: { HStack(spacing: 16) { ZStack { Circle().fill(store.current.completedSteps.contains(i + 1) ? Color.green : Color.accentColor.opacity(0.12)).frame(width: 36, height: 36); Text(store.current.completedSteps.contains(i + 1) ? "✓" : "\(i + 1)").foregroundStyle(store.current.completedSteps.contains(i + 1) ? Color.white : Color.accentColor) }; VStack(alignment: .leading) { Text(steps[i].0).font(.headline); Text(steps[i].1).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary) }.padding(16).contentShape(Rectangle()) }.buttonStyle(.plain); if i < 4 { Divider().padding(.leading, 68) } } }.background(.background).clipShape(RoundedRectangle(cornerRadius: 12)).shadow(color: .black.opacity(0.06), radius: 8) } }
}

struct InputStep: View {
    @EnvironmentObject var store: AppStore
    var body: some View { Page(title: "1. 入力") { DatePicker("対象月", selection: $store.month, displayedComponents: [.date]).frame(width: 260); Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 16) { moneyRow("TechBiz", key: \.techBiz); moneyRow("HelloLinks", key: \.helloLinks); moneyRow("Kindle", key: \.kindle); GridRow { Text("出社日数"); TextField("0", value: Binding(get: { store.current.officeDays }, set: { v in store.updateCurrent { $0.officeDays = v } }), format: .number).frame(width: 180); Text("日").foregroundStyle(.secondary) } }; HStack { Button("戻る") { store.step = 0 }; Spacer(); Button("次へ") { store.complete(1) }.buttonStyle(.borderedProminent) } } }
    @ViewBuilder func moneyRow(_ title: String, key: WritableKeyPath<MonthlyData, Int>) -> some View { GridRow { Text(title).frame(width: 130, alignment: .leading); TextField("0", value: Binding(get: { store.current[keyPath: key] }, set: { v in store.updateCurrent { $0[keyPath: key] = v } }), format: .number).frame(width: 180); Text("円").foregroundStyle(.secondary) } }
}

struct ReceiptStep: View {
    @EnvironmentObject var store: AppStore
    var monthFolder: URL? { guard !store.settings.rootFolder.isEmpty else { return nil }; return URL(fileURLWithPath: store.settings.rootFolder).appendingPathComponent(store.monthKey) }
    var files: [URL] { guard let folder = monthFolder else { return [] }; return (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] }
    var body: some View { Page(title: "2. 証憑チェック") { StatusRow(title: "Dropbox月フォルダ", ok: monthFolder.map { FileManager.default.fileExists(atPath: $0.path) } ?? false, detail: monthFolder?.lastPathComponent ?? "未設定"); StatusRow(title: "PDF", ok: files.contains { $0.pathExtension.lowercased() == "pdf" }, detail: "\(files.filter { $0.pathExtension.lowercased() == "pdf" }.count)ファイル"); StatusRow(title: "Vpass CSV", ok: !store.current.transactions.isEmpty, detail: store.current.transactions.isEmpty ? "未読込" : "読込済み"); Button("Dropboxフォルダを開く") { if let monthFolder { NSWorkspace.shared.open(monthFolder) } }.disabled(monthFolder == nil); HStack { Button("戻る") { store.step = 1 }; Spacer(); Button(files.isEmpty ? "不足したまま続ける" : "次へ") { store.complete(2) }.buttonStyle(.borderedProminent) } } }
}

struct StatusRow: View { let title: String, ok: Bool, detail: String; var body: some View { HStack { Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill").foregroundStyle(ok ? .green : .orange).font(.title2); VStack(alignment: .leading) { Text(title).font(.headline); Text(detail).foregroundStyle(.secondary) }; Spacer() }.padding().background(.quaternary.opacity(0.35)).clipShape(RoundedRectangle(cornerRadius: 10)) } }

struct VpassStep: View {
    @EnvironmentObject var store: AppStore; @State private var index = 0
    var body: some View { Page(title: "3. Vpass確認") { if store.current.transactions.isEmpty { ContentUnavailableView("CSVを読み込んでください", systemImage: "tablecells", description: Text("VpassのCSVファイルを選択します。")); Button("CSVを選択") { chooseCSV() }.buttonStyle(.borderedProminent) } else { let item = store.current.transactions[min(index, store.current.transactions.count - 1)]; Text("\(index + 1) / \(store.current.transactions.count)").foregroundStyle(.secondary); VStack(spacing: 14) { Text(item.merchant).font(.title.bold()); Text(item.date.formatted(date: .long, time: .omitted)); Text(item.amount, format: .currency(code: "JPY")).font(.system(size: 36, weight: .semibold)); Picker("判断", selection: decisionBinding(item.id)) { ForEach(Decision.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).frame(maxWidth: 420); if item.decision == .expense { TextField("用途（例：書籍・資料）", text: purposeBinding(item.id)).frame(maxWidth: 420) } }.frame(maxWidth: .infinity).padding(28).background(.quaternary.opacity(0.3)).clipShape(RoundedRectangle(cornerRadius: 16)); HStack { Button("戻る") { if index > 0 { index -= 1 } else { store.step = 2 } }; Button("別のCSVを読み込む") { chooseCSV() }; Spacer(); Button(index + 1 < store.current.transactions.count ? "次の取引" : "集計へ") { if index + 1 < store.current.transactions.count { index += 1 } else { store.complete(3) } }.buttonStyle(.borderedProminent) } } } }
    func decisionBinding(_ id: UUID) -> Binding<Decision> { Binding(get: { store.current.transactions.first(where: { $0.id == id })?.decision ?? .pending }, set: { value in store.updateCurrent { if let i = $0.transactions.firstIndex(where: { $0.id == id }) { $0.transactions[i].decision = value } } }) }
    func purposeBinding(_ id: UUID) -> Binding<String> { Binding(get: { store.current.transactions.first(where: { $0.id == id })?.purpose ?? "" }, set: { value in store.updateCurrent { if let i = $0.transactions.firstIndex(where: { $0.id == id }) { $0.transactions[i].purpose = value } } }) }
    func chooseCSV() { let panel = NSOpenPanel(); panel.allowedContentTypes = [.commaSeparatedText, .plainText]; panel.allowsMultipleSelection = false; if panel.runModal() == .OK, let url = panel.url { do { try store.importCSV(url: url) } catch { store.notice = error.localizedDescription } } }
}

struct SummaryStep: View {
    @EnvironmentObject var store: AppStore
    var body: some View { let d = store.current; Page(title: "4. 集計") { HStack(spacing: 40) { Metric(title: "収入", value: d.incomeTotal); Metric(title: "支出", value: store.expenseTotal()) }; HStack { CountChip(title: "経費", count: d.transactions.filter { $0.decision == .expense }.count, color: .green); CountChip(title: "除外", count: d.transactions.filter { $0.decision == .excluded }.count, color: .gray); CountChip(title: "保留", count: d.transactions.filter { $0.decision == .pending }.count, color: .orange) }; StatusRow(title: "Google Sheets", ok: d.sheetExported, detail: d.sheetExported ? "反映済み" : "未反映"); Button(store.isWorking ? "反映中…" : "内容を確認してGoogle Sheetsへ反映") { Task { await store.exportToSheet() } }.disabled(store.isWorking); HStack { Button("戻る") { store.step = 3 }; Spacer(); Button("メールへ") { store.complete(4); store.selection = .mail }.buttonStyle(.borderedProminent) } } }
}
struct Metric: View { let title: String, value: Int; var body: some View { VStack(alignment: .leading) { Text(title).foregroundStyle(.secondary); Text(value, format: .currency(code: "JPY")).font(.largeTitle.bold()) }.frame(maxWidth: .infinity, alignment: .leading).padding().background(.quaternary.opacity(0.35)).clipShape(RoundedRectangle(cornerRadius: 12)) } }
struct CountChip: View { let title: String, count: Int, color: Color; var body: some View { Text("\(title)  \(count)件").padding(.horizontal, 16).padding(.vertical, 8).background(color.opacity(0.13)).clipShape(Capsule()) } }
