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
}

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
