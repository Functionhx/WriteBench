# WriteBench for iPad

原生 SwiftUI / UIKit / PencilKit 应用，要求 **iPadOS 18 或更新版本**。`TARGETED_DEVICE_FAMILY = 2`，只面向 iPad，不包含 iPhone 版，也不启用 Mac Catalyst。

## 功能

- 考研英语一/二、六级、IELTS 的写作与翻译练习；66 道近五年六级完整正文随应用打包。
- 宽窗口题目与答题卡并排；窄窗口上下排列。横竖屏、窗口大小变化均可使用；窄屏切到手写时自动滚到答题卡。
- 原生键盘编辑：保留连续空格，Tab 插入四个空格，当前/选中段落左对齐、居中、右对齐。草稿和备份保留段落格式。
- PencilKit 手写纸、手指/Apple Pencil 输入、橡皮擦和清空确认；笔迹随草稿和备份保存。手写识别需要人工校对，再转换成评阅所需文字。
- 文件 App 图片导入、本机 Vision 中英文 OCR、原图预览、强制校对确认；UTF-8 文本、带文字层 PDF 导入。
- 交卷立即暂停计时；页面切换和退到后台暂停计时并保存草稿。离开前台会取消未完成的评阅，保留提交内容，不生成部分总分。
- DeepSeek 快速/三评审评阅，共用桌面的 rubric、JSON 校验、聚合规则、修改建议与翻译教学。
- 评阅历史、分享复习文本、错题/表达的间隔复习、按题型统计。
- Keychain 保存 API Key；无额外账号或云同步。可导入/导出与 macOS 兼容的 JSON 备份，备份不含凭据。自定义六级题库 JSON 需单独导入到题库。

桌面版的 Codex CLI 无法在 iPadOS 执行，因此 iPad 版目前只提供 DeepSeek。付费真实评阅与实体 Apple Pencil 尚需实机验证。

## Xcode 开发与测试

在仓库根目录：

```sh
xcodegen generate
xcodebuild -project WriteBench.xcodeproj -scheme WriteBenchPad \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' \
  -derivedDataPath build-ipad CODE_SIGN_IDENTITY=- test
```

使用本机实际可用的 iPad 模拟器名称（`xcrun simctl list devices available`）。模拟器构建使用临时签名；不要设置 `CODE_SIGNING_ALLOWED=NO` 来运行应用，否则 Keychain 会返回缺少 entitlement。

CI 会自动选取可用 iPad 模拟器，执行8 项单元测试与 6 项 UI 测试并上传 xcresult。测试使用内存数据库；OCR 测试用样本图片，不调用付费评阅。

## 安装到实体 iPad / TestFlight

打开 `WriteBench.xcodeproj`，选择 **WriteBenchPad** target，在 Signing & Capabilities 选择自己的 Apple 开发 Team，连接 iPad 并运行。按设备要求开启 Developer Mode。

TestFlight / App Store 需要 Apple Developer Program、有效的分发签名和 App Store Connect 配置。模拟器 `.app` 与未签名设备构建都不能直接作为可安装 IPA 分发。当前没有发布 iPad 安装包，不会把模拟器包伪装成 IPA。
