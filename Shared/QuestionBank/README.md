# 六级 2022–2026 真题库

Windows 和 macOS 内置同一份 `cet6-2022-2026.json`：**33 套，写作 33 题、翻译 33 题，均包含完整正文，可直接选题作答。**

正文提取自用户提供的本机真题 PDF 与 Word 文件。每套的写作题干和翻译题段落均经过 PDF／DOCX 交叉对比，移除了页眉、页脚、听力说明和排版断行，未混入答案或范文。保留写作题的指定开头、150–200 词要求及其他指令。中文词内的排版空格已清理。

少数资料存在英文词内断空格及标点空格问题，如 `t o`、`sen tence`；已对照 PDF 原页修复，并在条目的 `layoutCorrections` 中记录。未擅自改变指定句子的语法或观点。

范围：2022–2025 各已收录场次，以及 2026 年 6 月；包括 2022 年 9 月与 2023 年 3 月场次。套次沿用用户资料／来源网站编号，不保证其他机构的套次编号相同。资料核对依据为用户提供的文件，不表示这些重排资料是考试院发布的原版扫描件。

`cet6-import-audit.json` 保存每套 PDF、Word 的 SHA-256、文件名、交叉核对结果和题干长度。原始 PDF／Word 未复制进安装包。

## 使用

macOS：六级 → 写作／翻译 → 题库，默认显示近五年六级真题；“随机抽题”优先从六级真题抽取，并优先选未练习题目。

Windows：六级 → 写作／翻译 → 随机真题，或“近五年六级题库／批量导入”逐题选择。

## 批量导入与复核

两平台接受相同 JSON 格式，顶层为 `schemaVersion: 1` 和 `questions` 数组；题目字段为 `id`、`task`、`year`、`month`、`set`、`title`、`prompt`、`sourceUrl`、`verification`。题型为 `cet6Writing` 或 `cet6Translation`；用户导入标识为 `userImported`，本次从资料核对的内置题为 `providedDocument`。

缺正文、重复 ID、未知题型、无效来源、未来考试日期或不支持的数据版本会整批拒绝，原题库不变。相同 ID 更新，其余已有题目保留。内置题不会修改用户此前手动保存的题目和作答。

重新提取（需本机有 Poppler 的 `pdftotext`）：

```sh
python3 scripts/import-cet6.py --source '/path/to/六级真题2022-2026'
```

额外导入题目保存于 macOS `~/Library/Application Support/WriteBench/QuestionBank/cet6-custom.json`，Windows `%LOCALAPPDATA%/WriteBench/QuestionBank/cet6-custom.json`。同一 JSON 可在两平台导入，但不自动跨设备同步。macOS 现有“我的题库”备份不包含此独立 JSON，迁移时应另行复制它。
