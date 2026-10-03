import SwiftUI
import SwiftData

@main
struct dropToApp: App {
    let dataService = DataService()
    @AppStorage("dropTo.colorScheme") private var colorSchemePreference: String = "auto"
    @AppStorage("dropTo.hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var shouldPresentNewAlbum = false

    @State private var deepLinkCoordinator = DeepLinkCoordinator()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let service = dataService
        Task { @MainActor in
            MigrationService.migrateFromUserDefaults(to: service)
        }
    }

    private var colorScheme: ColorScheme? {
        switch colorSchemePreference {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if hasSeenOnboarding {
                    RootTabView(showNewAlbumOnAppear: shouldPresentNewAlbum)
                } else {
                    OnboardingView {
                        shouldPresentNewAlbum = true
                        hasSeenOnboarding = true
                    }
                }
            }
            .environmentObject(dataService)
            .modelContainer(dataService.modelContainer)
            .preferredColorScheme(colorScheme)
            .environment(deepLinkCoordinator)
            .onOpenURL { url in
                print("🔗 Deep link received: \(url)")
                deepLinkCoordinator.handle(url: url)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                dataService.syncWidget()
                Task { await dataService.purgeExpiredDeletedItems() }
            }
        }
    }
}
