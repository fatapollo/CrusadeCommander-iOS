import SwiftUI

// Read-only sector map. Mirrors the React `MapMobile` layout:
//   Phase strip → static map → holdings grid → owner-grouped node list.
// No pan / zoom / builder — iOS is read-only in parity with the
// design-handoff mobile branch.

private let MAP_W: CGFloat = 1000
private let MAP_H: CGFloat = 700
private let NEUTRAL_COLOR = Color(hex: "5c5346")
private let CONTESTED_COLOR = Color(hex: "f4c14b")

struct SectorMapPanel: View {
    let campaign: APICampaign
    let forces: [APIForce]

    var body: some View {
        if let map = campaign.sector_map, !map.nodes.isEmpty {
            SectorMapBody(map: map, forces: forces,
                          phases: campaign.phases ?? [.init(idx: 1, label: campaign.phase_label, date: nil, pending: nil)],
                          currentPhase: campaign.current_phase)
        } else {
            EmptyStateView(
                icon: "◷",
                title: "No sector charted yet",
                subtitle: "Once an admin builds the sector on the desktop, this view will track holdings and contested worlds."
            )
        }
    }
}

private struct SectorMapBody: View {
    let map: APISectorMap
    let forces: [APIForce]
    let phases: [APICampaignPhase]
    let currentPhase: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            phaseStrip
            staticMap
            holdingsGrid
            nodeList
        }
    }

    // MARK: - Phase strip
    private var phaseStrip: some View {
        let meta = phases.first(where: { $0.idx == currentPhase }) ?? phases.last
        return CardBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("// CURRENT PHASE")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.accent)
                HStack(spacing: 3) {
                    ForEach(phases, id: \.idx) { p in
                        Rectangle()
                            .fill(p.idx < currentPhase ? Color.accent.opacity(0.5)
                                  : p.idx == currentPhase ? Color.accent
                                  : Color.bgElevated)
                            .frame(height: 6)
                    }
                }
                Text((meta?.label ?? "Phase \(currentPhase)").uppercased())
                    .font(.headline.weight(.bold))
                Text("\(String(format: "%02d", currentPhase)) / \(String(format: "%02d", max(1, phases.count)))" +
                     (meta?.date.map { " · \($0)" } ?? ""))
                    .font(.caption2)
                    .foregroundStyle(Color.inkFade)
            }
        }
    }

    // MARK: - Static map (SwiftUI Canvas)
    private var staticMap: some View {
        CardBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("// SECTOR · STATIC VIEW")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.accent)
                Canvas { ctx, size in
                    let sx = size.width / MAP_W
                    let sy = size.height / MAP_H
                    // edges
                    for edge in map.edges where edge.count == 2 {
                        guard
                            let a = map.nodes.first(where: { $0.id == edge[0] }),
                            let b = map.nodes.first(where: { $0.id == edge[1] })
                        else { continue }
                        let oa = a.owner(atPhase: currentPhase)
                        let ob = b.owner(atPhase: currentPhase)
                        let sharedReal = oa == ob && oa != "NEUTRAL" && oa != "CONTESTED"
                        let stroke = sharedReal ? colorForOwner(oa) : Color(hex: "2e251e")
                        let dashed = oa == "NEUTRAL" || ob == "NEUTRAL"
                        var path = Path()
                        path.move(to: CGPoint(x: a.pos.x * sx, y: a.pos.y * sy))
                        path.addLine(to: CGPoint(x: b.pos.x * sx, y: b.pos.y * sy))
                        ctx.stroke(path, with: .color(stroke.opacity(0.85)),
                                   style: StrokeStyle(lineWidth: 1.5,
                                                      dash: dashed ? [4, 3] : []))
                    }
                    // nodes
                    for n in map.nodes {
                        let owner = n.owner(atPhase: currentPhase)
                        let c = colorForOwner(owner)
                        let x = n.pos.x * sx, y = n.pos.y * sy
                        let chip = CGRect(x: x - 14, y: y - 14, width: 28, height: 28)
                        ctx.fill(Path(chip), with: .color(owner == "NEUTRAL" ? Color(hex: "161310") : c))
                        ctx.stroke(Path(chip), with: .color(Color(hex: "06040a")), lineWidth: 1.5)
                        let accent = CGRect(x: x - 14, y: y - 14, width: 4, height: 28)
                        ctx.fill(Path(accent), with: .color(c))
                        if n.isObjective {
                            ctx.stroke(Path(ellipseIn: CGRect(x: x - 22, y: y - 22, width: 44, height: 44)),
                                       with: .color(CONTESTED_COLOR),
                                       style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                        }
                        if owner == "CONTESTED" {
                            ctx.stroke(Path(CGRect(x: x - 18, y: y - 18, width: 36, height: 36)),
                                       with: .color(CONTESTED_COLOR),
                                       style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        }
                    }
                }
                .aspectRatio(MAP_W / MAP_H, contentMode: .fit)
                .background(Color(hex: "06040a"))
                .overlay(Rectangle().stroke(Color.white.opacity(0.06)))
                Text("STATIC ON MOBILE · OPEN ON DESKTOP TO EXPLORE")
                    .font(.caption2)
                    .foregroundStyle(Color.inkFade)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    // MARK: - Holdings grid
    private var holdingsGrid: some View {
        let counts = ownerCounts()
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 1),
                                   GridItem(.flexible(), spacing: 1)],
                         spacing: 1) {
            ForEach(counts, id: \.0) { (owner, count) in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Rectangle().fill(colorForOwner(owner)).frame(width: 10, height: 10)
                        Text(labelForOwner(owner).uppercased())
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.inkFade)
                    }
                    Text(String(format: "%02d", count))
                        .font(.title2.weight(.bold))
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.bgElevated)
            }
        }
        .background(Color.white.opacity(0.05))
    }

    // MARK: - Owner-grouped node list
    private var nodeList: some View {
        let grouped = ownerCounts().filter { $0.1 > 0 }
        return CardBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("// NODES · \(map.nodes.count) TOTAL")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.accent)
                ForEach(grouped, id: \.0) { (owner, count) in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Rectangle().fill(colorForOwner(owner)).frame(width: 12, height: 12)
                            Text(labelForOwner(owner).uppercased())
                                .font(.caption.weight(.semibold))
                            Text("× \(count)")
                                .font(.caption2)
                                .foregroundStyle(Color.inkFade)
                        }
                        ForEach(map.nodes.filter { $0.owner(atPhase: currentPhase) == owner }) { n in
                            HStack(spacing: 8) {
                                Rectangle().fill(colorForOwner(owner)).frame(width: 3, height: 28)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(n.name.uppercased()).font(.subheadline.weight(.semibold))
                                    Text(n.type.label.uppercased() +
                                         ((n.battles?.count ?? 0) > 0
                                            ? " · \(n.battles!.count) battle\(n.battles!.count == 1 ? "" : "s")"
                                            : ""))
                                        .font(.caption2)
                                        .foregroundStyle(Color.inkFade)
                                }
                                Spacer()
                                if n.isObjective {
                                    Text("OBJ")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(CONTESTED_COLOR)
                                        .padding(.horizontal, 4).padding(.vertical, 1)
                                        .overlay(Rectangle().stroke(CONTESTED_COLOR, lineWidth: 1))
                                }
                                Text("\(n.value)").font(.headline.weight(.bold))
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background(Color.bgElevated)
                        }
                    }
                }
            }
        }
    }

    // MARK: - helpers
    private func colorForOwner(_ owner: String) -> Color {
        if owner == "NEUTRAL" { return NEUTRAL_COLOR }
        if owner == "CONTESTED" { return CONTESTED_COLOR }
        if let f = forces.first(where: { $0.id == owner }) { return Color(hex: f.color_hex) }
        return NEUTRAL_COLOR
    }
    private func labelForOwner(_ owner: String) -> String {
        if owner == "NEUTRAL" { return "Neutral" }
        if owner == "CONTESTED" { return "Contested" }
        return forces.first(where: { $0.id == owner })?.name ?? "Unknown"
    }
    /// Ordered: real forces (in their natural order) → CONTESTED → NEUTRAL,
    /// dropping owners with zero nodes.
    private func ownerCounts() -> [(String, Int)] {
        var counts: [String: Int] = [:]
        for n in map.nodes {
            let o = n.owner(atPhase: currentPhase)
            counts[o, default: 0] += 1
        }
        var ordered: [(String, Int)] = []
        for f in forces {
            if let c = counts[f.id], c > 0 { ordered.append((f.id, c)) }
        }
        if let c = counts["CONTESTED"], c > 0 { ordered.append(("CONTESTED", c)) }
        if let c = counts["NEUTRAL"], c > 0 { ordered.append(("NEUTRAL", c)) }
        return ordered
    }
}
