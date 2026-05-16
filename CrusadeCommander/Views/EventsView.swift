import SwiftUI

// MembersPanel: list members, generate / list invites (admin only).

struct MembersPanel: View {
    let campaignId: String
    let currentUserId: String
    let isAdmin: Bool

    @State private var members: [APIMember] = []
    @State private var invites: [APIInvite] = []
    @State private var loading = true
    @State private var error: String?
    @State private var showCreate = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if loading {
                ProgressView().tint(.accent).frame(maxWidth: .infinity).padding(.top, 20)
            } else {
                CardBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("MEMBERS (\(members.count))").font(.caption.weight(.semibold)).foregroundStyle(Color.inkFade)
                        ForEach(members) { m in
                            HStack {
                                Circle().fill(Color.bgElevated).frame(width: 28, height: 28)
                                    .overlay(Text(String(m.display_name.isEmpty ? m.email.prefix(1) : m.display_name.prefix(1)).uppercased()).font(.caption.weight(.bold)))
                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(spacing: 4) {
                                        Text(m.display_name.isEmpty ? m.email : m.display_name).font(.caption.weight(.medium))
                                        if m.user_id == currentUserId {
                                            Text("(you)").font(.caption2).foregroundStyle(Color.inkFade)
                                        }
                                    }
                                    Text(m.email).font(.caption2).foregroundStyle(Color.inkFade)
                                }
                                Spacer()
                                BadgeView(text: m.role, style: m.role == "owner" ? .accent : m.role == "admin" ? .warning : .dim)
                            }.padding(.vertical, 2)
                        }
                    }
                }

                if isAdmin {
                    CardBox {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("INVITES").font(.caption.weight(.semibold)).foregroundStyle(Color.inkFade)
                                Spacer()
                                Button { showCreate = true } label: {
                                    Label("New", systemImage: "plus")
                                        .font(.caption.weight(.medium))
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .background(Color.accent).foregroundStyle(.white)
                                        .clipShape(Capsule())
                                }
                            }
                            if invites.isEmpty {
                                Text("No active invites.").font(.caption).foregroundStyle(Color.inkFade)
                            } else {
                                ForEach(invites) { i in
                                    inviteRow(i)
                                }
                            }
                        }
                    }
                } else {
                    CardBox {
                        Text("Ask an admin to share an invite code so more players can join.")
                            .font(.caption).foregroundStyle(Color.inkFade)
                    }
                }
                if let error { ErrorBanner(message: error) }
            }
        }
        .task { await load() }
        .sheet(isPresented: $showCreate) {
            NavigationStack {
                CreateInviteSheet(campaignId: campaignId, onCreated: {
                    showCreate = false
                    Task { await load() }
                })
            }
        }
    }

    private func inviteRow(_ i: APIInvite) -> some View {
        let link = i.share_url ?? "/invite/\(i.code)"
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(i.code).font(.system(.subheadline, design: .monospaced).weight(.bold)).foregroundStyle(Color.accent)
                BadgeView(text: i.role_on_accept, style: i.role_on_accept == "admin" ? .warning : .dim)
                Text("\(i.times_used)/\(i.max_uses)").font(.caption2).foregroundStyle(Color.inkFade)
                Spacer()
                Button {
                    UIPasteboard.general.string = link
                } label: {
                    Image(systemName: "doc.on.doc").font(.caption).foregroundStyle(Color.inkFade)
                }
            }
            Text(link)
                .font(.caption2.monospaced())
                .foregroundStyle(Color.inkFade)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.bgElevated)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .textSelection(.enabled)
            if !i.label.isEmpty {
                Text(i.label).font(.caption2).foregroundStyle(Color.inkFade)
            }
        }
        .padding(.vertical, 4)
    }

    private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do {
            async let m = APIClient.shared.listMembers(campaignId)
            async let i = isAdmin ? APIClient.shared.listInvites(campaignId) : []
            let (mm, ii) = try await (m, i)
            self.members = mm; self.invites = ii
        } catch let e as APIError { error = e.message }
        catch let e { self.error = e.localizedDescription }
    }
}

struct CreateInviteSheet: View {
    @Environment(\.dismiss) private var dismiss
    let campaignId: String
    let onCreated: () -> Void

    @State private var role = "participant"
    @State private var label = ""
    @State private var maxUses = 1
    @State private var expiresHours: Int? = 168
    @State private var busy = false
    @State private var error: String?
    @State private var created: APIInvite?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let invite = created {
                    CardBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Invite created").font(.subheadline.weight(.semibold)).foregroundStyle(Color.successC)
                            Text("Code").font(.caption2).foregroundStyle(Color.inkFade)
                            Text(invite.code).font(.title3.monospaced().weight(.bold)).foregroundStyle(Color.accent).textSelection(.enabled)
                            Text("Share link").font(.caption2).foregroundStyle(Color.inkFade)
                            Text(invite.share_url ?? "/invite/\(invite.code)")
                                .font(.caption2.monospaced()).foregroundStyle(Color.inkDim)
                                .padding(6).background(Color.bgElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .textSelection(.enabled)
                            Button("Copy link") {
                                UIPasteboard.general.string = invite.share_url ?? "/invite/\(invite.code)"
                            }.buttonStyle(SecondaryButtonStyle())
                        }
                    }
                    Button("Done") { dismiss(); onCreated() }.buttonStyle(PrimaryButtonStyle())
                } else {
                    CardBox {
                        VStack(alignment: .leading, spacing: 12) {
                            labeled("Role on accept") {
                                Picker("", selection: $role) {
                                    Text("Participant").tag("participant")
                                    Text("Admin").tag("admin")
                                }.pickerStyle(.segmented)
                            }
                            labeled("Label (optional)") {
                                TextField("e.g. For Bob", text: $label)
                                    .padding(10).background(Color.bgElevated)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            labeled("Max uses: \(maxUses)") {
                                Stepper("", value: $maxUses, in: 1...50).labelsHidden()
                            }
                        }
                    }
                    if let error { ErrorBanner(message: error) }
                    Button {
                        Task { await create() }
                    } label: {
                        HStack {
                            if busy { ProgressView().tint(.white) }
                            Text(busy ? "Generating…" : "Generate Invite")
                        }
                    }.buttonStyle(PrimaryButtonStyle(enabled: !busy)).disabled(busy)
                }
            }.padding()
        }
        .background(Color.bg.ignoresSafeArea())
        .navigationTitle(created == nil ? "New Invite" : "Invite Created")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
    }

    private func labeled<V: View>(_ label: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.medium)).foregroundStyle(Color.inkDim)
            content()
        }
    }

    private func create() async {
        busy = true; error = nil
        defer { busy = false }
        do {
            let i = try await APIClient.shared.createInvite(
                campaignId, role: role, label: label, maxUses: maxUses, expiresInHours: expiresHours
            )
            self.created = i
        } catch let e as APIError { error = e.message }
        catch let e { self.error = e.localizedDescription }
    }
}
