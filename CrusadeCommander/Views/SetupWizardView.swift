import SwiftUI

struct SetupWizardView: View {
    @Environment(\.dismiss) private var dismiss
    let onCreated: (APICampaign) -> Void

    @State private var name = ""
    @State private var description = ""
    @State private var battleSize: BattleSize = .strikeForce
    @State private var phaseLabel = "Campaign Turn"
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CardBox {
                    VStack(alignment: .leading, spacing: 12) {
                        labeled("Campaign Name") {
                            TextField("The Octarius War", text: $name)
                                .textFieldStyle(.plain)
                                .padding(10).background(Color.bgElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        labeled("Description (optional)") {
                            TextField("", text: $description, axis: .vertical)
                                .lineLimit(2...4)
                                .padding(10).background(Color.bgElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        labeled("Default Battle Size — \(battleSize.pointsLabel)") {
                            HStack(spacing: 6) {
                                ForEach(BattleSize.allCases) { bs in
                                    Button {
                                        battleSize = bs
                                    } label: {
                                        VStack(spacing: 2) {
                                            Text(bs.rawValue).font(.caption.weight(.semibold))
                                            Text(bs.pointsLabel).font(.caption2)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(battleSize == bs ? Color.accent : Color.bgElevated)
                                        .foregroundStyle(battleSize == bs ? Color.white : Color.inkDim)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }
                        }
                        labeled("Phase Label") {
                            TextField("Campaign Turn", text: $phaseLabel)
                                .padding(10).background(Color.bgElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }

                CardBox {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What happens next").font(.caption.weight(.semibold)).foregroundStyle(Color.inkFade)
                        Text("• Campaign starts in setup state — no battles yet.\n• Invite players via the Members tab.\n• Each player creates their own Crusade Force (one faction per user).\n• When ≥2 forces are ready, hit Start.").font(.caption).foregroundStyle(Color.inkDim)
                    }
                }

                if let error { ErrorBanner(message: error) }

                Button {
                    Task { await create() }
                } label: {
                    HStack {
                        if busy { ProgressView().tint(.white) }
                        Text(busy ? "Creating…" : "Create Crusade")
                    }
                }
                .buttonStyle(PrimaryButtonStyle(enabled: !busy && !name.isEmpty))
                .disabled(busy || name.isEmpty)
            }
            .padding()
        }
        .background(Color.bg.ignoresSafeArea())
        .navigationTitle("New Crusade")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
    }

    private func labeled<V: View>(_ label: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.medium)).foregroundStyle(Color.inkDim)
            content()
        }
    }

    private func create() async {
        error = nil; busy = true
        defer { busy = false }
        do {
            let c = try await APIClient.shared.createCampaign(
                name: name.trimmingCharacters(in: .whitespaces),
                description: description,
                phaseLabel: phaseLabel,
                battleSize: battleSize
            )
            onCreated(c)
        } catch let e as APIError { error = e.message }
        catch let e { self.error = e.localizedDescription }
    }
}
