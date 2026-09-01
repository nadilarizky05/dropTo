import SwiftUI
import SwiftData


@main
struct dropToApp: App {
    
    //============================================================================
    // PHASE 1: PROPERTIES
    //============================================================================
    
    let dataService = DataService()
    @AppStorage("dropTo.colorScheme") private var colorSchemePreference: String = "auto"
    
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
    // PHASE 4: SCENE
    //============================================================================
    // INJECT DATASERVICE KE SELURUH APP, APPLY COLOR SCHEME
    
    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(dataService)
                .modelContainer(dataService.modelContainer)
                .preferredColorScheme(colorScheme)
        }
    }
}
