import SwiftUI

// ServerConfigView: first-launch / sign-out screen for choosing which
// Crusade Commander server to connect to. The user can self-host the Node.js
// backend and point the app at their domain.

struct ServerConfigView: View {
    @EnvironmentObject var serverSettings: ServerSettings
    @State private var urlText: String = ""
    @State private var probing = false
    @State private var error: String?

    private static let presets: [(label: String, url: String)] = [
        ("Local dev (simulator)", "http://localhost:3000"),
        ("Local dev (real iPhone — replace IP)", "http://192.168.1.100:3000"),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("Crusade Commander")
                        .font(.largeTitle.bold())
                        .foregroundStyle(Color.accent)
                    Text("Choose a server")
                        .font(.subheadline)
                        .foregroundStyle(Color.inkDim)
                }.padding(.top, 60)

                CardBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Server URL").font(.subheadline.weight(.semibold))
                        TextField("https://crusade.example.com", text: $urlText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .padding(10)
                            .background(Color.bgElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(Color.ink)
                        Text("Include scheme (http:// or https://). You can self-host the backend — point at your own server here.")
                            .font(.caption2)
                            .foregroundStyle(Color.inkFade)

                        if let error { ErrorBanner(message: error) }

                        Button {
                            Task { await connect() }
                        } label: {
                            HStack {
                                if probing { ProgressView().tint(.white) }
                                Text(probing ? "Connecting…" : "Connect")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle(enabled: !probing && !urlText.isEmpty))
                        .disabled(probing || urlText.isEmpty)

                        Divider().background(Color.white.opacity(0.05)).padding(.vertical, 4)

                        Text("Quick presets")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.inkFade)
                        ForEach(Self.presets, id: \.url) { p in
                            Button {
                                urlText = p.url
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(p.label).font(.caption.weight(.medium)).foregroundStyle(Color.ink)
                                        Text(p.url).font(.caption2).foregroundStyle(Color.inkFade)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Color.inkFade)
                                }
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal)

                Spacer(minLength: 40)
            }
        }
        .background(Color.bg.ignoresSafeArea())
    }

    private func connect() async {
        error = nil
        probing = true
        defer { probing = false }
        let trimmed = urlText.trimmingCharacters(in: .whitespaces)
        guard var url = URL(string: trimmed) else {
            error = "That doesn't look like a URL."
            return
        }
        let s = url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if let cleaned = URL(string: s) { url = cleaned }
        APIClient.shared.setBaseURL(url)
        do {
            struct Health: Decodable { let ok: Bool }
            let _: Health = try await APIClient.shared.get("/health")
            serverSettings.serverURL = url
        } catch let e as APIError {
            self.error = "Couldn't reach server: \(e.message)"
        } catch let e {
            self.error = "Couldn't reach server: \(e.localizedDescription)"
        }
    }
}
