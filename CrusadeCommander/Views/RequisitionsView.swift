import SwiftUI

// Spend Requisition Points. Mirrors the web Requisitions panel; costs and
// eligibility are enforced server-side.
struct RequisitionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let campaignId: String
    let forceId: String
    let force: APIForce?
    let units: [APIUnit]
    let onChange: () -> Void

    @State private var rp: Int = 0
    @State private var log: [RequisitionLogItem] = []
    @State private var message: (ok: Bool, text: String)?
    @State private var busy = false

    private var active: [APIUnit] { units.filter { $0.is_active } }
    private var characters: [APIUnit] { active.filter { $0.is_character } }
    private var veterans: [APIUnit] { active.filter { !$0.is_character && $0.xp >= 30 && !$0.can_exceed_30_xp } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("\(rp) RP available · spending is logged · costs charged server-side")
                    .font(.caption2).foregroundStyle(Color.inkFade)

                if let m = message {
                    Text(m.text).font(.caption.weight(.medium))
                        .foregroundStyle(m.ok ? Color.green : Color.red)
                }

                SimpleReqCard(title: "Increase Supply Limit", cost: "1 RP",
                              desc: "+200 pts to this force's Supply Limit.",
                              disabled: busy || rp < 1) {
                    await run { try await APIClient.shared.reqIncreaseSupplyLimit(campaignId, forceId: forceId) }
                }

                UnitReqCard(title: "Renowned Heroes", cost: "1–3 RP",
                            desc: "Grant an Enhancement to a Character (one per unit).",
                            units: characters, needsText: true, textLabel: "Enhancement Name",
                            busy: busy) { uid, text in
                    await run { try await APIClient.shared.reqRenownedHeroes(campaignId, forceId: forceId, unitId: uid, name: text, description: "") }
                }

                UnitReqCard(title: "Legendary Veterans", cost: "3 RP",
                            desc: "A non-Character at 30 XP may exceed the cap and keep ranking up.",
                            units: veterans, needsText: false, textLabel: "",
                            busy: busy) { uid, _ in
                    await run { try await APIClient.shared.reqLegendaryVeterans(campaignId, forceId: forceId, unitId: uid) }
                }

                UnitReqCard(title: "Rearm and Resupply", cost: "1 RP",
                            desc: "Change a unit's wargear loadout.",
                            units: active, needsText: true, textLabel: "New Equipment",
                            busy: busy) { uid, text in
                    await run { try await APIClient.shared.reqRearmAndResupply(campaignId, forceId: forceId, unitId: uid, equipment: text, pointsCost: nil) }
                }

                UnitReqCard(title: "Fresh Recruits", cost: "1–4 RP",
                            desc: "Add models to a unit (raises its points).",
                            units: active, needsText: true, textLabel: "Points to Add",
                            keyboard: .numberPad, busy: busy) { uid, text in
                    let pts = Int(text) ?? 0
                    await run { try await APIClient.shared.reqFreshRecruits(campaignId, forceId: forceId, unitId: uid, addedPoints: pts) }
                }

                CardBox {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Repair and Recuperate").font(.subheadline.weight(.bold))
                        Text("Remove a Battle Scar — use the Repair action from that unit's dossier.")
                            .font(.caption2).foregroundStyle(Color.inkFade)
                    }
                }

                if !log.isEmpty {
                    Text("// REQUISITION LOG").font(.caption2.weight(.bold))
                        .foregroundStyle(Color.accent).padding(.top, 6)
                    ForEach(log) { e in
                        HStack {
                            Text(e.requisition_name).font(.caption).foregroundStyle(Color.ink)
                            Spacer()
                            Text("−\(e.cost_paid) RP").font(.caption.weight(.bold)).foregroundStyle(Color.accent)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding()
        }
        .background(Color.bg.ignoresSafeArea())
        .navigationTitle("Requisitions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        .task {
            rp = force?.requisition_points ?? 0
            await reloadLog()
        }
    }

    private func reloadLog() async {
        log = (try? await APIClient.shared.requisitionLog(campaignId, forceId: forceId)) ?? []
    }

    private func run(_ op: () async throws -> APIForce) async {
        busy = true; message = nil
        defer { busy = false }
        do {
            let f = try await op()
            rp = f.requisition_points
            message = (true, "Done.")
            onChange()
            await reloadLog()
        } catch let e as APIError {
            message = (false, e.message)
        } catch {
            message = (false, "Requisition failed")
        }
    }
}

private struct SimpleReqCard: View {
    let title: String; let cost: String; let desc: String
    let disabled: Bool
    let action: () async -> Void
    var body: some View {
        CardBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title).font(.subheadline.weight(.bold))
                    Spacer()
                    Text(cost).font(.caption.weight(.bold)).foregroundStyle(Color.accent)
                }
                Text(desc).font(.caption2).foregroundStyle(Color.inkFade)
                Button { Task { await action() } } label: {
                    Text("Purchase").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(enabled: !disabled))
                .disabled(disabled)
            }
        }
    }
}

private struct UnitReqCard: View {
    let title: String; let cost: String; let desc: String
    let units: [APIUnit]
    let needsText: Bool
    let textLabel: String
    var keyboard: UIKeyboardType = .default
    let busy: Bool
    let action: (String, String) async -> Void

    @State private var unitId = ""
    @State private var text = ""

    var body: some View {
        CardBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title).font(.subheadline.weight(.bold))
                    Spacer()
                    Text(cost).font(.caption.weight(.bold)).foregroundStyle(Color.accent)
                }
                Text(desc).font(.caption2).foregroundStyle(Color.inkFade)
                if units.isEmpty {
                    Text("No eligible units.").font(.caption2).foregroundStyle(Color.inkFade)
                } else {
                    Picker("Unit", selection: $unitId) {
                        Text("— select —").tag("")
                        ForEach(units) { u in Text(u.name).tag(u.id) }
                    }
                    .pickerStyle(.menu).tint(.accent)
                    if needsText && !unitId.isEmpty {
                        TextField(textLabel, text: $text)
                            .keyboardType(keyboard)
                            .padding(10).background(Color.bgElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    Button { Task { await action(unitId, text) } } label: {
                        Text("Purchase").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle(enabled: !busy && !unitId.isEmpty && (!needsText || !text.isEmpty)))
                    .disabled(busy || unitId.isEmpty || (needsText && text.isEmpty))
                }
            }
        }
    }
}
