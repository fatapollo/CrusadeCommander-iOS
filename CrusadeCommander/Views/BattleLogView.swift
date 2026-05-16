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
    @State private var notes: String = ""
    @State private var busy = false
    @State private var error: String?
    @State private var feedback: String?

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
                        labeled("Outcome") {
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
                attackerId: attackerId, defenderId: defenderId,
                outcome: outcome, notes: notes
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
