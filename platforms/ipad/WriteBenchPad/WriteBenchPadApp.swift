import SwiftUI
import SwiftData

@main struct WriteBenchPadApp: App {
    @State private var store = PadStore()
    private let container: ModelContainer?
    private let failure: String?
    init() {
        do {
            let test = ProcessInfo.processInfo.arguments.contains("--ui-testing") || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            container = try ModelContainer(for: EssaySession.self, WritingDraft.self, SavedQuestion.self, EssayFolderMetadata.self, ReviewCard.self, configurations: ModelConfiguration(isStoredInMemoryOnly: test))
            failure = nil
        } catch { container = nil; failure = error.localizedDescription }
    }
    var body: some Scene {
        WindowGroup {
            if let container { PadWorkspace(store: store).modelContainer(container).tint(WB.blue) }
            else { ContentUnavailableView("无法打开本地资料", systemImage: "externaldrive.badge.exclamationmark", description: Text(failure ?? "请重新启动应用。已有资料未被重置。")) }
        }
    }
}
