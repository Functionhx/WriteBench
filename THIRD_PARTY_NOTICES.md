# Third-party components

WriteBench uses platform-native frameworks. Windows and Android add local OCR components; these do not send images to a grading service.

| Component | Use | Upstream / license |
| --- | --- | --- |
| .NET / WPF 10 | Windows app and self-contained runtime | [dotnet/wpf](https://github.com/dotnet/wpf), [dotnet/runtime](https://github.com/dotnet/runtime) · MIT and associated notices |
| Tesseract .NET 5.2.0 | Windows OCR wrapper and native binaries | [charlesw/tesseract](https://github.com/charlesw/tesseract) · Apache-2.0 |
| Tesseract / tessdata_fast | Local OCR and English / Chinese model data | [tesseract-ocr](https://github.com/tesseract-ocr) · Apache-2.0; model license included in `platforms/windows/WriteBench/tessdata/LICENSE` |
| Leptonica | Tesseract image processing dependency | [DanBloomberg/leptonica](https://github.com/DanBloomberg/leptonica) · BSD-style license |
| Google ML Kit text recognition | Android on-device Chinese / Latin OCR | [ML Kit terms](https://developers.google.com/ml-kit/terms) and dependency notices |
| Gradle / Android Gradle Plugin | Android build tools | [Gradle](https://github.com/gradle/gradle), [Android tools](https://android.googlesource.com/platform/tools/base/) · Apache-2.0 |

The Windows native OCR dependency requires Microsoft Visual C++ 2015–2022 x64 runtime. If it is absent, install the [official Microsoft redistributable](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist). The application remains usable for typed practice without OCR. No runtime installer executes automatically.

DeepSeek and OpenAI Codex are external, user-configured services. Codex is not bundled, and WriteBench does not redistribute or access its authentication data. Each provider retains its own terms and billing/allowance rules.

Exam names identify supported practice categories. Navigation symbols are original category illustrations or native system symbols, not official exam logos.
