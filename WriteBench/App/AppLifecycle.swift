import AppKit

@MainActor final class AppLifecycle: NSObject, NSApplicationDelegate {
    weak var writingStore: WritingStore?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store = writingStore else { return .terminateNow }
        store.tick(); store.persistDraft()
        guard store.isGrading, let task = store.gradingTask else { return .terminateNow }
        store.cancelGrading()
        Task {
            await task.value
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
