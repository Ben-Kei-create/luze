import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        if store.settings.hasCompletedOnboarding != true {
            WelcomeView()
        } else {
            mainView
        }
    }
    private var mainView: some View {
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

struct WelcomeView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 58)).foregroundStyle(.tint)
            Text("Luze").font(.system(size: 42, weight: .bold))
            Text("経理を、シンプルに。").font(.title2).foregroundStyle(.secondary)
            Text("毎月の入力、証憑確認、カード明細の分類、集計、メール作成を\n上から順番に進めるだけで完了できます。")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.vertical, 12)
            Button("今月の処理をはじめる") { store.settings.hasCompletedOnboarding = true }.buttonStyle(.borderedProminent).controlSize(.large)
            Button("設定からはじめる") { store.settings.hasCompletedOnboarding = true; store.selection = .settings }.buttonStyle(.link)
        }.frame(minWidth: 760, minHeight: 560).padding(40)
    }
}

struct MonthSelector: View {
    @Binding var month: Date
    var body: some View {
        HStack {
            Button { move(-1) } label: { Image(systemName: "chevron.left") }
            Text(AppStore.displayMonth.string(from: month)).font(.headline).frame(width: 120)
            Button { move(1) } label: { Image(systemName: "chevron.right") }
        }.buttonStyle(.borderless)
    }
    func move(_ value: Int) { month = Calendar.current.date(byAdding: .month, value: value, to: month) ?? month }
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
    var body: some View { Page(title: "\(AppStore.displayMonth.string(from: store.month))の処理") { Text("5ステップで完了します").foregroundStyle(.secondary); MonthSelector(month: $store.month); VStack(spacing: 0) { ForEach(steps.indices, id: \.self) { i in Button { if i == 4 { store.selection = .mail } else { store.step = i + 1 } } label: { HStack(spacing: 16) { ZStack { Circle().fill(store.current.completedSteps.contains(i + 1) ? Color.green : Color.accentColor.opacity(0.12)).frame(width: 36, height: 36); Text(store.current.completedSteps.contains(i + 1) ? "✓" : "\(i + 1)").foregroundStyle(store.current.completedSteps.contains(i + 1) ? Color.white : Color.accentColor) }; VStack(alignment: .leading) { Text(steps[i].0).font(.headline); Text(steps[i].1).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary) }.padding(16).contentShape(Rectangle()) }.buttonStyle(.plain); if i < 4 { Divider().padding(.leading, 68) } } }.background(.background).clipShape(RoundedRectangle(cornerRadius: 12)).shadow(color: .black.opacity(0.06), radius: 8) } }
}

struct InputStep: View {
    @EnvironmentObject var store: AppStore
    var body: some View { Page(title: "1. 入力") { MonthSelector(month: $store.month); Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 16) { ForEach(store.settings.monthlyFields) { field in fieldRow(field) } }; HStack { Button("戻る") { store.step = 0 }; Spacer(); Button("次へ") { store.complete(1) }.buttonStyle(.borderedProminent) } } }
    @ViewBuilder func fieldRow(_ field: MonthlyFieldDefinition) -> some View { GridRow { Text(field.name).frame(width: 130, alignment: .leading); TextField("0", value: Binding(get: { store.current.value(for: field.id) }, set: { value in store.updateCurrent { $0.setValue(value, for: field.id) } }), format: .number).frame(width: 180); Text(field.kind.unit).foregroundStyle(.secondary) } }
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
    var body: some View { Page(title: "3. Vpass確認") { if store.current.transactions.isEmpty { ContentUnavailableView("CSVを読み込んでください", systemImage: "tablecells", description: Text("VpassのCSVファイルを選択します。")); HStack { Button("戻る") { store.step = 2 }; Spacer(); Button("CSVを選択") { chooseCSV() }.buttonStyle(.borderedProminent) } } else { let item = store.current.transactions[min(index, store.current.transactions.count - 1)]; Text("\(index + 1) / \(store.current.transactions.count)").foregroundStyle(.secondary); VStack(spacing: 14) { Text(item.merchant).font(.title.bold()); Text(item.date.formatted(date: .long, time: .omitted)); Text(item.amount, format: .currency(code: "JPY")).font(.system(size: 36, weight: .semibold)); Picker("判断", selection: decisionBinding(item.id)) { ForEach(Decision.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).frame(maxWidth: 420); if item.decision == .expense { TextField("用途（例：書籍・資料）", text: purposeBinding(item.id)).frame(maxWidth: 420) } }.frame(maxWidth: .infinity).padding(28).background(.quaternary.opacity(0.3)).clipShape(RoundedRectangle(cornerRadius: 16)); HStack { Button("戻る") { if index > 0 { index -= 1 } else { store.step = 2 } }; Button("別のCSVを読み込む") { chooseCSV() }; Spacer(); Button(index + 1 < store.current.transactions.count ? "次の取引" : "集計へ") { if index + 1 < store.current.transactions.count { index += 1 } else { store.complete(3) } }.buttonStyle(.borderedProminent) } } } }
    func decisionBinding(_ id: UUID) -> Binding<Decision> { Binding(get: { store.current.transactions.first(where: { $0.id == id })?.decision ?? .pending }, set: { value in store.updateCurrent { if let i = $0.transactions.firstIndex(where: { $0.id == id }) { $0.transactions[i].decision = value } } }) }
    func purposeBinding(_ id: UUID) -> Binding<String> { Binding(get: { store.current.transactions.first(where: { $0.id == id })?.purpose ?? "" }, set: { value in store.updateCurrent { if let i = $0.transactions.firstIndex(where: { $0.id == id }) { $0.transactions[i].purpose = value } } }) }
    func chooseCSV() { let panel = NSOpenPanel(); panel.allowedContentTypes = [.commaSeparatedText]; panel.allowsMultipleSelection = false; if panel.runModal() == .OK, let url = panel.url { do { try store.importCSV(url: url) } catch { store.notice = "Vpass CSVを読み込めませんでした\n\(error.localizedDescription)" } } }
}

struct SummaryStep: View {
    @EnvironmentObject var store: AppStore
    var body: some View { let d = store.current; let vpass = d.transactions.filter { $0.decision == .expense }.reduce(0) { $0 + $1.amount }; let transport = store.attendanceDays(d) * store.settings.oneWayFare * 2; Page(title: "4. 集計") { HStack(spacing: 40) { Metric(title: "収入", value: store.incomeTotal(d)); Metric(title: "支出合計", value: store.expenseTotal()) }; VStack(spacing: 8) { ExpenseLine(title: "固定費", value: store.settings.rent); ExpenseLine(title: "Vpass経費", value: vpass); ExpenseLine(title: "交通費", value: transport) }.frame(maxWidth: 360); HStack { CountChip(title: "経費", count: d.transactions.filter { $0.decision == .expense }.count, color: .green); CountChip(title: "除外", count: d.transactions.filter { $0.decision == .excluded }.count, color: .gray); CountChip(title: "保留", count: d.transactions.filter { $0.decision == .pending }.count, color: .orange) }; StatusRow(title: "Google Sheets", ok: d.sheetExported, detail: d.sheetExported ? "反映済み" : "未反映"); Button(store.isWorking ? "反映中…" : "内容を確認してGoogle Sheetsへ反映") { Task { await store.exportToSheet() } }.disabled(store.isWorking); HStack { Button("戻る") { store.step = 3 }; Spacer(); Button("メールへ") { store.complete(4); store.selection = .mail }.buttonStyle(.borderedProminent) } } }
}
struct Metric: View { let title: String, value: Int; var body: some View { VStack(alignment: .leading) { Text(title).foregroundStyle(.secondary); Text(value, format: .currency(code: "JPY")).font(.largeTitle.bold()) }.frame(maxWidth: .infinity, alignment: .leading).padding().background(.quaternary.opacity(0.35)).clipShape(RoundedRectangle(cornerRadius: 12)) } }
struct ExpenseLine: View { let title: String, value: Int; var body: some View { HStack { Text(title).foregroundStyle(.secondary); Spacer(); Text(value, format: .currency(code: "JPY")).monospacedDigit() } } }
struct CountChip: View { let title: String, count: Int, color: Color; var body: some View { Text("\(title)  \(count)件").padding(.horizontal, 16).padding(.vertical, 8).background(color.opacity(0.13)).clipShape(Capsule()) } }
