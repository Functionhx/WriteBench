import SwiftUI

struct SettingsView: View {
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
                        HStack {
                            Button { testConnection() } label: { Label(testing ? "Connecting…" : "Test connection", systemImage: "network") }.buttonStyle(QuietButtonStyle()).disabled(!keyExists || testing)
                            if keyExists { Button("清除 Key") { do { DeepSeekCredentials.clearSession(); try KeychainService.remove(); keyExists = false; failed = false; status = "API Key 已移除。" } catch { showError(error) } }.buttonStyle(QuietButtonStyle()) }
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
                HStack(spacing: 10) { BrandMark(size: 24); Text("WriteBench 1.2").font(.system(size: 12, weight: .medium)); Text("Made for a more deliberate writing practice.").font(.system(size: 11)).foregroundStyle(WB.secondary) }.padding(.top, 4)
            }.frame(maxWidth: 860).padding(32).frame(maxWidth: .infinity, alignment: .leading)
        }.onAppear { keyExists = DeepSeekCredentials.hasSessionKey || ((try? DeepSeekCredentials.load()) != nil) }
    }
    private var providerCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 20) {
                Label("AI Judges", systemImage: "checkmark.seal").font(.system(size: 19, weight: .semibold)).labelStyle(BlueIconLabelStyle())
                judgePicker(.a, selection: $providerA)
                judgePicker(.b, selection: $providerB)
                judgePicker(.c, selection: $providerC)
                Text("三位评审独立阅读相同的原题和作文，本机取中位数。任一评审失败都不会生成总分或自动切换服务。").font(.system(size: 12)).foregroundStyle(WB.secondary).lineSpacing(4)
            }
        }
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
        do { try DeepSeekCredentials.use(key, remember: rememberKey); key = ""; keyExists = true; failed = false; status = rememberKey ? "Key 已保存到 Keychain，可以交卷。" : "Key 已启用，仅保留在本次运行内存中。现在可以交卷。" }
        catch { keyExists = DeepSeekCredentials.hasSessionKey; key = ""; failed = true; status = keyExists ? "Key 已启用，但无法记住；本次仍可正常评卷，下次启动请重新填写。" : error.localizedDescription }
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
