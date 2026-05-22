import Foundation

// MARK: - API Codable types (mirrors the backend src/types.ts)

struct APIUser: Codable, Identifiable, Hashable {
    let id: String
    let email: String
    let display_name: String
    let created_at: String
    let is_site_admin: Bool
}

struct AuthConfigMeta: Codable {
    let admin_passcode_enabled: Bool
}

enum BattleSize: String, Codable, CaseIterable, Identifiable {
    case incursion = "Incursion"
    case strikeForce = "Strike Force"
    case onslaught = "Onslaught"
    var id: String { rawValue }
    var pointsLabel: String {
        switch self {
        case .incursion: return "1000 pts"
        case .strikeForce: return "2000 pts"
        case .onslaught: return "3000 pts"
        }
    }
}

enum CampaignState: String, Codable {
    case setup
    case active
    case concluded
}

enum CampaignRole: String, Codable {
    case owner
    case admin
    case participant
}

struct APICampaign: Codable, Identifiable, Hashable {
    let id: String
    let owner_id: String
    let name: String
    let description: String
    let is_active: Bool
    let current_phase: Int
    let phase_label: String
    let default_battle_size: BattleSize
    let state: CampaignState
    let started_at: String?
    let concluded_at: String?
    let created_at: String
    let updated_at: String
    // Computed aggregates (present on newer backends; optional for tolerance).
    let force_count: Int?
    let unit_count: Int?
    let battle_count: Int?
    let power_rating: Int?
    // Sector map + phases (added in the desktop sector-map slice; iOS reads
    // them read-only).
    let phases: [APICampaignPhase]?
    let sector_map: APISectorMap?
}

struct APICampaignPhase: Codable, Hashable {
    let idx: Int
    let label: String
    let date: String?
    let pending: Bool?
}

enum APINodeType: String, Codable {
    case hive = "HIVE", forge = "FORGE", port = "PORT", relic = "RELIC"
    case strong = "STRONG", wild = "WILD", obj = "OBJ"

    var label: String {
        switch self {
        case .hive: return "Hive World"
        case .forge: return "Forge World"
        case .port: return "Spaceport"
        case .relic: return "Relic Site"
        case .strong: return "Stronghold"
        case .wild: return "Wilderness"
        case .obj: return "Objective"
        }
    }
    var glyph: String {
        switch self {
        case .hive: return "H"; case .forge: return "F"; case .port: return "P"
        case .relic: return "R"; case .strong: return "S"; case .wild: return "W"
        case .obj: return "Ω"
        }
    }
}

struct APISectorPos: Codable, Hashable { let x: Double; let y: Double }

struct APISectorHistory: Codable, Hashable { let phase: Int; let event: String }

struct APISectorNode: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let type: APINodeType
    let pos: APISectorPos
    let value: Int
    let traits: [String]
    let owners: [String]       // each entry is a force id, "NEUTRAL", or "CONTESTED"
    let isObjective: Bool
    let history: [APISectorHistory]?
    let battles: [String]?

    /// Carry-forward ownership lookup matching backend semantics.
    func owner(atPhase phase: Int) -> String {
        guard !owners.isEmpty else { return "NEUTRAL" }
        let idx = max(0, min(owners.count - 1, phase - 1))
        return owners[idx]
    }
}

struct APISectorMap: Codable, Hashable {
    let nodes: [APISectorNode]
    let edges: [[String]]      // each inner array is [aId, bId]
}

struct APIForce: Codable, Identifiable, Hashable {
    let id: String
    let campaign_id: String
    let user_id: String?
    var name: String
    var player_name: String
    var faction: String
    var team: String
    var color_hex: String
    var supply_limit: Int
    var requisition_points: Int
    var battle_tally: Int
    var victories: Int
    var notes: String
    var is_active: Bool
    var dropped_at: String?
    let created_at: String
    var commander: String?
    var motto: String?
    let unit_count: Int?
    let power_rating: Int?
    let wins: Int?
    let losses: Int?
    let draws: Int?
}

enum Rank: String {
    case battleReady = "Battle-ready"
    case blooded = "Blooded"
    case battleHardened = "Battle-hardened"
    case heroic = "Heroic"
    case legendary = "Legendary"

    static func from(xp: Int, isCharacter: Bool, canExceed30: Bool) -> Rank {
        if xp <= 5 { return .battleReady }
        if xp <= 15 { return .blooded }
        if xp <= 30 { return .battleHardened }
        if xp <= 50 { return (isCharacter || canExceed30) ? .heroic : .battleHardened }
        return (isCharacter || canExceed30) ? .legendary : .battleHardened
    }
}

struct APIUnit: Codable, Identifiable, Hashable {
    let id: String
    let force_id: String
    var name: String
    var datasheet: String
    var points_cost: Int
    var equipment: String
    var is_character: Bool
    var is_titanic: Bool
    var is_epic_hero: Bool
    var is_fortification: Bool
    var is_swarm: Bool
    var xp: Int
    var crusade_points: Int
    var battles_played: Int
    var battles_survived: Int
    var units_destroyed: Int
    var can_exceed_30_xp: Bool
    var is_active: Bool
    var notes: String
    let created_at: String
    var unit_type: String?
    var status: String?
    let honour_available: Int?

    var rank: Rank { Rank.from(xp: xp, isCharacter: is_character, canExceed30: can_exceed_30_xp) }
}

enum BattleOutcome: String, Codable, CaseIterable, Identifiable {
    case attackerWins = "Attacker Wins"
    case defenderWins = "Defender Wins"
    case draw = "Draw"
    var id: String { rawValue }
}

enum BattleStatus: String, Codable {
    case pending, confirmed, disputed, cancelled
}

struct APIBattle: Codable, Identifiable, Hashable {
    let id: String
    let campaign_id: String
    let battle_size: BattleSize
    let mission_name: String
    let attacker_force_id: String
    let defender_force_id: String
    let outcome: BattleOutcome
    let notes: String
    let campaign_phase: Int
    let occurred_at: String
    let status: BattleStatus
    let submitted_by_user_id: String?
    let confirmed_by_user_id: String?
    let confirmed_at: String?
    let dispute_reason: String
    let attacker_score: Int?
    let defender_score: Int?
    let deployment: String?
    let duration_turns: Int?
    let opposing_commander: String?
    // Sector-map linkage (optional; older backends omit these).
    let contesting_node_id: String?
    let claim_node_on_win: Bool?
}

struct APIHonour: Codable, Identifiable, Hashable {
    let id: String
    let unit_id: String
    let category: String
    let name: String
    let description: String
    let weapon_name: String
    let relic_category: String?
    let crusade_points_value: Int
    let earned_at: String
}

struct APIScar: Codable, Identifiable, Hashable {
    let id: String
    let unit_id: String
    let name: String
    let description: String
    let earned_at: String
}

struct UnitDetailResponse: Codable {
    let unit: APIUnit
    let honours: [APIHonour]
    let scars: [APIScar]
    let honour_available: Int?
}

struct RequisitionLogItem: Codable, Identifiable, Hashable {
    let id: String
    let force_id: String
    let requisition_name: String
    let cost_paid: Int
    let target_unit_id: String?
    let notes: String
    let used_at: String
}

struct RequisitionResult: Codable {
    let force: APIForce
}

struct RequisitionLogResponse: Codable { let log: [RequisitionLogItem] }

struct APIInvite: Codable, Identifiable, Hashable {
    let id: String
    let campaign_id: String
    let code: String
    let role_on_accept: String
    let label: String
    let max_uses: Int
    let times_used: Int
    let expires_at: String?
    let created_at: String
    let share_url: String?
}

struct APIInvitePreview: Codable {
    struct Campaign: Codable { let id: String; let name: String; let description: String }
    let campaign: Campaign
    let role: String
    let label: String
    let remaining_uses: Int
}

struct APIMember: Codable, Identifiable, Hashable {
    var id: String { user_id }
    let user_id: String
    let email: String
    let display_name: String
    let role: String
    let joined_at: String
}

// MARK: - Response envelopes

struct CampaignsListResponse: Codable { let campaigns: [APICampaign] }
struct CampaignResponse: Codable { let campaign: APICampaign; let role: CampaignRole? }
struct CampaignCreatedResponse: Codable { let campaign: APICampaign }
struct ForcesListResponse: Codable { let forces: [APIForce] }
struct ForceResponse: Codable { let force: APIForce }
struct UnitsListResponse: Codable { let units: [APIUnit] }
struct UnitResponse: Codable { let unit: APIUnit }
struct BattlesListResponse: Codable { let battles: [APIBattle] }
struct InvitesListResponse: Codable { let invites: [APIInvite] }
struct InviteCreatedResponse: Codable { let invite: APIInvite }
struct MembersListResponse: Codable { let members: [APIMember] }
struct AuthResponse: Codable { let user: APIUser }
struct MeResponse: Codable { let user: APIUser; let config_meta: AuthConfigMeta? }
struct AuthConfigResponse: Codable { let admin_passcode_enabled: Bool }
