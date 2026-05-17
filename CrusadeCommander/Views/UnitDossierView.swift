import SwiftUI

private let SCAR_NAMES = ["Crippling Damage", "Battle-weary", "Fatigued", "Disgraced", "Mark of Shame", "Deep Scars"]
private let HONOUR_CATEGORIES = ["Battle Trait", "Weapon Modification", "Crusade Relic"]

struct UnitDossierView: View {
    let campaignId: String
    let forceId: String
    let unitId: String

    @State private var unit: APIUnit?
    @State private var honours: [APIHonour] = []
    @State private var scars: [APIScar] = []
    @State private var honourAvailable = 0
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if loading {
                    ProgressView().tint(.accent).frame(maxWidth: .infinity).padding(.top, 40)
                } else if let u = unit {
                    header(u)
                    statsGrid(u)
                    honoursSection(u)
                    scarsSection(u)
                    typeStatusEditor(u)
                } else if let error {
                    ErrorBanner(message: error)
                }
            }
            .padding()
        }
        .background(Color.bg.ignoresSafeArea())
        .navigationTitle(unit?.name ?? "Unit")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do {
            let r = try await APIClient.shared.getUnitDetail(campaignId, unitId: unitId)
            unit = r.unit; honours = r.honours; scars = r.scars
            honourAvailable = r.honour_available ?? 0
        } catch let e as APIError { error = e.message }
        catch { self.error = "Failed to load unit" }
    }

    private func header(_ u: APIUnit) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(u.name).font(.title3.weight(.bold))
                if u.is_character { BadgeView(text: "Character", style: .accent) }
                if u.is_titanic { BadgeView(text: "Titanic", style: .warning) }
                if (u.status ?? "Active") == "Reserve" { BadgeView(text: "Reserve", style: .dim) }
                if (u.status ?? "Active") == "Injured" { BadgeView(text: "Injured", style: .warning) }
                if !u.is_active { BadgeView(text: "Destroyed", style: .danger) }
            }
            Text("\(u.datasheet) · \(u.points_cost) pts · \(u.rank.rawValue)\(u.unit_type.map { $0.isEmpty ? "" : " · \($0)" } ?? "")")
                .font(.caption).foregroundStyle(Color.inkDim)
            if !u.equipment.isEmpty {
                Text(u.equipment).font(.caption2).foregroundStyle(Color.inkFade)
            }
        }
    }

    private func statsGrid(_ u: APIUnit) -> some View {
        HStack(spacing: 8) {
            stat("XP", "\(u.xp)", .accent)
            stat("CP", "\(u.crusade_points)", u.crusade_points < 0 ? .red : .ink)
            stat("Battles", "\(u.battles_played)")
            stat("Kills", "\(u.units_destroyed)")
        }
    }

    private func stat(_ l: String, _ v: String, _ c: Color = .ink) -> some View {
        CardBox {
            VStack(spacing: 2) {
                Text(v).font(.headline.weight(.bold)).foregroundStyle(c)
                Text(l).font(.caption2).foregroundStyle(Color.inkFade)
            }.frame(maxWidth: .infinity)
        }
    }

    private func honoursSection(_ u: APIUnit) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Battle Honours").font(.subheadline.weight(.semibold))
                if honourAvailable > 0 && u.is_active {
                    BadgeView(text: "\(honourAvailable) available", style: .success)
                }
            }
            if honours.isEmpty {
                Text("No Battle Honours earned yet. Each rank-up grants one.")
                    .font(.caption2).foregroundStyle(Color.inkFade)
            } else {
                ForEach(honours) { h in
                    CardBox {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    BadgeView(text: h.category, style: .accent)
                                    Text(h.name).font(.caption.weight(.semibold))
                                }
                                if !h.description.isEmpty {
                                    Text(h.description).font(.caption2).foregroundStyle(Color.inkFade)
                                }
                            }
                            Spacer()
                            Button(role: .destructive) {
                                Task { await act { try await APIClient.shared.removeHonour(campaignId, unitId: unitId, honourId: h.id) } }
                            } label: { Image(systemName: "xmark.circle") }
                                .foregroundStyle(Color.inkFade)
                        }
                    }
                }
            }
            if u.is_active && honourAvailable > 0 {
                AddHonourForm(campaignId: campaignId, unitId: unitId, onDone: { Task { await load() } },
                              onError: { error = $0 })
            } else if u.is_active && honours.count < (u.is_character || u.can_exceed_30_xp ? 6 : 3) {
                Text("No Battle Honour available — rank up (gain XP) or be Marked for Greatness and survive a battle.")
                    .font(.caption2).foregroundStyle(Color.inkFade)
            }
            if u.is_character && u.is_active {
                EnhancementForm(campaignId: campaignId, forceId: forceId, unitId: unitId,
                                onDone: { Task { await load() } }, onError: { error = $0 })
            }
        }
    }

    private func scarsSection(_ u: APIUnit) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Battle Scars (\(scars.count)/3)").font(.subheadline.weight(.semibold))
            if scars.isEmpty {
                Text("No scars.").font(.caption2).foregroundStyle(Color.inkFade)
            } else {
                ForEach(scars) { s in
                    CardBox {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.name).font(.caption.weight(.semibold)).foregroundStyle(Color.red)
                                if !s.description.isEmpty {
                                    Text(s.description).font(.caption2).foregroundStyle(Color.inkFade)
                                }
                            }
                            Spacer()
                            Button("Repair") {
                                Task { await act { _ = try await APIClient.shared.reqRepairAndRecuperate(campaignId, forceId: forceId, unitId: unitId, scarId: s.id) } }
                            }.font(.caption2).foregroundStyle(Color.accent)
                            Button(role: .destructive) {
                                Task { await act { try await APIClient.shared.removeScar(campaignId, unitId: unitId, scarId: s.id) } }
                            } label: { Image(systemName: "xmark.circle") }
                                .foregroundStyle(Color.inkFade)
                        }
                    }
                }
            }
            if u.is_active && scars.count < 3 {
                AddScarForm(campaignId: campaignId, unitId: unitId, existing: scars.map(\.name),
                            onDone: { Task { await load() } }, onError: { error = $0 })
            }
        }
    }

    private func typeStatusEditor(_ u: APIUnit) -> some View {
        TypeStatusForm(campaignId: campaignId, unitId: unitId,
                       unitType: u.unit_type ?? "", status: u.status ?? "Active",
                       onDone: { Task { await load() } }, onError: { error = $0 })
    }

    private func act(_ op: () async throws -> Void) async {
        do { try await op(); await load() }
        catch let e as APIError { error = e.message }
        catch { self.error = "Action failed" }
    }
}

private struct AddHonourForm: View {
    let campaignId: String; let unitId: String
    let onDone: () -> Void; let onError: (String) -> Void
    @State private var open = false
    @State private var category = "Battle Trait"
    @State private var name = ""
    @State private var weapon = ""
    @State private var relic = "Artificer"
    @State private var busy = false

    var body: some View {
        if !open {
            Button("+ Add Battle Honour") { open = true }
                .font(.caption.weight(.medium)).foregroundStyle(Color.accent)
        } else {
            CardBox {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Category", selection: $category) {
                        ForEach(HONOUR_CATEGORIES, id: \.self) { Text($0) }
                    }.pickerStyle(.menu).tint(.accent)
                    field("Name", $name)
                    if category == "Weapon Modification" { field("Weapon", $weapon) }
                    if category == "Crusade Relic" {
                        Picker("Relic", selection: $relic) {
                            ForEach(["Artificer", "Antiquity", "Legendary"], id: \.self) { Text($0) }
                        }.pickerStyle(.menu).tint(.accent)
                    }
                    HStack {
                        Button("Add") {
                            busy = true
                            Task {
                                do {
                                    try await APIClient.shared.addHonour(campaignId, unitId: unitId,
                                        category: category, name: name.trimmingCharacters(in: .whitespaces),
                                        description: "", weaponName: category == "Weapon Modification" ? weapon : "",
                                        relicCategory: category == "Crusade Relic" ? relic : nil)
                                    open = false; onDone()
                                } catch let e as APIError { onError(e.message) }
                                catch { onError("Failed") }
                                busy = false
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle(enabled: !busy && !name.isEmpty))
                        .disabled(busy || name.isEmpty)
                        Button("Cancel") { open = false }.foregroundStyle(Color.inkDim)
                    }
                }
            }
        }
    }
    private func field(_ l: String, _ b: Binding<String>) -> some View {
        TextField(l, text: b).padding(10).background(Color.bgElevated)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct AddScarForm: View {
    let campaignId: String; let unitId: String; let existing: [String]
    let onDone: () -> Void; let onError: (String) -> Void
    @State private var open = false
    @State private var name = SCAR_NAMES[0]
    @State private var busy = false
    var available: [String] { SCAR_NAMES.filter { !existing.contains($0) } }

    var body: some View {
        if !open {
            Button("+ Add Battle Scar") { open = true; name = available.first ?? SCAR_NAMES[0] }
                .font(.caption.weight(.medium)).foregroundStyle(Color.accent)
        } else {
            CardBox {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Scar", selection: $name) {
                        ForEach(available, id: \.self) { Text($0) }
                    }.pickerStyle(.menu).tint(.accent)
                    HStack {
                        Button("Add Scar") {
                            busy = true
                            Task {
                                do { try await APIClient.shared.addScar(campaignId, unitId: unitId, name: name); open = false; onDone() }
                                catch let e as APIError { onError(e.message) }
                                catch { onError("Failed") }
                                busy = false
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle(enabled: !busy))
                        .disabled(busy)
                        Button("Cancel") { open = false }.foregroundStyle(Color.inkDim)
                    }
                }
            }
        }
    }
}

private struct EnhancementForm: View {
    let campaignId: String; let forceId: String; let unitId: String
    let onDone: () -> Void; let onError: (String) -> Void
    @State private var open = false
    @State private var name = ""
    @State private var busy = false

    var body: some View {
        if !open {
            Button("+ Add Enhancement (Renowned Heroes · 1–3 RP)") { open = true }
                .font(.caption.weight(.medium)).foregroundStyle(Color.accent)
        } else {
            CardBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Spends 1–3 RP from this force (scales with Enhancements already in the force).")
                        .font(.caption2).foregroundStyle(Color.inkFade)
                    TextField("Enhancement Name", text: $name)
                        .padding(10).background(Color.bgElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    HStack {
                        Button("Purchase") {
                            busy = true
                            Task {
                                do {
                                    _ = try await APIClient.shared.reqRenownedHeroes(campaignId, forceId: forceId,
                                        unitId: unitId, name: name.trimmingCharacters(in: .whitespaces), description: "")
                                    open = false; onDone()
                                } catch let e as APIError { onError(e.message) }
                                catch { onError("Failed") }
                                busy = false
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle(enabled: !busy && !name.isEmpty))
                        .disabled(busy || name.isEmpty)
                        Button("Cancel") { open = false }.foregroundStyle(Color.inkDim)
                    }
                }
            }
        }
    }
}

private struct TypeStatusForm: View {
    let campaignId: String; let unitId: String
    let unitType: String; let status: String
    let onDone: () -> Void; let onError: (String) -> Void
    @State private var open = false
    @State private var t = ""
    @State private var s = "Active"
    @State private var busy = false

    var body: some View {
        if !open {
            Button("Edit type / status") { t = unitType; s = status; open = true }
                .font(.caption2).foregroundStyle(Color.inkDim)
        } else {
            CardBox {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Unit Type (e.g. INFANTRY)", text: $t)
                        .padding(10).background(Color.bgElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Picker("Status", selection: $s) {
                        ForEach(["Active", "Reserve", "Injured"], id: \.self) { Text($0) }
                    }.pickerStyle(.segmented)
                    HStack {
                        Button("Save") {
                            busy = true
                            Task {
                                do { _ = try await APIClient.shared.updateUnit(campaignId, unitId: unitId, unitType: t, status: s); open = false; onDone() }
                                catch let e as APIError { onError(e.message) }
                                catch { onError("Failed") }
                                busy = false
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle(enabled: !busy))
                        .disabled(busy)
                        Button("Cancel") { open = false }.foregroundStyle(Color.inkDim)
                    }
                }
            }
        }
    }
}
