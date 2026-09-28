import SwiftUI
import SwiftData

@main
struct dropToApp: App {
    
    //============================================================================
    // PHASE 1: PROPERTIES
    //============================================================================
    
    let dataService = DataService()
    @AppStorage("dropTo.colorScheme") private var colorSchemePreference: String = "auto"
    
    // DEEP LINK COORDINATOR (UNTUK WIDGET)
    @State private var deepLinkCoordinator = DeepLinkCoordinator()
    @Environment(\.scenePhase) private var scenePhase
    
    //============================================================================
    // PHASE 2: INITIALIZER
    //============================================================================
    // JALANKAN MIGRASI DARI USERDEFAULTS KE SWIFTDATA (SEKALI AJA DI FIRST LAUNCH)
    
    init() {
        let service = dataService
        Task { @MainActor in
            MigrationService.migrateFromUserDefaults(to: service)
        }
    }
    
    //============================================================================
    // PHASE 3: COMPUTED PROPERTY: COLOR SCHEME
    //============================================================================
    // NIL = AUTO (IKUTIN SYSTEM), .LIGHT = LIGHT, .DARK = DARK
    
    private var colorScheme: ColorScheme? {
        switch colorSchemePreference {
        case "light": return .light
        case "dark": return .dark
        default: return nil  // "auto" = ikutin system
        }
    }
    
    //============================================================================
    // SCENE
    //============================================================================
    // INJECT DATASERVICE KE SELURUH APP, APPLY COLOR SCHEME, HANDLE DEEP LINKS
    
    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(dataService)
                .modelContainer(dataService.modelContainer)
                .preferredColorScheme(colorScheme)
                .environment(deepLinkCoordinator)
                .onOpenURL { url in
                    print("🔗 Deep link received: \(url)")
                    deepLinkCoordinator.handle(url: url)
                }
        }
        // TIAP APP AKTIF LAGI: SYNC ULANG WIDGET
        // (MISAL USER BARU KASIH IZIN PHOTOS, ATAU HAPUS FOTO COVER DI APP PHOTOS)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                dataService.syncWidget()
            }
        }
    }
}
