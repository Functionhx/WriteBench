# WriteBench for Windows 1.9.3

Native WPF / C# application, .NET 10, self-contained Windows x64. Extract the entire ZIP and run `WriteBench.exe`; keep all adjacent files and OCR data together. No separate .NET installation is required.

Eight writing and translation tasks include immersive answering, local drafts/history/rewrite, multi-page OCR confirmation, independent grading, three-judge median aggregation, review, mistakes and statistics. Kaoyan and CET-6 hide live word counts.

## Answer sheet and grading

Spaces are preserved. Tab inserts four spaces. Left/center/right alignment applies to the current logical line or selected lines, with native undo support. Title and signature can be aligned independently. Clicking Submit immediately pauses the writing timer, including missing-key, cancellation and failed-review paths. Resume answering explicitly to restart it.

DeepSeek streams progress separately for each judge. A result is accepted only after a complete stream and field validation; optional error lists can be missing/null and numeric strings are accepted. Invalid result format gets at most one format-repair retry; authorization failures and interrupted output are not retried. No partial result becomes a final score or history entry.

Kaoyan translation reviews include source-anchored meaning groups, vocabulary, concrete translation techniques, a complete reference translation and assembly notes. English I preserves numbered source segments; English II teaches passage sentences. Older reports without teaching fields still open.

## Credentials and Codex

Remember Key is enabled by default. DeepSeek credentials are encrypted using Windows DPAPI for the current Windows account, separately from drafts and history. Disabling Remember removes the saved credential and retains the active key in memory only. Forget removes both. Save and check connection distinguishes storing a key from validating it against DeepSeek.

Each judge can independently use DeepSeek or the official locally installed `codex.exe`. Defaults: A/B DeepSeek, C Codex. Run official `codex login` once using ChatGPT; WriteBench checks login status without reading authentication files. Specify the executable path if discovery fails. No subscription tier is inferred.

OCR uses bundled Tesseract English/Simplified Chinese models. On a clean Windows installation, install the [Microsoft Visual C++ x64 Redistributable](https://aka.ms/vs/17/release/vc_redist.x64.exe) if OCR reports a missing native library; the self-contained .NET runtime does not include this separate prerequisite. Images and OCR remain local; only confirmed text is submitted. Correct recognition carefully, especially handwriting.

## Validation and limitations

The release workflow publishes on a real GitHub-hosted Windows runner, starts the published executable, checks domain/scoring/rejection, format retries, interrupted streams, DPAPI persistence/forgetting, timer pause/resume, actual WPF editor alignment/undo/Tab/progress, and real OCR. It also validates the 66-question full-text CET-6 bank, transactional imports and native library screen, and renders preparation, settings, answer-sheet and CET-6-library screens for visual inspection. Tests use deterministic provider fixtures, not paid live grading requests.

This automated coverage does not replace manual Windows 11 checks of screen scaling, physical keyboard shortcuts, window switching, network/proxy configurations, or a live grading account. The portable application is not Authenticode-signed. Windows provides eight task presets and the shared 2022–2026 CET-6 full-text bank (33 writing and 33 translation questions). Other expanded macOS question banks and the unified synthesized review are not yet included.

## Build

On Windows with .NET 10 SDK:

```powershell
dotnet publish WriteBench/WriteBench.csproj -c Release -r win-x64 --self-contained true -o publish
# For real OCR, copy Documentation/TestImages/ocr-sample-1.png from repo to publish/ocr-fixture.png.
$p = Start-Process ./publish/WriteBench.exe -ArgumentList '--self-test' -Wait -PassThru
if ($p.ExitCode -ne 0) { Get-Content ./publish/self-test-error.txt; exit 1 }
```

`--render-preview` renders three WPF screens using isolated temporary data. Local user data lives under `%LOCALAPPDATA%/WriteBench`. See [third-party notices](../../THIRD_PARTY_NOTICES.md).
