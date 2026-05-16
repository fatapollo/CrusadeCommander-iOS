import SwiftUI

struct CampaignListView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var serverSettings: ServerSettings
    @State private var campaigns: [APICampaign] = []
    @State private var loading = true
    @State private var error: String?
    @State private var inviteCode: String = ""
    @State private var showWizard = false
    @State private var pendingAcceptCode: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                joinCard

                if loading {
                    ProgressView().tint(.accent).frame(maxWidth: .infinity).padding(.top, 40)
                } else if let error {
                    ErrorBanner(message: error)
                } else if campaigns.isEmpty {
                    EmptyStateView(icon: "⚔", title: "No campaigns yet", subtitle: "Create one above, or paste an invite code shared with you.")
                } else {
                    section("In Setup", filter: { $0.state == .setup })
                    section("Active", filter: { $0.state == .active })
                    section("Concluded", filter: { $0.state == .concluded })
                }

                Spacer(minLength: 20)
            }
            .padding()
        }
        .background(Color.bg.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Text(auth.user?.display_name ?? auth.user?.email ?? "")
                    .font(.caption).foregroundStyle(Color.inkFade)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if auth.user?.is_site_admin == true {
                        Text("Site Admin — manage from web")
                    }
                    Button("Change server", role: .destructive) {
                        Task { await auth.logout(); serverSettings.clearServer() }
                    }
                    Button("Sign out") { Task { await auth.logout() } }
                } label: {
                    Image(systemName: "person.circle").foregroundStyle(Color.accent)
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showWizard) {
            NavigationStack { SetupWizardView(onCreated: { c in
                showWizard = false
                Task { await load() }
            }) }
        }
        .sheet(item: Binding(
            get: { pendingAcceptCode.map { CodeWrapper(code: $0) } },
            set: { pendingAcceptCode = $0?.code })
        ) { wrapper in
            NavigationStack { GenerateBattleMapAcceptInviteView(code: wrapper.code, onAccepted: {
                pendingAcceptCode = nil
                Task { await load() }
            }) }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Your Campaigns").font(.title.bold())
                if !loading {
                    Text(campaigns.isEmpty ? "Create one or join with an invite code." : "\(campaigns.count) campaign\(campaigns.count == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(Color.inkFade)
                }
            }
            Spacer()
            Button { showWizard = true } label: {
                Label("New", systemImage: "plus")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.accent).foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
    }

    private var joinCard: some View {
        CardBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Have an invite code?").font(.subheadline.weight(.semibold))
                HStack {
                    TextField("ABCD1234EF", text: $inviteCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(.subheadline, design: .monospaced))
                        .padding(10)
                        .background(Color.bgElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(Color.ink)
                    Button("Join") {
                        let raw = inviteCode.trimmingCharacters(in: .whitespaces).uppercased()
                        let match = raw.range(of: "INVITE/", options: .regularExpression)
                        let code: String
                        if let m = match {
                            code = String(raw[m.upperBound...]).replacingOccurrences(of: "/", with: "")
                        } else {
                            code = raw
                        }
                        if !code.isEmpty { pendingAcceptCode = code }
                    }
                    .buttonStyle(PrimaryButtonStyle(enabled: !inviteCode.isEmpty))
                    .frame(width: 100)
                    .disabled(inviteCode.isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, filter: (APICampaign) -> Bool) -> some View {
        let items = campaigns.filter(filter)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.inkFade)
                ForEach(items) { c in
                    NavigationLink(destination: CampaignDashboardView(campaignId: c.id)) {
                        campaignCard(c)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func campaignCard(_ c: APICampaign) -> some View {
        CardBox {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(c.name).font(.headline)
                    Spacer()
                    BadgeView(text: c.state.rawValue.capitalized, style: c.state == .active ? .success : c.state == .setup ? .warning : .dim)
                }
                if !c.description.isEmpty {
                    Text(c.description).font(.caption).foregroundStyle(Color.inkDim).lineLimit(2)
                }
                HStack(spacing: 12) {
                    Text(c.default_battle_size.rawValue).font(.caption2).foregroundStyle(Color.inkFade)
                    Text("\(c.phase_label) \(c.current_phase)").font(.caption2).foregroundStyle(Color.inkFade)
                }
            }
        }
    }

    private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do {
            campaigns = try await APIClient.shared.listCampaigns()
        } catch let e as APIError {
            error = e.message
        } catch let e {
            error = e.localizedDescription
        }
    }
}

private struct CodeWrapper: Identifiable { let code: String; var id: String { code } }
