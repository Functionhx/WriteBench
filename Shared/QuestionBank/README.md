# 六级 2022–2026 题库数据

Windows 和 macOS 使用同一个 `cet6-2022-2026-index.json` 文件。

**目前是第三方来源索引，包含写作 33 条、翻译 33 条，不包含真题正文，不能直接作为练习题。** 目录来自以下页面，并保留来源的套次编号，尚未逐卷核对正文、日期或题目真实性：

- https://english-exam.lazynote.cn/cet6/sections/writing/
- https://english-exam.lazynote.cn/cet6/sections/chinese-english-translation/

范围：2022、2023、2024、2025、2026；2026 仅列 6 月。包含目录中的 2022 年 9 月与 2023 年 3 月条目。不能将来源编号视为所有机构一致使用的官方套次编号。

## 完整正文批量导入

从用户提供的 PDF、图片或题目文件中提取并校对题目后，生成相同 JSON 格式：

```json
{
  "schemaVersion": 1,
  "questions": [
    {
      "id": "cet6-2024-06-1-cet6Writing",
      "task": "cet6Writing",
      "year": 2024,
      "month": 6,
      "set": 1,
      "title": "2024 年 6 月 · 来源第 1 套 · 写作",
      "prompt": "这里填写从你提供的资料提取并校对后的完整题干",
      "sourceUrl": "https://example.com/source",
      "verification": "userImported"
    }
  ]
}
```

翻译的 `task` 为 `cet6Translation`。来源链接应指向所用资料的出处，不应伪造。导入文件必须全部有正文；仅含索引、重复 ID、未知题型、无效来源、未来考试日期或不支持的数据版本会整体拒绝，原题库不变。相同 ID 在后续导入中更新，其余已有条目保留。

macOS：题库 → 近五年六级 → 批量导入题库 JSON。Windows：六级 → 写作／翻译 → 近五年六级题库／批量导入。

用户题库只保存在本机：macOS `~/Library/Application Support/WriteBench/QuestionBank/cet6-custom.json`；Windows `%LOCALAPPDATA%/WriteBench/QuestionBank/cet6-custom.json`。两平台使用同一种格式，但不会自动跨设备同步。macOS 原有“我的题库”备份不会自动包含这个独立 JSON 文件；迁移时应另行复制它。
