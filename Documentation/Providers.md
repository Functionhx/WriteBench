# AI grading providers — 1.2

Defaults verified on 2026-09-13:

| Reviewer | Role | Provider | Model | Reasoning |
|---|---|---|---|---|
| A | Exam rubric | DeepSeek API | deepseek-v4-pro | max |
| B | Language | DeepSeek API | deepseek-v4-pro | max |
| C | Independent examiner | ChatGPT via official Codex CLI | gpt-6-astra | max |

Each role has its own provider selector. A submission freezes the selected configuration, sends identical original evidence to three independent requests, validates every response and aggregates the median locally. An error identifies the judge and provider. There is no fallback to another provider, partial aggregate, or mock result. Test fixtures are compiled only into WriteBenchTests. Legacy demo reviews remain stored but are hidden from History and excluded from analytics.

## Direct key entry

A user pastes a DeepSeek key and clicks **使用此 Key**. It works immediately from process memory, without accessing an old Keychain item. **在这台 Mac 上记住 Key** is optional and defaults off. No key is stored in UserDefaults, SwiftData, source, logs or a release package. Keychain reads and updates disallow authentication UI; an inaccessible item asks the user to enter the API key again. A failed optional save leaves the in-memory key usable and reports that it could not be remembered.

Missing keys block both typed and OCR-confirmed submissions before any provider receives the essay. The draft is saved; the user can continue answering or open Settings. Clearing a key or quitting clears the session key. Remembered keys follow macOS Keychain storage rules.

## Official Codex subprocess

The app detects common official installation paths or an explicitly supplied executable path. Check Connection runs `--version`, `exec --help`, and `login status`. Only a successful status stating ChatGPT login is accepted. It does not infer Pro/Plus, quota remaining, or model access from login status. A user who has not signed in runs `codex login` in Terminal. The app does not initiate a browser flow.

WriteBench never reads credential files, browser cookies or OAuth tokens, implements no OAuth refresh logic, and calls no ChatGPT web endpoints. It does not pass API credentials or custom provider URLs to the CLI. Codex owns its authentication and refresh. The installed official CLI on this development Mac is `/opt/homebrew/bin/codex`, version 0.154.0; the official `model/list` capability response and a live request confirmed `gpt-6-astra` with `max`.

Each call uses `codex exec --ephemeral --ignore-user-config --skip-git-repo-check --sandbox read-only --output-schema … --output-last-message … --json`, a unique private temporary directory, and prompt input through stdin. It never resumes a thread. CLI configuration fixes the official OpenAI provider and ChatGPT authentication. Shell, app, plugin, hook, browser, computer-use, memory, and multi-agent features are disabled for this writing-only task. Project instructions are disabled with `project_doc_max_bytes=0`; web search is disabled. No global Codex setting or login is modified.

The shared JSON Schema describes all required `JudgeResponse` and correction fields. Swift decodes only JSON from the final output file, not Markdown or regex-extracted prose. It validates score ranges, complete dimensions, summaries, revisions, and exact correction spans against the original essay. Provider/model/reasoning metadata is saved with each reviewer, with optional fields for older records.

The process runner uses private file-backed streams to avoid pipe deadlocks, output caps, a ten-minute deadline, cooperative cancellation and termination of the launched process. Temporary request and output files are removed on completion, failure or cancellation. Codex `--ephemeral` prevents rollout persistence; this does not imply that the remote provider has no retention policy. Raw subprocess output is not surfaced in user errors or application logs, avoiding accidental disclosure.

## Native distribution and storage

The personal/direct-distribution target uses native Swift Process and is not App Sandboxed: an inherited App Sandbox would prevent an independently installed CLI from using its own authentication store. This is not an App Store sandboxed build. Ad-hoc signing is used locally; Developer ID signing/notarization are still required for public distribution. No OS security setting is changed.

Existing installations continue using the complete prior SwiftData store and its external-image folder in the app's old container. New installations use `~/Library/Application Support/WriteBench/default.store`. The app does not reset or delete user data. Native import panels, Vision OCR and mandatory immersion remain intact.

## Verification

- Unit/integration tests cover role routing, no fallback, credential preflight, stdin/Schema/ephemeral flags, exact model and MAX settings, malformed JSON, quota mapping, real subprocess timeout and cancellation, legacy reviewer decoding, persistence, three-way concurrency and Vision OCR.
- A real GPT-6 Astra/MAX call through the actual Swift service returned complete JSON and one relevant correction on a synthetic invitation letter. Result: `codex-live-check.json`; log: `../codex-live-check.log`. This is a validation artifact, not a shipped sample score or user history record.
- A temporary user-supplied DeepSeek key successfully retrieved the official model list. A complete mixed-provider paid grading was not completed after the user requested direct key entry; a user can now enter a key in the normal UI and submit.
- Model access and quota errors remain explicit; nothing silently downgrades MAX or selects another model.

References: [Codex models](https://learn.chatgpt.com/docs/models), [non-interactive execution](https://learn.chatgpt.com/docs/non-interactive-mode), [DeepSeek chat completions](https://api-docs.deepseek.com/api/create-chat-completion/).
