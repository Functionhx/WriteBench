# WriteBench 1.4

A real native macOS exam-writing workstation, built with Swift 6, SwiftUI, AppKit, SwiftData, Vision and Swift Charts. No web wrapper, external runtime or third-party app dependencies.

## Open the app

Double-click **WriteBench.app** in this folder, or open **WriteBench.xcodeproj** in Xcode and run the **WriteBench** scheme with **My Mac** selected.

- Requires macOS 15 or later.
- Developed and tested with Xcode 26.6 on Apple silicon.
- The included Release app is locally ad-hoc signed. App Store/distribution signing and notarization are not included.
- Real grading only. Missing credentials prompt for setup; no demo mode or fake review is available to users.
- Default judges: DeepSeek V4 Pro / DeepSeek V4 Pro / GPT-6 Astra via official Codex CLI, all with MAX reasoning. Each role’s provider is selectable.

## The writing workflow

1. Choose 考研英语 (英语一小作文/大作文、英语一/二翻译), CET-6 writing/translation, or IELTS Academic Task 1 / Task 2.
2. Use the supplied **original practice question**, edit/paste your own, or import an image. The pencil beside the question toggles its plain-text editor. 真题库 saves your own labelled question sources; bundled exercises are not presented as past papers.
3. Click **开始答题** (or **⌘Return**) to enter the only answering workspace: native full-screen immersion. Preparation has no essay editor or grading button. The sidebar, exam tabs and decorative cards disappear. The question stays on the left and your answer on the right.
4. The timer starts when you start answering. Kaoyan and CET-6 use a ruled answer area. All tasks default to **no live word count**. Enable **答题时显示词数** in Settings if wanted; Chinese translations show characters. This is a practice writing surface, not a claim of exact official answer-card dimensions. Native undo/redo and copy/paste remain available through standard shortcuts, without a formatting toolbar. **保存并离开** saves the draft and pauses its timer; continuing requires **开始答题** again. Switching away from the app during an active session does not stop the exam timer. Leaving macOS full screen through the system controls still leaves you in the same minimal answering workspace.
5. Click **交卷** or press **⌘Return** while answering. The app immediately returns to preparation while three independent graders run in the background. The status strip shows actual completed reviewers, elapsed time and submitted word count. Switch pages, edit another draft or minimize the window; use **查看进度** for streamed DeepSeek comments. Codex feedback arrives when its structured result completes. Open the final review yourself when ready. Failure or cancellation never overwrites the current draft or produces a partial total. Quitting the app interrupts unfinished grading. There is no non-immersive submission route.
6. In History / Review, **开始重写** or **继续重写** enters the same immersive workspace. Rewrites automatically save back to the source review, including after closing/reopening the app. The review page itself has no alternate editable essay field. Each completed regrading retains its own review inside the same question folder. New rewrites record their source version, including branches from an older draft. Old same-question records are grouped without inventing parent links. The review header **Copy** copies the assessment; the existing improved-essay **Copy** still copies only that essay.

Drafts are kept separately for all eight task types, with debounced local saves and periodic timer saves. Expand a question folder in History to reopen complete reviews, including the original question, essay and imported source images. Search and exam filtering are available in History.

## Handwritten essays and OCR

Use **导入题目图片** on the preparation page for a question. To import one or more handwritten pages, first click **开始答题**, then **导入手写稿** in the immersive workspace. PNG, JPEG, HEIC, TIFF and BMP are supported. Up to 12 pages per import, 25 MB per page and 80 MB total. Each file is treated as one page; multi-frame TIFF/PDF import is not implemented.

Vision recognition runs on a worker task, on the Mac. Automatic language correction is disabled to avoid silently fixing student language. The confirmation screen shows the original image on the left and editable recognized text on the right. You can navigate and reorder pages. Inside the answering workspace, select **题目 + 作文** for a mixed photo and move the prompt into the question field, leaving only the answer in the essay fields.

**Nothing is graded at import time.** All pages must be checked and the confirmation checkbox selected before **Confirm & Grade** becomes available. Question-only imports use **确认并填入题目** and never trigger grading. For visual/chart prompts, add the chart values and relevant visual meaning to the confirmed question text: grading uses text, not raw images. Handwriting quality varies; OCR errors must be corrected manually.

## Configure AI judges

Open **Settings**. Each of the three roles has its own provider selector; defaults are DeepSeek / DeepSeek / ChatGPT via Codex.

For DeepSeek, paste your own API key and click **使用此 Key**. It works immediately, with no Mac password required. By default it remains only in process memory until quitting. **在这台 Mac 上记住 Key** optionally saves it to Keychain. The current default model is `deepseek-v4-pro`, with `thinking: enabled`, `reasoning_effort: max`, and a 128K output ceiling that includes thinking. The app validates the entire JSON response before saving a grade.

For **ChatGPT · via Codex**, install the official CLI and run `codex login` once in Terminal if needed. **Check Connection** checks the executable and official ChatGPT login status; an existing login is reused without another browser flow. Default model: `gpt-6-astra`; reasoning: **MAX**. WriteBench never reads Codex authentication files, cookies or tokens. Codex manages authentication and allowance. Each judge uses a fresh ephemeral CLI request with a JSON Schema.

The app has no automatic provider fallback. If any judge fails, its name and provider are shown and no total score is saved. Missing DeepSeek keys preserve the draft and offer **前往设置** or **继续作答**. Codex-only configurations do not require a DeepSeek key.

See [provider architecture and validation](Providers.md). Real Codex/MAX structured grading has been validated using a synthetic essay; DeepSeek model-list connection has been validated. This native direct-distribution build is not App Sandboxed because it launches the independently installed CLI. No system security setting is changed. Existing local essays are preserved.

## Scoring and statistics

- Kaoyan English I small essay: `/ 10`; large essay: `/ 20`.
- CET-6 Writing: practice raw writing score `/ 15`, without a claimed conversion to the CET report scale.
- IELTS: single-task band estimate `/ 9`, not an overall Writing band.
- The app-owned Markdown rubrics are practical summaries, not official examiner scoring systems. IELTS criterion context follows [IELTS Writing criteria](https://ielts.org/take-a-test/preparation-resources/writing-test-resources) and [Academic Writing task format](https://ielts.org/take-a-test/test-types/ielts-academic-test/ielts-academic-format-writing).
- Overall score is the **local median** of all three results. Spread is max minus min, in that task's raw score units. `≤ 1`: High; `≤ 2`: Medium; `> 2`: Low. Confidence indicates agreement, not a measured probability of correctness.
- The four overview meters are **0–10 practice diagnostics**, separate from the exam's scoring scale.
- Statistics normalize scores to a percentage of each task's maximum and allow task filtering. Legacy demo reviews are hidden and excluded. Corrections duplicated across reviewers are counted once per essay. Mistakes shows prior-essay examples with links back to their reviews.
- `ChiefExaminerService` is an extension point for optional future arbitration. It is deliberately not called in v1.

## Project map

```
WriteBench/
  App/                 App lifecycle and three-zone workspace
  DesignSystem/        Colors, spacing, reusable card/button styles
  Components/          Brand art and native plain-text editor
  Models/              Exam tasks and Codable grading structures
  Features/
    Writing/           Editor, timer, drafts, question library, OCR confirmation
    Review/            Scores, comments, corrections, improved version, rewrite
    History/           Saved reviews and search
    Statistics/        Swift Charts and normalized statistics
    Mistakes/          Recurring categories with examples
    Settings/          Judge providers, Codex status, model and optional Keychain UI
  Persistence/         EssaySession, WritingDraft, SavedQuestion (SwiftData)
  Services/
    OCR/               Vision and native file import
    DeepSeek/          URLSession, in-memory credentials, optional Keychain
    Codex/             Official CLI discovery, subprocess, JSON Schema
    Grading/           Provider protocol, orchestration, validation, median
  Rubrics/             Eight bundled, versioned Markdown resources
WriteBenchTests/       Domain, concurrency, transport, persistence and real OCR tests
```

## Command-line build

The generated Xcode project is included; XcodeGen is not required to build it.

```sh
cd /Users/chen/Downloads/WriteBench
xcodebuild -project WriteBench.xcodeproj -scheme WriteBench \
  -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/WriteBench.app
```

Run tests:

```sh
xcodebuild -project WriteBench.xcodeproj -scheme WriteBench \
  -configuration Debug -derivedDataPath build \
  -destination 'platform=macOS' test
```

Build and copy the Release app into this folder:

```sh
./scripts/build.sh
```

`project.yml` is the optional XcodeGen source. Regenerate only after changing target/file structure: `xcodegen generate`. The original W app icon is generated by `scripts/make-icon.swift` using AppKit drawing. Editable vector source, PNG/ICNS exports and size previews are in [Design/Icon](Design/Icon/README.md).
