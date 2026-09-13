# WriteBench for Android

Native Android Views / Java 17. A phone layout with exam cards, horizontally scrolling task tabs, a pinned Start button, and a single immersive answering screen. Android 13 or newer.

Supports eight tasks: Kaoyan English I small/large essays, English I/II translation, CET-6 writing/translation, and IELTS Academic Tasks 1/2. All practice uses three independent DeepSeek V4 Pro / MAX graders and local median aggregation. No fake scores and no silent fallback. The API Key lives only in process memory.

Image OCR uses bundled ML Kit Chinese + Latin recognition on-device. Review the original image above editable text, move through pages, and confirm before grading. For a photo containing both question and answer, import it for each purpose and retain only the relevant text in each confirmation step. Diagrams require manually transcribed data. Handwriting accuracy varies; always correct OCR first.

Drafts, complete reviewer JSON, originals, corrected versions and rewrites are stored as atomic JSON files in app-private storage. Rotation preserves an active session; closing the process preserves the draft but clears the API Key. Statistics are a compact summary within History. Codex is available on desktop only.

## Android Studio

Open this folder in Android Studio and allow Gradle sync. This project was built using the user's installed Android Studio JBR and SDK, Gradle 8.13, AGP 8.13.2, compile/target SDK 35. No web runtime.

```sh
./gradlew :app:testDebugUnitTest :app:assembleDebug
```

For a signed release, provide your own keystore through environment variables (never commit it):

```text
WRITEBENCH_KEYSTORE          absolute path to a private keystore
WRITEBENCH_SIGNING_PASSWORD  keystore / key password
key alias                   writebench
```

Then run `./gradlew :app:assembleRelease`. The APK is under `app/build/outputs/apk/release/`. The public release uses a stable privately retained release key, not Android's debug certificate.

See [third-party notices](../../THIRD_PARTY_NOTICES.md).
