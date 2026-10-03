import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    var showsBackup = true
    @AppStorage("showLiveWordCount") private var showLiveWordCount = false
    @AppStorage("examTimeLimit") private var examTimeLimit = false
    @AppStorage("autoSubmitAtLimit") private var autoSubmitAtLimit = false
    @AppStorage("quickJudge") private var quickJudge = Judge.b
    @AppStorage(UsageCost.inputKey) private var priceInput = 0.0
    @AppStorage(UsageCost.cachedKey) private var priceCached = 0.0
    @AppStorage(UsageCost.outputKey) private var priceOutput = 0.0
    @AppStorage("deepSeekModel") private var model = DeepSeekClient.defaultModel
    @AppStorage("judgeProviderA") private var providerA = GradingProvider.deepSeek
    @AppStorage("judgeProviderB") private var providerB = GradingProvider.deepSeek
    @AppStorage("judgeProviderC") private var providerC = GradingProvider.codex
    @AppStorage("codexModel") private var codexModel = CodexJudgeService.defaultModel
    @AppStorage("codexReasoning") private var codexReasoning = "max"
    @AppStorage("codexExecutablePath") private var codexPath = ""
    @State private var codexStatus = "尚未检查连接"
    @State private var codexConnected = false
    @State private var checkingCodex = false
    @State private var key = ""
    @State private var keyExists = false
    @State private var rememberKey = false
    @State private var status: String?
    @State private var failed = false
    @State private var testing = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SectionHeading(title: "A workspace of your own.", subtitle: "Settings · AI providers and local storage.")
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("答题偏好", systemImage: "textformat.123").font(.system(size: 18, weight: .semibold)).labelStyle(BlueIconLabelStyle())
                        Toggle("答题时显示词数", isOn: $showLiveWordCount).toggleStyle(.switch).accessibilityIdentifier("showLiveWordCountSetting")
                        Text("默认关闭，交卷后再显示本次词数。开启后，所有考试的答题页显示实时计数；中文译文显示字符数。").font(.system(size: 12)).foregroundStyle(WB.secondary)
                        Divider().padding(.vertical, 4)
                        Toggle("考试限时（倒计时）", isOn: $examTimeLimit).toggleStyle(.switch).accessibilityIdentifier("examTimeLimitSetting")
                        Toggle("到点自动交卷（三位评审）", isOn: $autoSubmitAtLimit).toggleStyle(.checkbox).disabled(!examTimeLimit).padding(.leading, 2)
                        Text("开启后答题页显示剩余时间，最后 5 分钟变色，到点提示音；不自动交卷时可继续作答并显示超时。限时：" + WritingTask.allCases.map { "\($0.exam == .ielts ? "雅思" : $0.exam == .cet6 ? "六级" : "考研")\($0.title) \($0.suggestedMinutes)" }.joined(separator: " · ") + " 分钟。")
                            .font(.system(size: 12)).foregroundStyle(WB.secondary).lineSpacing(3)
                    }
                }
                providerCard
                codexCard
                Card {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack { Label("DeepSeek API", systemImage: "key.horizontal").font(.system(size: 18, weight: .semibold)).labelStyle(BlueIconLabelStyle()); Spacer(); Label(keyExists ? "Key available" : "请填写 API Key", systemImage: keyExists ? "lock.fill" : "lock.open").font(.system(size: 11)).foregroundStyle(keyExists ? WB.green : WB.secondary) }
                        Text("API Key").font(.system(size: 12, weight: .medium))
                        HStack {
                            SecureField("Paste your DeepSeek API key", text: $key).textFieldStyle(.plain).padding(13).background(WB.canvas, in: RoundedRectangle(cornerRadius: 11)).overlay(RoundedRectangle(cornerRadius: 11).stroke(WB.line)).accessibilityIdentifier("apiKeyField")
                            Button("使用此 Key") { saveKey() }.buttonStyle(PrimaryButtonStyle()).disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        Toggle("在这台 Mac 上记住 Key（Keychain）", isOn: $rememberKey).font(.system(size: 12)).toggleStyle(.checkbox)
                        Text("直接填写即可使用。默认只在本次运行中保留；无需输入 Mac 密码。").font(.system(size: 11)).foregroundStyle(WB.secondary)
                        HStack { Text("Model").font(.system(size: 12, weight: .medium)).frame(width: 70, alignment: .leading); TextField("Model ID", text: $model).textFieldStyle(.roundedBorder).frame(maxWidth: 340) }
                        Text("默认：\(DeepSeekClient.defaultModel) · MAX 思考。模型 ID 可修改，不会自动切换。").font(.system(size: 11)).foregroundStyle(WB.secondary)
                        HStack(spacing: 10) {
                            Text("价格").font(.system(size: 12, weight: .medium)).frame(width: 70, alignment: .leading)
                            priceField("输入", $priceInput); priceField("缓存命中", $priceCached); priceField("输出", $priceOutput)
                            Text("元 / 百万 tokens").font(.system(size: 11)).foregroundStyle(WB.secondary)
                        }
                        Text("按 DeepSeek 官网当前价格填写后，评阅页和统计页显示估算花费；留空只显示 token 数。").font(.system(size: 11)).foregroundStyle(WB.secondary)
                        HStack {
                            Button { testConnection() } label: { Label(testing ? "Connecting…" : "Test connection", systemImage: "network") }.buttonStyle(QuietButtonStyle()).disabled(!keyExists || testing)
                            if keyExists { Button("清除 Key") { Task { do { try await DeepSeekCredentials.forget(); keyExists = false; failed = false; status = "API Key 已移除。" } catch { showError(error) } } }.buttonStyle(QuietButtonStyle()) }
                            Spacer()
                        }
                        if let status { Label(status, systemImage: failed ? "exclamationmark.circle" : "checkmark.circle").font(.system(size: 12)).foregroundStyle(failed ? WB.amber : WB.green).textSelection(.enabled) }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Local by design", systemImage: "externaldrive.badge.checkmark").font(.system(size: 18, weight: .semibold)).labelStyle(BlueIconLabelStyle())
                        settingsNote("SwiftData", "作文、校对后的原稿、评阅、重写和题库保存在这台 Mac。")
                        settingsNote("Vision OCR", "图片识别在本机完成。必须经过校对确认才会评分。")
                        settingsNote("Three reviewers", "三次独立请求；本机取中位数。置信度表示评审一致性，不是准确率保证。")
                        settingsNote("Exam scales", "英语一：小作文 / 10，大作文 / 20；CET-6 写作原始分 / 15；IELTS 单项任务 band / 9。")
                    }
                }
                if showsBackup { BackupCard() }
                HStack(spacing: 10) { BrandMark(size: 24); Text("WriteBench \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")").font(.system(size: 12, weight: .medium)); Text("Made for a more deliberate writing practice.").font(.system(size: 11)).foregroundStyle(WB.secondary) }.padding(.top, 4)
            }.frame(maxWidth: 860).padding(32).frame(maxWidth: .infinity, alignment: .leading)
        }.task { await DeepSeekCredentials.restoreRememberedKey(); keyExists = DeepSeekCredentials.hasSessionKey }
    }
    private var providerCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 20) {
                Label("AI Judges", systemImage: "checkmark.seal").font(.system(size: 19, weight: .semibold)).labelStyle(BlueIconLabelStyle())
                judgePicker(.a, selection: $providerA)
                judgePicker(.b, selection: $providerB)
                judgePicker(.c, selection: $providerC)
                Text("三位评审独立阅读相同的原题和作文，本机取中位数。任一评审失败都不会生成总分或自动切换服务。").font(.system(size: 12)).foregroundStyle(WB.secondary).lineSpacing(4)
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 4) { Text("快速单评").font(.system(size: 13, weight: .semibold)); Text("答题页“快速单评”或 ⇧⌘↩ · 只请一位评审，适合草稿").font(.system(size: 11)).foregroundStyle(WB.secondary) }
                    Spacer()
                    Picker("快速单评", selection: $quickJudge) {
                        ForEach(Judge.allCases) { judge in Text("\(judge.title) · \(provider(judge).title)").tag(judge) }
                    }.labelsHidden().frame(width: 240).accessibilityIdentifier("quickJudge")
                }
            }
        }
    }
    private func provider(_ judge: Judge) -> GradingProvider { switch judge { case .a: providerA; case .b: providerB; case .c: providerC } }
    private func priceField(_ title: String, _ value: Binding<Double>) -> some View {
        TextField(title, value: value, format: .number.precision(.fractionLength(0...4))).textFieldStyle(.roundedBorder).frame(width: 74).help(title)
    }
    private func judgePicker(_ judge: Judge, selection: Binding<GradingProvider>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) { Text(judge.title).font(.system(size: 13, weight: .semibold)); Text(judge.role).font(.system(size: 11)).foregroundStyle(WB.secondary) }
            Spacer()
            Picker(judge.title, selection: selection) { ForEach(GradingProvider.allCases) { Text($0.title).tag($0) } }.labelsHidden().frame(width: 240).accessibilityIdentifier("provider_\(judge.rawValue)")
        }
    }
    private var codexCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 18) {
                HStack { Label("ChatGPT · via Codex", systemImage: "terminal").font(.system(size: 18, weight: .semibold)).labelStyle(BlueIconLabelStyle()); Spacer(); Image(systemName: codexConnected ? "checkmark.circle.fill" : "circle.dashed").foregroundStyle(codexConnected ? WB.green : WB.secondary) }
                Text("Uses your signed-in Codex account · 使用 Codex 额度，无需 OpenAI API Key。").font(.system(size: 12)).foregroundStyle(WB.secondary)
                HStack { Text("Model").frame(width: 70, alignment: .leading); TextField("Automatic（由 Codex 选择）", text: $codexModel).textFieldStyle(.roundedBorder) }.font(.system(size: 12))
                Picker("Thinking", selection: $codexReasoning) { Text("Medium").tag("medium"); Text("High").tag("high"); Text("Extra high").tag("xhigh"); Text("MAX").tag("max") }.frame(maxWidth: 380, alignment: .leading)
                Text("当前默认 GPT-6 Astra · MAX。最高单评审思考强度，可能需要数分钟。").font(.system(size: 11)).foregroundStyle(WB.secondary)
                DisclosureGroup("Codex CLI 路径") { TextField("自动检测 Homebrew / .local / Codex.app", text: $codexPath).textFieldStyle(.roundedBorder).padding(.top, 8) }.font(.system(size: 12))
                HStack {
                    Button(checkingCodex ? "Checking…" : "Check Connection") { checkCodex() }.buttonStyle(QuietButtonStyle()).disabled(checkingCodex).accessibilityIdentifier("checkCodex")
                    Text(codexStatus).font(.system(size: 12)).foregroundStyle(codexConnected ? WB.green : WB.secondary).textSelection(.enabled)
                }
                Text("首次使用请在终端运行 codex login，通过官方流程登录 ChatGPT 后检查连接。WriteBench 不读取或保存 Codex 认证文件、Cookie 或 Token。").font(.system(size: 12)).foregroundStyle(WB.secondary).lineSpacing(4)
            }
        }
    }
    private func checkCodex() {
        checkingCodex = true; codexStatus = "正在检查官方 CLI 与登录状态…"; codexConnected = false
        Task {
            defer { checkingCodex = false }
            do { let connection = try await CodexJudgeService.checkConnection(customPath: codexPath); codexConnected = true; codexStatus = "已通过 ChatGPT 登录 · \(connection.version)" }
            catch { codexStatus = error.localizedDescription }
        }
    }
    private func settingsNote(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 20) { Text(title).font(.system(size: 12, weight: .medium)).frame(width: 110, alignment: .leading); Text(detail).font(.system(size: 12)).foregroundStyle(WB.secondary).lineSpacing(4) }
    }
    private func saveKey() {
        let supplied = key
        do {
            try DeepSeekCredentials.use(supplied, remember: rememberKey)
            key = ""; keyExists = true; failed = false
            status = "Key 已启用，仅保留在本次运行内存中。现在可以交卷。"
            if rememberKey {
                Task {
                    do { try await DeepSeekCredentials.remember(supplied); status = "Key 已保存到 Keychain，可以交卷。" }
                    catch { failed = true; status = "Key 已启用，但无法记住；本次仍可正常评卷，下次启动请重新填写。" }
                }
            }
        } catch { showError(error) }
    }
    private func showError(_ error: Error) { failed = true; status = error.localizedDescription }
    private func testConnection() {
        testing = true; status = nil
        Task {
            defer { testing = false }
            do {
                let models = try await DeepSeekClient(apiKey: DeepSeekCredentials.load(), model: model).testConnection()
                failed = false; status = models.contains(model) ? "连接成功，当前模型可用。" : "连接成功。账户可用模型：" + models.joined(separator: ", ")
            } catch { showError(error) }
        }
    }
}

private struct BackupCard: View {
    @Environment(\.modelContext) private var context
    @State private var status: String?
    @State private var failed = false
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Label("数据备份", systemImage: "arrow.up.arrow.down.circle").font(.system(size: 18, weight: .semibold)).labelStyle(BlueIconLabelStyle())
                Text("导出为一个 JSON 文件，包含全部作文、评阅、草稿、题库、目录信息、复习卡和图片；不含 API Key 与 Codex 登录信息。恢复时只添加本机没有的记录，不覆盖现有内容。")
                    .font(.system(size: 12)).foregroundStyle(WB.secondary).lineSpacing(4)
                HStack {
                    Button { export() } label: { Label("导出备份…", systemImage: "square.and.arrow.up") }.buttonStyle(QuietButtonStyle()).accessibilityIdentifier("exportBackup")
                    Button { restore() } label: { Label("从备份恢复…", systemImage: "square.and.arrow.down") }.buttonStyle(QuietButtonStyle()).accessibilityIdentifier("restoreBackup")
                    Spacer()
                }
                if let status { Label(status, systemImage: failed ? "exclamationmark.circle" : "checkmark.circle").font(.system(size: 12)).foregroundStyle(failed ? WB.amber : WB.green).textSelection(.enabled) }
            }
        }
    }
    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = BackupService.suggestedFileName; panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try BackupService.export(from: context)
            try data.write(to: url, options: .atomic)
            failed = false; status = "已导出到 \(url.lastPathComponent)（\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))）。"
        } catch { failed = true; status = error.localizedDescription }
    }
    private func restore() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { failed = false; status = try BackupService.restore(try Data(contentsOf: url), into: context).text }
        catch { failed = true; status = error.localizedDescription }
    }
}
