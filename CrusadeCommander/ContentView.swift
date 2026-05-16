import SwiftUI

struct ContentView: View {
    @EnvironmentObject var serverSettings: ServerSettings
    @EnvironmentObject var auth: AuthStore
    @State private var bootstrapping = true

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()

            if !serverSettings.isConfigured {
                ServerConfigView()
            } else if bootstrapping || auth.loading {
                ProgressView().tint(.accent)
            } else if auth.user == nil {
                AuthView()
            } else {
                NavigationStack {
                    CampaignListView()
                }
            }
        }
        .task {
            // Re-configure APIClient when the server URL changes; bootstrap auth state once
            await ensureBoot()
        }
        .onChange(of: serverSettings.serverURL) { _, newValue in
            if let url = newValue {
                APIClient.shared.setBaseURL(url)
            } else {
                Task { await auth.logout() }
            }
            Task { await ensureBoot() }
        }
    }

    private func ensureBoot() async {
        bootstrapping = true
        defer { bootstrapping = false }
        if let url = serverSettings.serverURL {
            APIClient.shared.setBaseURL(url)
            await auth.bootstrap()
        }
    }
}
