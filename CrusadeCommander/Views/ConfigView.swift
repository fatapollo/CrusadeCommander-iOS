import SwiftUI

// AuthView: login / register against the configured server.

struct AuthView: View {
    @EnvironmentObject var serverSettings: ServerSettings
    @EnvironmentObject var auth: AuthStore

    enum Mode { case signIn, register }
    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var adminPasscode = ""
    @State private var showAdminField = false
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 6) {
                    Text("Crusade Commander").font(.largeTitle.bold()).foregroundStyle(Color.accent)
                    Text(serverSettings.serverURL?.host ?? "—").font(.caption).foregroundStyle(Color.inkFade)
                }.padding(.top, 60)

                CardBox {
                    VStack(spacing: 14) {
                        HStack(spacing: 0) {
                            tabButton("Sign In", isSelected: mode == .signIn) { mode = .signIn }
                            tabButton("Create Account", isSelected: mode == .register) { mode = .register }
                        }
                        .padding(4).background(Color.bgElevated).clipShape(RoundedRectangle(cornerRadius: 8))

                        if mode == .register {
                            field("Display Name", text: $displayName, keyboard: .default)
                        }
                        field("Email", text: $email, keyboard: .emailAddress, autocap: false)
                        secureField("Password", text: $password)

                        if mode == .register && auth.adminPasscodeEnabled {
                            if showAdminField {
                                secureField("Admin Passcode", text: $adminPasscode)
                                    .transition(.opacity)
                            } else {
                                Button("+ I have an admin passcode") { showAdminField = true }
                                    .font(.caption)
                                    .foregroundStyle(Color.inkFade)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        if let error { ErrorBanner(message: error) }

                        Button {
                            Task { await submit() }
                        } label: {
                            HStack {
                                if busy { ProgressView().tint(.white) }
                                Text(busy ? "…" : (mode == .signIn ? "Sign In" : "Create Account"))
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle(enabled: !busy))
                        .disabled(busy)

                        Button {
                            serverSettings.clearServer()
                        } label: {
                            Text("Use a different server")
                                .font(.caption)
                                .foregroundStyle(Color.inkFade)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 60)
        }
        .background(Color.bg.ignoresSafeArea())
    }

    private func tabButton(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accent : Color.clear)
                .foregroundStyle(isSelected ? Color.white : Color.inkDim)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func field(_ label: String, text: Binding<String>, keyboard: UIKeyboardType, autocap: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.medium)).foregroundStyle(Color.inkDim)
            TextField("", text: text)
                .textInputAutocapitalization(autocap ? .sentences : .never)
                .autocorrectionDisabled(!autocap)
                .keyboardType(keyboard)
                .padding(10)
                .background(Color.bgElevated)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(Color.ink)
        }
    }

    private func secureField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.medium)).foregroundStyle(Color.inkDim)
            SecureField("", text: text)
                .padding(10)
                .background(Color.bgElevated)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(Color.ink)
        }
    }

    private func submit() async {
        error = nil
        busy = true
        defer { busy = false }
        do {
            if mode == .signIn {
                try await auth.login(email: email, password: password)
            } else {
                try await auth.register(email: email, password: password, displayName: displayName, adminPasscode: showAdminField ? adminPasscode : nil)
            }
        } catch let e as APIError {
            error = e.message
        } catch let e {
            error = e.localizedDescription
        }
    }
}
