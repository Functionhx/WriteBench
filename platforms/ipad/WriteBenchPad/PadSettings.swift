import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct PadBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
struct PadSettings: View {
    @Bindable var store: PadStore
    @Environment(\.modelContext) private var context
    @AppStorage("deepSeekModel") private var model = DeepSeekClient.defaultModel
    @State private var key = ""
    @State private var remembered = DeepSeekCredentials.hasSessionKey
    @State private var message: String?
    @State private var document = PadBackupDocument(data: Data())
    @State private var exporting = false
    @State private var importing = false
    @State private var confirmImport = false
    var body: some View {
        Form {
            Section("DeepSeek 评阅") {
                TextField("模型 ID", text: $model).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("API Key", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("api-key")
                Button("保存 API Key") { do { try DeepSeekCredentials.save(key); key = ""; remembered = true; message = "API Key 已安全保存。" } catch { store.error = error.localizedDescription } }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if remembered { Label("已保存到本机 Keychain", systemImage: "lock.shield"); Button("删除保存的 API Key", role: .destructive) { do { try DeepSeekCredentials.forget(); remembered = false } catch { store.error = error.localizedDescription } } }
                Text("快速评阅使用 1 位评审；完整评阅使用 3 位评审并汇总。请求使用你自己的 DeepSeek API 余额。iPad 版支持 DeepSeek，桌面的 Codex CLI 登录无法在 iPad 上运行。").font(.footnote).foregroundStyle(.secondary)
            }
            Section("资料备份") {
                Button("导出备份到文件") { store.pause(); do { document = PadBackupDocument(data: try BackupService.export(from: context)); exporting = true } catch { store.error = error.localizedDescription } }
                Button("导入桌面或 iPad 备份") { confirmImport = true }.disabled(store.isGrading)
                Text("备份包含草稿、题目、历史评阅和复习卡片，不包含 API Key。可以通过文件 App 或 AirDrop 传到另一台设备。").font(.footnote).foregroundStyle(.secondary)
            }
            Section("关于") { LabeledContent("平台", value: "iPadOS 18+"); Text("题库默认包含近五年六级写作、翻译完整正文。资料保存在本机；目前不提供自动云同步。") }
        }.navigationTitle("设置")
            .confirmationDialog("导入备份", isPresented: $confirmImport, titleVisibility: .visible) { Button("选择备份文件") { importing = true } } message: { Text("补充本机缺少的记录，不覆盖已有作答。") }
            .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: BackupService.suggestedFileName) { result in
                if case .failure(let error) = result { store.error = error.localizedDescription }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    store.pause()
                    let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    message = try BackupService.restore(Data(contentsOf: url), into: context).text; store.restore()
                } catch { store.error = error.localizedDescription }
            }
            .alert("已完成", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("好") {} } message: { Text(message ?? "") }
    }
}
