import SwiftUI
import SwiftData

@main struct WriteBenchApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycle.self) private var lifecycle
    @State private var writingStore = WritingStore()
    private let container: ModelContainer?
    private let storageError: String?
    private static var isTestHost: Bool {
        #if DEBUG
        NSClassFromString("XCTestCase") != nil || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        #else
        false
        #endif
    }
    init() {
        do {
            // Hosted tests must never open or migrate the user's active database.
            if Self.isTestHost {
                container = try ModelContainer(for: EssaySession.self, WritingDraft.self, SavedQuestion.self, EssayFolderMetadata.self,
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true))
                storageError = nil
                return
            }
            // Keep the previous sandbox database and external image storage together on upgrade.
            let fm = FileManager.default
            let legacy = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Containers/com.chen.WriteBench/Data/Library/Application Support/default.store")
            let folder = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("WriteBench", isDirectory: true)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let storeURL = fm.fileExists(atPath: legacy.path) ? legacy : folder.appendingPathComponent("default.store")
            container = try ModelContainer(for: EssaySession.self, WritingDraft.self, SavedQuestion.self, EssayFolderMetadata.self, configurations: ModelConfiguration(url: storeURL))
            storageError = nil
            if UserDefaults.standard.string(forKey: "deepSeekModel") == "deepseek-v4-flash" { UserDefaults.standard.set(DeepSeekClient.defaultModel, forKey: "deepSeekModel") }
        }
        catch { container = nil; storageError = error.localizedDescription }
    }
    var body: some Scene {
        Window("WriteBench", id: "workspace") {
            if let container { WorkspaceView(store: writingStore).modelContainer(container).preferredColorScheme(.light).task { lifecycle.writingStore = writingStore; if !Self.isTestHost { await DeepSeekCredentials.restoreRememberedKey() } } }
            else { VStack(spacing: 18) { Text("WriteBench could not open local storage").font(.title2); Text(storageError ?? "Unknown storage error").textSelection(.enabled); Text("Your files have not been reset. Restart the app or check available disk space.").foregroundStyle(.secondary) }.padding(40).frame(width: 600, height: 300) }
        }
        .windowStyle(.hiddenTitleBar).windowToolbarStyle(.unified).defaultSize(width: 1440, height: 900)
        .commands { CommandGroup(replacing: .newItem) {} }
        Settings { SettingsView().frame(width: 780, height: 760).background(WB.canvas).preferredColorScheme(.light) }
    }
}
