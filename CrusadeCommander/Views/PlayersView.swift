import SwiftUI

// ForcesPanel + AddForceSheet

struct ForcesPanel: View {
    let campaignId: String
    let forces: [APIForce]
    let currentUserId: String
    let isAdmin: Bool
    let onChange: () -> Void

    @State private var showingAdd = false

    private var myForce: APIForce? { forces.first(where: { $0.user_id == currentUserId }) }
    private var canAdd: Bool { myForce == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(forces.count) Crusade Force\(forces.count == 1 ? "" : "s")").font(.subheadline.weight(.semibold))
                Spacer()
                if canAdd {
                    Button { showingAdd = true } label: {
                        Label("Add Force", systemImage: "plus")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color.accent).foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                } else if let mine = myForce {
                    Text("You command **\(mine.name)**").font(.caption).foregroundStyle(Color.inkFade)
                }
            }

            sectionGroup("Your Forces", items: forces.filter { $0.user_id == currentUserId && $0.is_active })
            sectionGroup("Other Forces", items: forces.filter { $0.user_id != currentUserId && $0.is_active })
            sectionGroup("Dropped", items: forces.filter { !$0.is_active })
        }
        .sheet(isPresented: $showingAdd) {
            NavigationStack {
                AddForceSheet(
                    campaignId: campaignId,
                    existingTeams: Array(Set(forces.map { $0.team }.filter { !$0.isEmpty })),
                    onDone: { showingAdd = false; onChange() }
                )
            }
        }
    }

    @ViewBuilder
    private func sectionGroup(_ title: String, items: [APIForce]) -> some View {
        if !items.isEmpty {
            Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(Color.inkFade).padding(.top, 4)
            ForEach(items) { f in
                NavigationLink(destination: ForceDetailView(campaignId: campaignId, forceId: f.id)) {
                    forceCard(f)
                }.buttonStyle(.plain)
            }
        }
    }

    private func forceCard(_ f: APIForce) -> some View {
        CardBox {
            VStack(spacing: 10) {
                HStack {
                    Circle().fill(Color(hex: f.color_hex)).frame(width: 36, height: 36)
                        .overlay(Text(f.name.prefix(1).uppercased()).font(.headline).foregroundStyle(.white))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(f.name).font(.subheadline.weight(.semibold))
                            if !f.team.isEmpty { BadgeView(text: f.team, style: .accent) }
                            if !f.is_active { BadgeView(text: "Dropped", style: .dim) }
                        }
                        Text(f.faction.isEmpty ? "—" : f.faction)
                            .font(.caption2).foregroundStyle(Color.inkFade)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Color.inkFade)
                }
                HStack(spacing: 14) {
                    stat("Supply", "\(f.supply_limit)")
                    stat("RP", "\(f.requisition_points)", accent: .accent)
                    stat("Battles", "\(f.battle_tally)")
                    stat("Wins", "\(f.victories)", accent: .successC)
                }
            }
        }
        .opacity(f.is_active ? 1 : 0.6)
    }

    private func stat(_ label: String, _ value: String, accent: Color = .ink) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.weight(.bold)).foregroundStyle(accent)
            Text(label).font(.caption2).foregroundStyle(Color.inkFade)
        }
        .frame(maxWidth: .infinity)
    }
}

struct AddForceSheet: View {
    @Environment(\.dismiss) private var dismiss
    let campaignId: String
    let existingTeams: [String]
    let onDone: () -> Void

    @State private var name = ""
    @State private var playerName = ""
    @State private var faction = ""
    @State private var team = ""
    @State private var color = playerColors.first!
    @State private var busy = false
    @State private var error: String?

    private var teamSuggestions: [String] { Array(Set(existingTeams + suggestedTeams)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                CardBox {
                    VStack(alignment: .leading, spacing: 12) {
                        labeled("Force Name") { input($name) }
                        labeled("Player Name (optional)") { input($playerName) }
                        labeled("Faction") {
                            Picker("Faction", selection: $faction) {
                                Text("Select…").tag("")
                                ForEach(warhammerFactions, id: \.self) { Text($0).tag($0) }
                            }
                            .pickerStyle(.menu)
                            .padding(8).background(Color.bgElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        labeled("Team / Alliance (optional)") {
                            input($team)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(teamSuggestions, id: \.self) { t in
                                    Button {
                                        team = t
                                    } label: {
                                        Text(t).font(.caption2.weight(.medium))
                                            .padding(.horizontal, 10).padding(.vertical, 5)
                                            .background(team == t ? Color.accent : Color.accentSoft)
                                            .foregroundStyle(team == t ? Color.white : Color.accent)
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                        labeled("Colour") { ColorPickerStrip(selection: $color) }
                    }
                }
                if let error { ErrorBanner(message: error) }
                Button {
                    Task { await create() }
                } label: {
                    HStack {
                        if busy { ProgressView().tint(.white) }
                        Text(busy ? "Adding…" : "Add Force")
                    }
                }
                .buttonStyle(PrimaryButtonStyle(enabled: !busy && !name.isEmpty))
                .disabled(busy || name.isEmpty)
            }.padding()
        }
        .background(Color.bg.ignoresSafeArea())
        .navigationTitle("New Force")
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
            _ = try await APIClient.shared.createForce(
                campaignId, name: name.trimmingCharacters(in: .whitespaces),
                playerName: playerName, faction: faction,
                team: team.trimmingCharacters(in: .whitespaces),
                colorHex: color
            )
            onDone()
        } catch let e as APIError { error = e.message }
        catch let e { self.error = e.localizedDescription }
    }
}
