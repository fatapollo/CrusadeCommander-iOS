import SwiftUI

@main
struct CrusadeCommanderApp: App {
    @StateObject private var serverSettings = ServerSettings()
    @StateObject private var auth = AuthStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(serverSettings)
                .environmentObject(auth)
                .preferredColorScheme(.dark)
        }
    }
}
