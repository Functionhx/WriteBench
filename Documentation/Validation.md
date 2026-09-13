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
