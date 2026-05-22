import SwiftUI

struct CampaignDashboardView: View {
    let campaignId: String

    @EnvironmentObject var auth: AuthStore

    @State private var campaign: APICampaign?
    @State private var role: CampaignRole?
    @State private var forces: [APIForce] = []
    @State private var battles: [APIBattle] = []
    @State private var error: String?
    @State private var loading = true
    @State private var tab: Tab = .overview

    enum Tab: String, CaseIterable { case overview = "Overview", forces = "Forces", battles = "Battles", members = "Members", map = "Map" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if loading {
                    ProgressView().tint(.accent).frame(maxWidth: .infinity).padding(.top, 60)
                } else if let c = campaign {
                    header(c)
                    lifecycleBanner(c)
                    tabsBar
                    switch tab {
                    case .overview: OverviewPanel(campaign: c, forces: forces, battles: battles)
                    case .forces:
                        ForcesPanel(
                            campaignId: campaignId,
                            forces: forces,
                            currentUserId: auth.user?.id ?? "",
                            isAdmin: role == .owner || role == .admin,
                            onChange: { Task { await loadAll() } }
                        )
                    case .battles:
                        BattlesPanel(
                            campaignId: campaignId,
                            campaignState: c.state,
                            forces: forces,
                            battles: battles,
                            defaultBattleSize: c.default_battle_size,
                            currentUserId: auth.user?.id ?? "",
                            isAdmin: role == .owner || role == .admin,
                            onChange: { Task { await loadAll() } }
                        )
                    case .members:
                        MembersPanel(
                            campaignId: campaignId,
                            currentUserId: auth.user?.id ?? "",
                            isAdmin: role == .owner || role == .admin
                        )
                    case .map:
                        SectorMapPanel(campaign: c, forces: forces)
                    }
                } else if let error {
                    ErrorBanner(message: error)
                }
                Spacer(minLength: 24)
            }
            .padding()
        }
        .background(Color.bg.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadAll() }
        .refreshable { await loadAll() }
    }

    private func header(_ c: APICampaign) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(c.name).font(.title2.bold())
            if !c.description.isEmpty {
                Text(c.description).font(.caption).foregroundStyle(Color.inkDim)
            }
            HStack(spacing: 8) {
                BadgeView(text: c.default_battle_size.rawValue, style: .dim)
                Text("\(c.phase_label) \(c.current_phase)").font(.caption2).foregroundStyle(Color.inkFade)
                BadgeView(text: c.state.rawValue.capitalized, style: c.state == .active ? .success : c.state == .setup ? .warning : .dim)
                if let role { BadgeView(text: "You are \(role.rawValue)", style: role == .owner ? .accent : role == .admin ? .warning : .dim) }
            }
        }
    }

    @ViewBuilder
    private func lifecycleBanner(_ c: APICampaign) -> some View {
        let isAdmin = role == .owner || role == .admin
        let activeForces = forces.filter { $0.is_active }.count
        if c.state == .setup {
            CardBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Campaign in setup").font(.subheadline.weight(.semibold)).foregroundStyle(Color.warningC)
                    Text("Invite players via Members, create Crusade Forces, then Start when ≥2 active forces are ready.")
                        .font(.caption).foregroundStyle(Color.inkDim)
                    Text("\(activeForces) active force\(activeForces == 1 ? "" : "s") — \(activeForces >= 2 ? "ready to start" : "need at least 2").")
                        .font(.caption2).foregroundStyle(Color.inkFade)
                    if isAdmin {
                        Button("⚔ Start Campaign") {
                            Task { await startCampaign() }
                        }
                        .buttonStyle(PrimaryButtonStyle(enabled: activeForces >= 2))
                        .disabled(activeForces < 2)
                    }
                }
            }
            .background(Color.warningC.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.warningC.opacity(0.3)))
        } else if c.state == .concluded {
            CardBox {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Campaign concluded").font(.subheadline.weight(.semibold)).foregroundStyle(Color.inkDim)
                    Text("No new battles can be recorded.").font(.caption).foregroundStyle(Color.inkFade)
                    if isAdmin {
                        Button("Reopen") {
                            Task { await reopen() }
                        }.buttonStyle(SecondaryButtonStyle())
                    }
                }
            }
        } else if c.state == .active && isAdmin {
            HStack(spacing: 8) {
                Text("✓ Campaign active").font(.caption).foregroundStyle(Color.successC)
                Text("\(activeForces) active force\(activeForces == 1 ? "" : "s")").font(.caption2).foregroundStyle(Color.inkFade)
                Spacer()
                Button("Conclude") { Task { await conclude() } }
                    .font(.caption).foregroundStyle(Color.inkFade)
            }
            .padding(10)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var tabsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Tab.allCases, id: \.self) { t in
                    Button {
                        tab = t
                    } label: {
                        Text(t.rawValue)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .foregroundStyle(tab == t ? Color.accent : Color.inkDim)
                            .overlay(
                                Rectangle()
                                    .fill(tab == t ? Color.accent : Color.clear)
                                    .frame(height: 2)
                                    .padding(.top, 28),
                                alignment: .top
                            )
                    }
                }
            }
        }
        .padding(.bottom, 4)
        .overlay(Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1), alignment: .bottom)
    }

    // MARK: - Network

    private func loadAll() async {
        loading = true; error = nil
        defer { loading = false }
        do {
            async let camp = APIClient.shared.getCampaign(campaignId)
            async let forcesT = APIClient.shared.listForces(campaignId)
            async let battlesT = APIClient.shared.listBattles(campaignId)
            let (c, f, b) = try await (camp, forcesT, battlesT)
            self.campaign = c.campaign
            self.role = c.role
            self.forces = f
            self.battles = b
        } catch let e as APIError { error = e.message }
        catch let e { self.error = e.localizedDescription }
    }

    private func startCampaign() async {
        do { campaign = try await APIClient.shared.startCampaign(campaignId) }
        catch let e as APIError { error = e.message } catch let e { self.error = e.localizedDescription }
    }
    private func conclude() async {
        do { campaign = try await APIClient.shared.concludeCampaign(campaignId) }
        catch let e as APIError { error = e.message } catch let e { self.error = e.localizedDescription }
    }
    private func reopen() async {
        do { campaign = try await APIClient.shared.reopenCampaign(campaignId) }
        catch let e as APIError { error = e.message } catch let e { self.error = e.localizedDescription }
    }
}

// MARK: - Overview panel

struct OverviewPanel: View {
    let campaign: APICampaign
    let forces: [APIForce]
    let battles: [APIBattle]

    var body: some View {
        let sorted = forces.sorted { ($0.victories, $0.battle_tally) > ($1.victories, $1.battle_tally) }
        VStack(spacing: 12) {
            CardBox {
                VStack(alignment: .leading, spacing: 10) {
                    Text("STANDINGS").font(.caption.weight(.semibold)).foregroundStyle(Color.inkFade)
                    if sorted.isEmpty {
                        Text("No crusade forces yet.").font(.caption).foregroundStyle(Color.inkFade)
                    } else {
                        ForEach(Array(sorted.enumerated()), id: \.element.id) { idx, f in
                            HStack {
                                Text("\(idx + 1)")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(idx == 0 ? Color.warningC : Color.inkFade)
                                    .frame(width: 24)
                                Circle().fill(Color(hex: f.color_hex)).frame(width: 10, height: 10)
                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(spacing: 4) {
                                        Text(f.name).font(.subheadline.weight(.medium))
                                        if !f.team.isEmpty { BadgeView(text: f.team, style: .accent) }
                                        if !f.is_active { BadgeView(text: "Dropped", style: .dim) }
                                    }
                                    Text(f.faction.isEmpty ? "—" : f.faction).font(.caption2).foregroundStyle(Color.inkFade)
                                }
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text("\(f.victories) W").font(.subheadline.weight(.bold)).foregroundStyle(Color.successC)
                                    Text("\(f.battle_tally) battles").font(.caption2).foregroundStyle(Color.inkFade)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }

            CardBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("CAMPAIGN").font(.caption.weight(.semibold)).foregroundStyle(Color.inkFade)
                    row("Phase", "\(campaign.phase_label) \(campaign.current_phase)")
                    row("Battle Size", campaign.default_battle_size.rawValue)
                    row("Battles", "\(battles.count)")
                    row("Forces", "\(forces.count)")
                }
            }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.caption).foregroundStyle(Color.inkFade)
            Spacer()
            Text(v).font(.caption.weight(.medium))
        }
    }
}
