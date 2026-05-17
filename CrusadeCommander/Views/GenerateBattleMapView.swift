import SwiftUI

// ForceDetailView + AcceptInviteView (legacy filename retained).

struct ForceDetailView: View {
    let campaignId: String
    let forceId: String

    @State private var force: APIForce?
    @State private var units: [APIUnit] = []
    @State private var loading = true
    @State private var error: String?
    @State private var showAddUnit = false
    @State private var showReq = false
    @State private var unitPendingDelete: APIUnit?
    @State private var deleting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if loading {
                    ProgressView().tint(.accent).frame(maxWidth: .infinity).padding(.top, 40)
                } else if let f = force {
                    header(f)
                    statsGrid(f)
                    Button { showReq = true } label: {
                        HStack {
                            Label("Requisitions", systemImage: "arrow.triangle.2.circlepath")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(f.requisition_points) RP").font(.caption.weight(.bold)).foregroundStyle(Color.accent)
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Color.inkFade)
                        }
                        .padding(12)
                        .background(Color.bgElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    HStack {
                        Text("Order of Battle").font(.subheadline.weight(.semibold))
                        Spacer()
                        Button { showAddUnit = true } label: {
                            Label("Add Unit", systemImage: "plus")
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Color.accent).foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                    }
                    if units.isEmpty {
                        EmptyStateView(icon: "◐", title: "No units yet", subtitle: "Add units to build the Order of Battle.")
                    } else {
                        ForEach(units) { u in unitRow(u) }
                    }
                } else if let error {
                    ErrorBanner(message: error)
                }
            }
            .padding()
        }
        .background(Color.bg.ignoresSafeArea())
        .navigationTitle(force?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showAddUnit) {
            NavigationStack {
                AddUnitSheet(campaignId: campaignId, forceId: forceId, onDone: {
                    showAddUnit = false; Task { await load() }
                })
            }
        }
        .sheet(isPresented: $showReq) {
            NavigationStack {
                RequisitionsSheet(campaignId: campaignId, forceId: forceId,
                                  force: force, units: units,
                                  onChange: { Task { await load() } })
            }
        }
        .alert("Delete Unit", isPresented: Binding(get: { unitPendingDelete != nil }, set: { if !$0 { unitPendingDelete = nil } }), presenting: unitPendingDelete) { u in
            Button("Delete", role: .destructive) { Task { await deleteUnit(u) } }
            Button("Cancel", role: .cancel) { unitPendingDelete = nil }
        } message: { u in
            Text("Permanently delete \"\(u.name)\" from the Order of Battle? This cannot be undone.")
        }
    }

    private func header(_ f: APIForce) -> some View {
        HStack(spacing: 12) {
            Circle().fill(Color(hex: f.color_hex)).frame(width: 48, height: 48)
                .overlay(Text(f.name.prefix(1).uppercased()).font(.title3.weight(.bold)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(f.name).font(.title3.weight(.bold))
                    if !f.team.isEmpty { BadgeView(text: f.team, style: .accent) }
                }
                Text("\(f.faction.isEmpty ? "—" : f.faction)\(f.player_name.isEmpty ? "" : " · \(f.player_name)")")
                    .font(.caption).foregroundStyle(Color.inkDim)
            }
        }
    }

    private func statsGrid(_ f: APIForce) -> some View {
        let used = units.filter { $0.is_active }.reduce(0) { $0 + $1.points_cost }
        return HStack(spacing: 8) {
            stat("Supply", "\(used)/\(f.supply_limit)", sub: "\(f.supply_limit - used) free")
            stat("RP", "\(f.requisition_points)/10", accent: .accent)
            stat("Battles", "\(f.battle_tally)")
            stat("Wins", "\(f.victories)", accent: .successC)
        }
    }

    private func stat(_ label: String, _ value: String, sub: String? = nil, accent: Color = .ink) -> some View {
        CardBox {
            VStack(spacing: 2) {
                Text(value).font(.headline.weight(.bold)).foregroundStyle(accent)
                Text(label).font(.caption2).foregroundStyle(Color.inkFade)
                if let sub {
                    Text(sub).font(.system(size: 9)).foregroundStyle(Color.inkFade)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func unitRow(_ u: APIUnit) -> some View {
        CardBox {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(u.name).font(.subheadline.weight(.semibold))
                        if u.is_character { BadgeView(text: "Character", style: .accent) }
                        if u.is_titanic { BadgeView(text: "Titanic", style: .warning) }
                        if !u.is_active { BadgeView(text: "Destroyed", style: .danger) }
                    }
                    Text("\(u.datasheet) · \(u.points_cost) pts · \(u.rank.rawValue)")
                        .font(.caption2).foregroundStyle(Color.inkFade)
                }
                Spacer()
                HStack(spacing: 12) {
                    miniStat("XP", "\(u.xp)", color: .accent)
                    miniStat("CP", "\(u.crusade_points)", color: u.crusade_points < 0 ? .dangerC : .ink)
                    miniStat("Kills", "\(u.units_destroyed)", color: .ink)
                }
            }
        }
        .opacity(u.is_active ? 1 : 0.5)
        .contextMenu {
            Button(role: .destructive) { unitPendingDelete = u } label: {
                Label("Delete Unit", systemImage: "trash")
            }
        }
    }

    private func miniStat(_ label: String, _ value: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.caption.weight(.bold)).foregroundStyle(color)
            Text(label).font(.system(size: 9)).foregroundStyle(Color.inkFade)
        }
    }

    private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do {
            async let units = APIClient.shared.listUnits(campaignId, forceId: forceId)
            async let forces = APIClient.shared.listForces(campaignId)
            let (u, f) = try await (units, forces)
            self.units = u
            self.force = f.first { $0.id == forceId }
        } catch let e as APIError { error = e.message }
        catch let e { self.error = e.localizedDescription }
    }

    private func deleteUnit(_ u: APIUnit) async {
        deleting = true; error = nil
        defer { deleting = false; unitPendingDelete = nil }
        do {
            try await APIClient.shared.deleteUnit(campaignId, unitId: u.id)
            await load()
        } catch let e as APIError { error = e.message }
        catch let e { self.error = e.localizedDescription }
    }
}

struct AddUnitSheet: View {
    @Environment(\.dismiss) private var dismiss
    let campaignId: String
    let forceId: String
    let onDone: () -> Void

    @State private var name = ""
    @State private var datasheet = ""
    @State private var pointsCost = 100
    @State private var equipment = ""
    @State private var isCharacter = false
    @State private var isTitanic = false
    @State private var isEpicHero = false
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                CardBox {
                    VStack(alignment: .leading, spacing: 12) {
                        labeled("Unit Name (unique)") { input($name) }
                        labeled("Datasheet") { input($datasheet) }
                        labeled("Points Cost") {
                            TextField("100", value: $pointsCost, format: .number)
                                .keyboardType(.numberPad)
                                .padding(10).background(Color.bgElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        labeled("Equipment") {
                            TextField("", text: $equipment, axis: .vertical)
                                .lineLimit(1...3)
                                .padding(10).background(Color.bgElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        Toggle("Character", isOn: $isCharacter)
                        Toggle("Titanic", isOn: $isTitanic)
                        Toggle("Epic Hero (no XP gain)", isOn: $isEpicHero)
                    }
                }
                if let error { ErrorBanner(message: error) }
                Button {
                    Task { await create() }
                } label: {
                    HStack {
                        if busy { ProgressView().tint(.white) }
                        Text(busy ? "Adding…" : "Add Unit")
                    }
                }.buttonStyle(PrimaryButtonStyle(enabled: !busy && !name.isEmpty)).disabled(busy || name.isEmpty)
            }.padding()
        }
        .background(Color.bg.ignoresSafeArea())
        .navigationTitle("New Unit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
    }

    private func labeled<V: View>(_ label: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.medium)).foregroundStyle(Color.inkDim)
            content()
        }
    }
    private func input(_ binding: Binding<String>) -> some View {
        TextField("", text: binding)
            .padding(10).background(Color.bgElevated)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    private func create() async {
        busy = true; error = nil
        defer { busy = false }
        do {
            _ = try await APIClient.shared.createUnit(
                campaignId, forceId: forceId,
                name: name.trimmingCharacters(in: .whitespaces),
                datasheet: datasheet, pointsCost: pointsCost,
                equipment: equipment, isCharacter: isCharacter,
                isTitanic: isTitanic, isEpicHero: isEpicHero
            )
            onDone()
        } catch let e as APIError { error = e.message }
        catch let e { self.error = e.localizedDescription }
    }
}

// MARK: - Accept invite

struct GenerateBattleMapAcceptInviteView: View {
    @Environment(\.dismiss) private var dismiss
    let code: String
    let onAccepted: () -> Void

    @State private var preview: APIInvitePreview?
    @State private var loading = true
    @State private var accepting = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if loading {
                    ProgressView().tint(.accent).frame(maxWidth: .infinity).padding(.top, 40)
                } else if let p = preview {
                    CardBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("CRUSADE INVITATION").font(.caption.weight(.semibold)).foregroundStyle(Color.inkFade)
                            Text(p.campaign.name).font(.title2.weight(.bold))
                            if !p.campaign.description.isEmpty {
                                Text(p.campaign.description).font(.caption).foregroundStyle(Color.inkDim)
                            }
                            Divider().background(Color.white.opacity(0.05)).padding(.vertical, 4)
                            row("Code", code)
                            row("Joining as", p.role.capitalized)
                            if !p.label.isEmpty { row("From", p.label) }
                            row("Uses left", "\(p.remaining_uses)")
                        }
                    }
                    if let error { ErrorBanner(message: error) }
                    Button {
                        Task { await accept() }
                    } label: {
                        HStack {
                            if accepting { ProgressView().tint(.white) }
                            Text(accepting ? "Joining…" : "Join Crusade")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle(enabled: !accepting))
                    .disabled(accepting)
                } else if let error {
                    ErrorBanner(message: error)
                    Button("Close") { dismiss() }.buttonStyle(SecondaryButtonStyle())
                }
            }.padding()
        }
        .background(Color.bg.ignoresSafeArea())
        .navigationTitle("Invite")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .task { await load() }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.caption).foregroundStyle(Color.inkFade)
            Spacer()
            Text(v).font(.caption.weight(.semibold))
        }
    }

    private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do { preview = try await APIClient.shared.previewInvite(code) }
        catch let e as APIError { error = e.message }
        catch let e { self.error = e.localizedDescription }
    }

    private func accept() async {
        accepting = true; error = nil
        defer { accepting = false }
        do {
            _ = try await APIClient.shared.acceptInvite(code)
            onAccepted()
            dismiss()
        } catch let e as APIError { error = e.message }
        catch let e { self.error = e.localizedDescription }
    }
}
