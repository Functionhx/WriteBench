# WriteBench for Windows

A native WPF / C# application, targeting .NET 10 and distributed as a self-contained Windows x64 folder. Extract the ZIP and run `WriteBench.exe`; keep the adjacent files and OCR data together. Windows 11 is the tested platform.

The eight writing and translation tasks share a mandatory immersive answer sheet, local draft/history/rewrite persistence, multi-page OCR confirmation, independent JSON grading, local median aggregation, review, mistakes and simple statistics. Kaoyan and CET-6 hide live word counts.

DeepSeek uses a user-entered Key held only in process memory. Each judge can independently use DeepSeek or the official locally installed `codex.exe`. Defaults are A/B = DeepSeek and C = Codex. Use official `codex login` once; WriteBench checks `codex login status` and never reads credential files. Set the executable path if automatic discovery fails. No desktop Codex application or subscription tier is inferred.

OCR uses Tesseract with bundled English / Simplified Chinese models, because the unpackaged portable app does not have the package identity required by Windows' OCR API. Images and OCR stay local; only confirmed text is sent for grading. Handwriting recognition needs careful correction. For mixed question/answer photos, retain the relevant text when importing each purpose.

## Build

Install .NET 10 SDK on Windows:

```powershell
dotnet publish WriteBench/WriteBench.csproj -c Release -r win-x64 --self-contained true -o publish
$p = Start-Process ./publish/WriteBench.exe -ArgumentList '--self-test' -Wait -PassThru
if ($p.ExitCode -ne 0) { Get-Content ./publish/self-test-error.txt; exit 1 }
```

To include a real OCR check, copy `Documentation/TestImages/ocr-sample-1.png` from the repository to `publish/ocr-fixture.png` before running the self-test. `--render-preview` renders the actual WPF preparation view to `windows-preview.png` using an isolated temporary store; it does not seed user history.

Local files are under `%LOCALAPPDATA%/WriteBench`. This preview is not Authenticode-signed. Its independent version is 0.1.0; the macOS application remains 1.3.0.

See [third-party notices](../../THIRD_PARTY_NOTICES.md).
