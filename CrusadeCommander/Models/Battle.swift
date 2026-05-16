import Foundation
import SwiftUI

@MainActor
final class AuthStore: ObservableObject {
    @Published var user: APIUser? = nil
    @Published var adminPasscodeEnabled: Bool = false
    @Published var loading: Bool = true

    func bootstrap() async {
        loading = true
        defer { loading = false }
        // Fetch /me and /config in parallel
        async let meTask = (try? APIClient.shared.me())
        async let cfgTask = (try? APIClient.shared.authConfig())
        let me = await meTask
        let cfg = await cfgTask
        self.user = me?.user
        self.adminPasscodeEnabled = me?.config_meta?.admin_passcode_enabled ?? cfg?.admin_passcode_enabled ?? false
    }

    func login(email: String, password: String) async throws {
        self.user = try await APIClient.shared.login(email: email, password: password)
    }

    func register(email: String, password: String, displayName: String, adminPasscode: String?) async throws {
        self.user = try await APIClient.shared.register(email: email, password: password, displayName: displayName, adminPasscode: adminPasscode)
    }

    func logout() async {
        try? await APIClient.shared.logout()
        self.user = nil
    }
}
