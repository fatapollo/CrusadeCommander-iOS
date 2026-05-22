import SwiftUI

// BattlesPanel + RecordBattleSheet

struct BattlesPanel: View {
    let campaignId: String
    let campaignState: CampaignState
    let forces: [APIForce]
    let battles: [APIBattle]
    let defaultBattleSize: BattleSize
    let currentUserId: String
    let isAdmin: Bool
    let onChange: () -> Void

    @State private var showingRecord = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                let pending = battles.filter { $0.status == .pending }.count
                let confirmed = battles.filter { $0.status == .confirmed }.count
                Text("\(confirmed) Confirmed · \(pending) Pending").font(.subheadline.weight(.semibold))
                Spacer()
                if campaignState == .active {
                    Button { showingRecord = true } label: {
                        Label("Record", systemImage: "plus")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color.accent).foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }
            }

            if campaignState == .setup {
                EmptyStateView(icon: "⏱", title: "Campaign hasn't started", subtitle: "An admin must Start the campaign before battles can be recorded.")
            } else if campaignState == .concluded {
                EmptyStateView(icon: "◇", title: "Campaign concluded", subtitle: "No new battles can be recorded.")
            } else if forces.filter({ $0.is_active }).count < 2 {
                EmptyStateView(icon: "◉", title: "Need at least 2 active forces", subtitle: "Add or rejoin a force to record battles.")
            } else {
                let pending = battles.filter { $0.status == .pending || $0.status == .disputed }
                let confirmed = battles.filter { $0.status == .confirmed }
                if !pending.isEmpty {
                    Text("AWAITING CONFIRMATION").font(.caption.weight(.semibold)).foregroundStyle(Color.inkFade).padding(.top, 4)
                    ForEach(pending) { battleRow($0, pending: true) }
                }
                if !confirmed.isEmpty {
                    if !pending.isEmpty {
                        Text("CONFIRMED").font(.caption.weight(.semibold)).foregroundStyle(Color.inkFade).padding(.top, 4)
                    }
                    ForEach(confirmed) { battleRow($0, pending: false) }
                }
                if pending.isEmpty && confirmed.isEmpty {
                    EmptyStateView(icon: "⚔", title: "No battles yet", subtitle: "Record your first to start awarding XP and Requisition Points.")
                }
            }
        }
        .sheet(isPresented: $showingRecord) {
            NavigationStack {
                RecordBattleSheet(
                    campaignId: campaignId,
                    forces: forces.filter { $0.is_active },
                    defaultBattleSize: defaultBattleSize,
                    onDone: { showingRecord = false; onChange() }
                )
            }
        }
    }

    private func battleRow(_ b: APIBattle, pending: Bool) -> some View {
        let att = forces.first { $0.id == b.attacker_force_id }
        let def = forces.first { $0.id == b.defender_force_id }
        let winnerId: String? = {
            switch b.outcome {
            case .attackerWins: return b.attacker_force_id
            case .defenderWins: return b.defender_force_id
            case .draw: return nil
            }
        }()
        let canConfirm = b.status == .pending
            && b.submitted_by_user_id != currentUserId
            && (isAdmin || [att?.user_id, def?.user_id].contains(currentUserId))

        return CardBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    BadgeView(text: b.battle_size.rawValue, style: .dim)
                    Text(att?.name ?? "?").font(.subheadline.weight(winnerId == b.attacker_force_id ? .semibold : .regular))
                    Text("vs").font(.caption2).foregroundStyle(Color.inkFade)
                    Text(def?.name ?? "?").font(.subheadline.weight(winnerId == b.defender_force_id ? .semibold : .regular))
                    Spacer()
                    BadgeView(
                        text: b.status == .confirmed ? b.outcome.rawValue : b.status.rawValue.capitalized,
                        style: b.status == .confirmed ? (b.outcome == .draw ? .dim : .success) : b.status == .pending ? .warning : .danger
                    )
                }
                if let asc = b.attacker_score, let dsc = b.defender_score, asc + dsc > 0 {
                    Text("\(asc) – \(dsc)").font(.caption.weight(.semibold)).foregroundStyle(Color.inkDim)
                }
                if !b.mission_name.isEmpty {
                    Text(b.mission_name).font(.caption2).foregroundStyle(Color.inkFade)
                }
                if pending {
                    if canConfirm {
                        Button("✓ Confirm Result") {
                            Task {
                                do {
                                    try await APIClient.shared.confirmBattle(campaignId, b.id)
                                    onChange()
                                } catch { }
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .font(.caption)
                    } else if b.submitted_by_user_id == currentUserId {
                        Text("Awaiting opponent confirmation").font(.caption2).foregroundStyle(Color.inkFade)
                    }
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12).stroke(b.status == .pending ? Color.warningC.opacity(0.4) : b.status == .disputed ? Color.dangerC.opacity(0.4) : Color.clear)
        )
    }
}

private struct UnitParticipation: Equatable {
    var selected: Bool = false
    var wasWarlord: Bool = false
    var enemiesDestroyed: Int = 0
    var wasDestroyed: Bool = false
    var markedForGreatness: Bool = false
    var ooaResult: String = ""       // "", "passed", "battle_scar", "devastating_blow"
    var grantScar: String = ""       // BattleScar name when ooa == battle_scar
    var grantHonourName: String = "" // applied only if a rank-up occurred server-side
}

private let SCARS = ["Crippling Damage", "Battle-weary", "Fatigued",
                     "Disgraced", "Mark of Shame", "Deep Scars"]

struct RecordBattleSheet: View {
    @Environment(\.dismiss) private var dismiss
    let campaignId: String
    let forces: [APIForce]
    let defaultBattleSize: BattleSize
    let onDone: () -> Void

    @State private var battleSize: BattleSize
    @State private var attackerId: String = ""
    @State private var defenderId: String = ""
    @State private var outcome: BattleOutcome = .attackerWins
    @State private var mission: String = ""
    @State private var deployment: String = ""
    @State private var durationTurns: Int = 5
    @State private var opposingCommander: String = ""
    @State private var attackerScore: Int = 0
    @State private var defenderScore: Int = 0
    @State private var notes: String = ""
    @State private var busy = false
    @State private var error: String?
    @State private var feedback: String?

    // Per-force unit listings + participation rows, keyed by unit id.
    @State private var attackerUnits: [APIUnit] = []
    @State private var defenderUnits: [APIUnit] = []
    @State private var participation: [String: UnitParticipation] = [:]
    @State private var loadingUnits = false

    init(campaignId: String, forces: [APIForce], defaultBattleSize: BattleSize, onDone: @escaping () -> Void) {
        self.campaignId = campaignId
        self.forces = forces
        self.defaultBattleSize = defaultBattleSize
        self.onDone = onDone
        self._battleSize = State(initialValue: defaultBattleSize)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                CardBox {
                    VStack(alignment: .leading, spacing: 12) {
                        labeled("Battle Size") {
                            Picker("", selection: $battleSize) {
                                ForEach(BattleSize.allCases) { Text($0.rawValue).tag($0) }
                            }.pickerStyle(.segmented)
                        }
                        labeled("Attacker") {
                            Picker("", selection: $attackerId) {
                                Text("Select…").tag("")
                                ForEach(forces) { Text($0.name).tag($0.id) }
                            }.pickerStyle(.menu).padding(8).background(Color.bgElevated).clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        labeled("Defender") {
                            Picker("", selection: $defenderId) {
                                Text("Select…").tag("")
                                ForEach(forces.filter { $0.id != attackerId }) { Text($0.name).tag($0.id) }
                            }.pickerStyle(.menu).padding(8).background(Color.bgElevated).clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        labeled("Mission Name (optional)") {
                            TextField("", text: $mission)
                                .padding(10).background(Color.bgElevated).clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        labeled("Deployment (optional)") {
                            TextField("", text: $deployment)
                                .padding(10).background(Color.bgElevated).clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        labeled("Duration (turns)") {
                            Stepper("\(durationTurns)", value: $durationTurns, in: 0...50)
                                .padding(8).background(Color.bgElevated).clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        HStack(spacing: 10) {
                            labeled("Attacker Score") {
                                TextField("0", value: $attackerScore, format: .number)
                                    .keyboardType(.numberPad)
                                    .padding(10).background(Color.bgElevated).clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            labeled("Defender Score") {
                                TextField("0", value: $defenderScore, format: .number)
                                    .keyboardType(.numberPad)
                                    .padding(10).background(Color.bgElevated).clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        labeled("Opposing Commander (optional)") {
                            TextField("", text: $opposingCommander)
                                .padding(10).background(Color.bgElevated).clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        labeled("Outcome (auto from score — override if needed)") {
                            Picker("", selection: $outcome) {
                                ForEach(BattleOutcome.allCases) { Text($0.rawValue).tag($0) }
                            }.pickerStyle(.segmented)
                        }
                        labeled("Notes (optional)") {
                            TextField("", text: $notes, axis: .vertical)
                                .lineLimit(2...4)
                                .padding(10).background(Color.bgElevated).clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }

                unitsCard

                if let feedback {
                    CardBox {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Submitted").font(.caption.weight(.semibold)).foregroundStyle(Color.successC)
                            Text(feedback).font(.caption).foregroundStyle(Color.inkDim)
                        }
                    }
                }
                if let error { ErrorBanner(message: error) }

                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        if busy { ProgressView().tint(.white) }
                        Text(busy ? "Submitting…" : "Record Battle")
                    }
                }
                .buttonStyle(PrimaryButtonStyle(enabled: !busy && !attackerId.isEmpty && !defenderId.isEmpty))
                .disabled(busy || attackerId.isEmpty || defenderId.isEmpty)
            }.padding()
        }
        .background(Color.bg.ignoresSafeArea())
        .navigationTitle("Record Battle")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .onChange(of: attackerScore) { syncOutcome() }
        .onChange(of: defenderScore) { syncOutcome() }
        .onChange(of: attackerId) { Task { await loadUnits(force: .attacker) } }
        .onChange(of: defenderId) { Task { await loadUnits(force: .defender) } }
    }

    // MARK: - Units deployed

    private enum Side { case attacker, defender }

    @ViewBuilder
    private var unitsCard: some View {
        CardBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("UNITS DEPLOYED")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.inkFade)
                    Spacer()
                    Text("\(selectedCount) selected")
                        .font(.caption2)
                        .foregroundStyle(Color.inkFade)
                }
                if attackerId.isEmpty || defenderId.isEmpty {
                    Text("Pick both forces to choose units.")
                        .font(.caption)
                        .foregroundStyle(Color.inkFade)
                } else if loadingUnits {
                    ProgressView().tint(.accent)
                } else {
                    unitsForce(label: forceName(attackerId) + " (ATTACKER)", units: attackerUnits)
                    unitsForce(label: forceName(defenderId) + " (DEFENDER)", units: defenderUnits)
                }
            }
        }
    }

    @ViewBuilder
    private func unitsForce(label: String, units: [APIUnit]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("// \(label)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.accent)
            if units.isEmpty {
                Text("No units.").font(.caption2).foregroundStyle(Color.inkFade)
            } else {
                ForEach(units) { u in unitRow(u) }
            }
        }
    }

    @ViewBuilder
    private func unitRow(_ u: APIUnit) -> some View {
        let p = participation[u.id] ?? UnitParticipation()
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: toggleBinding(u.id, \.selected)) {
                HStack(spacing: 6) {
                    Text(u.name).font(.subheadline.weight(.semibold))
                    Text("· \(u.unit_type ?? u.datasheet) · \(u.xp) XP")
                        .font(.caption2)
                        .foregroundStyle(Color.inkFade)
                }
            }
            .toggleStyle(.switch)
            .tint(.accent)

            if p.selected {
                HStack(spacing: 12) {
                    labeled("Enemies Destroyed") {
                        Stepper("\(p.enemiesDestroyed)", value: stepperBinding(u.id, \.enemiesDestroyed), in: 0...99)
                            .padding(6).background(Color.bg).clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Warlord", isOn: toggleBinding(u.id, \.wasWarlord)).font(.caption)
                        Toggle("Marked for Greatness", isOn: toggleBinding(u.id, \.markedForGreatness)).font(.caption)
                        Toggle("Destroyed", isOn: toggleBinding(u.id, \.wasDestroyed)).font(.caption)
                    }
                }
                if p.wasDestroyed {
                    labeled("Out of Action") {
                        Picker("", selection: stringBinding(u.id, \.ooaResult)) {
                            Text("— not tested —").tag("")
                            Text("Passed").tag("passed")
                            Text("Battle Scar").tag("battle_scar")
                            Text("Devastating Blow").tag("devastating_blow")
                        }
                        .pickerStyle(.menu)
                        .padding(6).background(Color.bgElevated).clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    if p.ooaResult == "battle_scar" {
                        labeled("Scar to apply") {
                            Picker("", selection: stringBinding(u.id, \.grantScar)) {
                                Text("— none —").tag("")
                                ForEach(SCARS, id: \.self) { Text($0).tag($0) }
                            }
                            .pickerStyle(.menu)
                            .padding(6).background(Color.bgElevated).clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                labeled("Grant Battle Honour (only if a rank was gained)") {
                    TextField("e.g. Duellist", text: stringBinding(u.id, \.grantHonourName))
                        .padding(8).background(Color.bgElevated).clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding(10)
        .background(Color.bg)
        .overlay(Rectangle().stroke(Color.white.opacity(0.06)))
    }

    // MARK: - Bindings into the participation map

    private func mutate(_ unitId: String, _ block: (inout UnitParticipation) -> Void) {
        var row = participation[unitId] ?? UnitParticipation()
        block(&row)
        participation[unitId] = row
    }
    private func toggleBinding(_ unitId: String, _ kp: WritableKeyPath<UnitParticipation, Bool>) -> Binding<Bool> {
        Binding(get: { (participation[unitId] ?? UnitParticipation())[keyPath: kp] },
                set: { v in mutate(unitId) { $0[keyPath: kp] = v } })
    }
    private func stepperBinding(_ unitId: String, _ kp: WritableKeyPath<UnitParticipation, Int>) -> Binding<Int> {
        Binding(get: { (participation[unitId] ?? UnitParticipation())[keyPath: kp] },
                set: { v in mutate(unitId) { $0[keyPath: kp] = v } })
    }
    private func stringBinding(_ unitId: String, _ kp: WritableKeyPath<UnitParticipation, String>) -> Binding<String> {
        Binding(get: { (participation[unitId] ?? UnitParticipation())[keyPath: kp] },
                set: { v in mutate(unitId) { $0[keyPath: kp] = v } })
    }

    private var selectedCount: Int {
        participation.values.filter { $0.selected }.count
    }

    private func forceName(_ id: String) -> String {
        forces.first(where: { $0.id == id })?.name ?? "—"
    }

    private func loadUnits(force side: Side) async {
        let id = side == .attacker ? attackerId : defenderId
        guard !id.isEmpty else {
            if side == .attacker { attackerUnits = [] } else { defenderUnits = [] }
            return
        }
        loadingUnits = true
        defer { loadingUnits = false }
        do {
            let units = try await APIClient.shared.listUnits(campaignId, forceId: id)
            if side == .attacker { attackerUnits = units } else { defenderUnits = units }
        } catch { /* surface silently — Inscribe Battle still works without per-unit rows */ }
    }

    private func collectUnitInputs(units: [APIUnit]) -> [APIClient.UnitBattleInputBody] {
        units.compactMap { u in
            let p = participation[u.id] ?? UnitParticipation()
            guard p.selected else { return nil }
            let honourName = p.grantHonourName.trimmingCharacters(in: .whitespacesAndNewlines)
            return APIClient.UnitBattleInputBody(
                unit_id: u.id,
                was_warlord: p.wasWarlord,
                enemies_destroyed: p.enemiesDestroyed,
                was_destroyed: p.wasDestroyed,
                marked_for_greatness: p.markedForGreatness,
                ooa_result: p.ooaResult.isEmpty ? nil : p.ooaResult,
                grant_scar: p.grantScar.isEmpty ? nil : p.grantScar,
                grant_honour: honourName.isEmpty ? nil
                    : .init(category: "Battle Trait", name: honourName,
                            description: nil, weapon_name: nil, relic_category: nil)
            )
        }
    }

    private func syncOutcome() {
        if attackerScore > defenderScore { outcome = .attackerWins }
        else if defenderScore > attackerScore { outcome = .defenderWins }
        else { outcome = .draw }
    }

    private func labeled<V: View>(_ label: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.medium)).foregroundStyle(Color.inkDim)
            content()
        }
    }

    private func submit() async {
        busy = true; error = nil; feedback = nil
        defer { busy = false }
        do {
            let r = try await APIClient.shared.createBattle(
                campaignId, battleSize: battleSize, mission: mission,
                deployment: deployment, durationTurns: durationTurns, opposingCommander: opposingCommander,
                attackerId: attackerId, defenderId: defenderId,
                outcome: outcome, attackerScore: attackerScore, defenderScore: defenderScore,
                notes: notes,
                attackerUnits: collectUnitInputs(units: attackerUnits),
                defenderUnits: collectUnitInputs(units: defenderUnits)
            )
            if r.needs_confirmation == true {
                feedback = "Waiting for the opposing player to confirm. XP and RP apply on confirmation."
            } else {
                onDone()
                return
            }
            onDone()
        } catch let e as APIError { error = e.message }
        catch let e { self.error = e.localizedDescription }
    }
}
