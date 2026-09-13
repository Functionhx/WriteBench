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
