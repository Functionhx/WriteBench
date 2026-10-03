# 1.6.2 validation · 2026-10-02

- 66 Swift tests pass. New coverage: the custom caret replaces the system indicator, stays within one text line on Latin and blank lines, moves with the selection and hides for a range selection; answer-sheet numbering for the six kaoyan tasks.
- The full answering page was rendered offscreen from the app sources for English II small essay and English I translation and compared with a published 英语（二）答题卡 2 writing page (section heading, black frame, dark rules, question number, corner marks).

# 1.6.1 validation · 2026-10-02

- 65 Swift tests pass. New coverage: `<u>` markup renders as an underline in place and strips to plain text; a malformed tag degrades to plain text; the ruled editor keeps natural line height with spacing after each line and an even 36 pt pitch at 18 pt for Latin, CJK and blank lines.
- The ruled editor was rendered offscreen in sans and serif with mixed English/Chinese text: every line sits on its own rule. In an isolated QA copy the English I translation shows (46)–(50) underlined inside the passage, and Settings shows a live editor preview.
- The user's local English I translation questions were rewritten to the underline format by question id (17 questions, 1 matching draft); no graded essay was changed.

# 1.6.0 validation · 2026-10-02

- 63 Swift tests pass on Xcode 27.0. New coverage: English II small/large tasks (scales 10/15, 100/150 words, own rubrics loaded from the bundle), kaoyan task order, and the grader prompt carrying the 【配图说明】 transcription rule with the 0–15 scale.
- An isolated QA copy restored a 68-question local package (2010–2026 English I/II small and large essays, 34 figures) through the existing backup restore: 17 per task, figures stored and shown in the library badge, preparation page and immersive view; English II large essay countdown is 30 minutes. The six kaoyan task tabs fit the preparation column. No user database was used.
- Past-paper text and figures are not bundled in the app or repository; they were imported only into the user's local question bank.

# 1.5.0 validation · 2026-10-02

- 62 Swift tests pass on Xcode 27.0 / macOS 27.0.1. New coverage: correction anchoring across curly quotes, full-width punctuation, whitespace and case; invented spans dropped without failing the review; DeepSeek streamed usage (including cache hits and reasoning tokens) and Codex turn-completion usage; required `expressions` in the Codex schema; single-judge quick review routing, aggregation and persistence; legacy reports decoding as full reviews; one exam time-up signal per crossing; clearing an untouched submitted draft; word/character revision diffs; parent-then-earlier revision baselines; built-in bank uniqueness and practice index; review-card sync idempotence and the 1/2/4/8/16-day schedule; backup export/restore round trip with images, cards and drafts, and a second restore that adds nothing.
- Two existing expectations changed by design: an invented correction span no longer rejects the whole review, and a successfully graded, unchanged draft starts fresh.
- An isolated QA copy (separate bundle identifier, store and defaults) was seeded through the new backup restore with six synthetic reviews, then each page was captured: review score, comparison card and word diff, annotated essay, quick-review score card, History deltas and 单评 label, Statistics trends, Mistakes trends and mastery, Practice start and a revealed drill card, question bank sheet, immersive countdown, and Settings. Layout issues found there (sidebar badge truncation, struck words joining neighbours) were fixed. The user's database and defaults were not used.
- No paid live grading was run. DeepSeek usage relies on `stream_options.include_usage`; Codex usage parsing is lenient and absent usage is not an error. Model compliance with the new `expressions` field is untested live.
- macOS version 1.5.0 (8), Universal arm64 + x86_64. SwiftData adds the `ReviewCard` model and defaulted `SavedQuestion.year` / `label`; existing stores migrate lightly. Prompt version 1.3.0.

# 1.4.0 validation · 2026-09-13

- 49 Swift tests pass on Xcode 26.6 / macOS 26.6.2. New coverage includes completion-order progress, concurrent independent inputs, immutable submission and rewrite-parent snapshots, editing a new draft during grading, duplicate-submit rejection, cancellation, judge-specific failure, Codex preflight failure, and no partial score persistence.
- SSE fixtures cover UTF-8 split across byte boundaries, CRLF, comments, multiline data, escaped/incomplete JSON summaries, first readable previews, required final `[DONE]`, malformed/truncated completion rejection, and backward-compatible saved feedback. Production streaming uses URLSession async bytes; no paid live DeepSeek streaming call was made for this release.
- History tests cover chronological ordering, old same-question grouping without invented ancestry, branching from an earlier draft, search retaining all versions, exam/prompt/image isolation, demo exclusion, revision parent persistence across a disk-store reopen, optional year validation, folder metadata persistence/filtering and inheritance by future versions. Review export includes scores, comments and corrections while leaving both full essay bodies out; old saved reports still copy correctly.
- A separate fixture executable built the original v1.3.1 SwiftData schema and wrote two synthetic reviews (4.5 and 7.5). An isolated copy of the new app successfully opened and migrated that store, displayed one question folder and reopened both complete legacy reviews. No user database was used for this upgrade check.
- Native interactive checks in isolated app copies: hand-in returns to preparation with a 0/3 status bar; Settings remains accessible during grading; word count defaults off and becomes visible in immersion when enabled; a completed review is opened explicitly. The history folder and its two child rows were visually inspected. Clicking the new review Copy showed Copied; the existing improved-essay Copy remains separate. The question-info menu saved a custom title, 2024 year and label in the isolated store, exposed year/label filters, and kept exam/task badges visible. The left review outline was checked with actual section jumps.
- Real-time partial-preview timing and cancellation are covered by gated service tests. Codex still displays its final structured feedback on completion, rather than token streaming. An end-to-end live mixed-provider paid review is not claimed.
- The hosted test app uses an in-memory container and does not restore credentials. Credential preference tests use a temporary defaults suite. QA copies have separate identities and synthetic data; the user's running app and current writing session were left untouched.
- macOS version 1.4.0 (7), Universal arm64 + x86_64. SwiftData adds optional `EssaySession.parentSessionID` and the separate `EssayFolderMetadata` model; grouping is computed without rewriting old records. Windows and Android remain 0.1.0.

# 1.3.1 validation · 2026-09-13

- 33 Swift tests pass. New coverage includes Chinese/English UTF-8 (with/without BOM), UTF-16 LE/BE, paragraph normalization, rejected empty/binary/oversized input, a real text-file read, per-task SwiftData persistence, answer/image/time preservation, and detachment from a historical rewrite even when the new question text is identical.
- In a separate app copy with an in-memory store, inspected the actual native import sheet and verified paste → Command-Return → question refill, disabled empty submission, and Escape cancellation without changing the question. The user's active writing session was left untouched.
- Text file decoding and disk reads are tested; native file-picker automation could navigate and preview the fixture but did not complete confirmation. This interaction still needs a normal user check. The app uses AppKit's asynchronous NSOpenPanel with text/Markdown content types.
- macOS version 1.3.1 (6), Universal arm64 + x86_64. No persistence schema change; Windows and Android remain 0.1.0.

# 1.3.0 validation · 2026-09-13

## macOS

- Xcode 26.6, macOS 26.6.2; deployment target macOS 15.
- 29 Swift tests pass, including independent concurrency, strict JSON, local median/spread, cancellation, provider routing, subprocess timeout/cancellation, SwiftData, real Vision OCR, mandatory immersion, rewrite persistence, missing credentials, and Chinese translation submission.
- Checked the actual native English II preparation and full-screen answer sheet. Chinese text enables Hand In. No live word counter appears.
- Found and fixed a real legacy Keychain call blocking the UI. Verified the final native Hand In flow immediately displays the missing DeepSeek API Key alert and retains the draft. Submissions now read memory only; explicit persistence/restoration happens in the background using a new data-protection Keychain item. Legacy development items are untouched.
- Universal arm64 + x86_64 Release build; signature and disk image checks recorded with published artifacts.

## Windows preview 0.1.0

- Built on Windows 11 x64 with .NET SDK 10.0.401. Native WPF executable; self-contained .NET runtime.
- Actual executable self-test passes median, spread, missing/duplicate reviewers, task scales, bundled rubrics, required JSON properties, serialization, and real Tesseract OCR of the repository's synthetic image.
- The real WPF preparation view was rendered at 1320 × 840 for visual inspection with an isolated temporary store. This is view rendering, not a manual live network grading test.
- Eight tasks, independent DeepSeek/Codex configuration, OCR confirmation, history, rewrite and basic statistics implemented. Windows Codex was not logged in on the test host, so no claim of Windows Codex live grading is made.

## Android preview 0.1.0

- Built using the user's installed Android Studio JBR and SDK: Gradle 8.13, AGP 8.13.2, compile/target SDK 35, minimum API 33.
- Five JUnit tests cover translation directions/scales, Chinese answer aggregation, disagreement, incomplete/duplicate judges, exact correction spans and missing-Key rejection.
- Signed release APK passes apksigner verification and installs successfully on the Android 15 ARM64 emulator. The app was built and launched from the installed Android Studio; the actual phone preparation screen was visually inspected. Interactive keyboard/rotation behavior has not been manually verified across physical devices.
- Two Android 15 device tests pass: real bundled ML Kit OCR of the synthetic image, and atomic local history with a Chinese rewrite that preserves the original.
- On-device ML Kit OCR is bundled for Chinese and Latin text. Three real DeepSeek providers are required; no demo grading is in the shipped app.

## Live provider scope

GPT-6 Astra/MAX completed a sample through the actual macOS Swift subprocess service. DeepSeek's official models endpoint was verified with the temporary user-supplied Key. That Key was not committed and has expired. A complete mixed three-provider paid grading session is not claimed as verified; users must enter their own current Key.

---

# WriteBench 1.1.0 — validation

2026-09-13, Xcode 26.6, Swift 6.

## Automated checks

17 Swift Testing tests pass:

- Median, reviewer spread thresholds, invalid scores and missing/duplicate judges.
- Word count, exam scales, correction deduplication and Codable round trip.
- Three graders overlap in time with the same original evidence.
- Cancellation, DeepSeek request isolation and JSON contract, HTTP/malformed/truncated response rejection, invalid correction spans.
- SwiftData sessions, images, rewrites and separate task drafts.
- Five bundled rubrics and actual Vision recognition of a generated English PNG.
- A preparation-stage draft cannot start its timer by typing or submit for grading; Start is required. An answering session cannot switch tasks. Leaving preserves the draft, and reopening requires Start again. Kaoyan/CET-6 hide the live count; IELTS retains it.
- Successful hand-in saves one complete review before returning to preparation.
- Failed grading returns to immersion with the original text intact.
- Rewriting enters the same immersive workspace and saves back to the source review, including after restart. Switching to an unrelated question detaches that rewrite association.

## Interactive checks

- The upgraded app loads the existing 1.0 SwiftData store and retains the earlier draft and reviews.
- Preparation has no editable answer, grade button, focus toggle or companion rail.
- Start / Command-Return enters the native full-screen answer view.
- Answer view visually inspected: no sidebar, exam tabs, greeting, mountains or formatting toolbar. The Kaoyan question appears beside a native lined answer surface; text aligns with the ruling. No live word count is displayed.
- Hand in completes the local demo grading and opens the complete review, with word count now visible in its metadata.
- Start rewrite on that review returns to the same immersive editor.
- Save and leave returns to preparation with the draft intact.
- Native OCR and Keychain/network service implementations remain unchanged, apart from restricting essay import to an active answering session.

## Scope limits

The ruled surface is a screen practice area, not an exact official answer-card reproduction. It never truncates a longer stored essay. The user can leave macOS full screen through system controls, but this never exposes another answer editor: the app remains in its minimal answering layout until hand-in or save-and-leave.

No API key was supplied; paid DeepSeek grading and live Keychain storage remain untested. HTTP behavior is covered with injected fixtures. Vision's automated fixture uses printed text and does not establish handwriting accuracy. Local ad-hoc signing is used; App Store signing and notarization are not included.
