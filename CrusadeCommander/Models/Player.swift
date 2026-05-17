import Foundation
import SwiftUI

// MARK: - Server URL persistence

@MainActor
final class ServerSettings: ObservableObject {
    @Published var serverURL: URL? {
        didSet {
            UserDefaults.standard.set(serverURL?.absoluteString, forKey: "serverURL")
        }
    }

    init() {
        if let raw = UserDefaults.standard.string(forKey: "serverURL"), let url = URL(string: raw) {
            self.serverURL = url
        }
    }

    /// True if a usable server URL is configured.
    var isConfigured: Bool { serverURL != nil }

    /// Reset stored credentials and host (used by Sign out → Change server).
    func clearServer() {
        serverURL = nil
        APIClient.shared.clearCookies()
    }
}

// MARK: - Error type

struct APIError: LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { message }
}

// MARK: - APIClient

/// Cookie-session based HTTP client that talks to the Crusade Commander backend.
/// Server URL is supplied by ServerSettings. URLSession's shared HTTPCookieStorage
/// persists the session cookie across app restarts.
@MainActor
final class APIClient {
    static let shared = APIClient()

    var baseURL: URL?

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.httpCookieAcceptPolicy = .always
        cfg.httpShouldSetCookies = true
        cfg.httpCookieStorage = HTTPCookieStorage.shared
        return URLSession(configuration: cfg)
    }()

    func setBaseURL(_ url: URL) { self.baseURL = url }

    func clearCookies() {
        guard let storage = session.configuration.httpCookieStorage else { return }
        storage.cookies?.forEach { storage.deleteCookie($0) }
    }

    /// Perform a JSON request. Empty body when no `body` provided.
    func request<T: Decodable>(
        _ method: String,
        _ path: String,
        body: Encodable? = nil,
        decode: T.Type = T.self
    ) async throws -> T {
        guard let base = baseURL else {
            throw APIError(status: 0, message: "No server configured")
        }
        let url = base.appendingPathComponent(path.hasPrefix("/") ? String(path.dropFirst()) : path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body = body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        }
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw APIError(status: 0, message: "No HTTP response")
        }
        if !(200...299).contains(http.statusCode) {
            let msg = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data).error) ?? "HTTP \(http.statusCode)"
            throw APIError(status: http.statusCode, message: msg)
        }
        if T.self == EmptyResponse.self {
            return EmptyResponse() as! T
        }
        if data.isEmpty {
            return EmptyResponse() as! T
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func get<T: Decodable>(_ path: String) async throws -> T {
        try await request("GET", path)
    }
    func post<T: Decodable>(_ path: String, body: Encodable? = nil) async throws -> T {
        try await request("POST", path, body: body)
    }
    func patch<T: Decodable>(_ path: String, body: Encodable) async throws -> T {
        try await request("PATCH", path, body: body)
    }
    func delete<T: Decodable>(_ path: String) async throws -> T {
        try await request("DELETE", path)
    }
}

struct EmptyResponse: Decodable {}
private struct ErrorEnvelope: Decodable { let error: String }

/// Type-erased Encodable wrapper so we can accept heterogenous bodies.
private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    init(_ wrapped: Encodable) { self._encode = wrapped.encode }
    func encode(to encoder: Encoder) throws { try _encode(encoder) }
}

// MARK: - Endpoint helpers

extension APIClient {
    // Auth
    struct LoginBody: Encodable { let email: String; let password: String }
    struct RegisterBody: Encodable {
        let email: String; let password: String; let display_name: String
        let admin_passcode: String?
    }

    func login(email: String, password: String) async throws -> APIUser {
        let r: AuthResponse = try await post("/api/auth/login", body: LoginBody(email: email, password: password))
        return r.user
    }

    func register(email: String, password: String, displayName: String, adminPasscode: String?) async throws -> APIUser {
        let body = RegisterBody(email: email, password: password, display_name: displayName, admin_passcode: adminPasscode?.isEmpty == false ? adminPasscode : nil)
        let r: AuthResponse = try await post("/api/auth/register", body: body)
        return r.user
    }

    func me() async throws -> MeResponse {
        try await get("/api/auth/me")
    }

    func logout() async throws {
        let _: EmptyResponse = try await post("/api/auth/logout")
    }

    func authConfig() async throws -> AuthConfigResponse {
        try await get("/api/auth/config")
    }

    // Campaigns
    func listCampaigns() async throws -> [APICampaign] {
        let r: CampaignsListResponse = try await get("/api/campaigns")
        return r.campaigns
    }

    struct CreateCampaignBody: Encodable {
        let name: String; let description: String
        let phase_label: String; let default_battle_size: String
    }

    func createCampaign(name: String, description: String, phaseLabel: String, battleSize: BattleSize) async throws -> APICampaign {
        let r: CampaignCreatedResponse = try await post("/api/campaigns",
            body: CreateCampaignBody(name: name, description: description, phase_label: phaseLabel, default_battle_size: battleSize.rawValue))
        return r.campaign
    }

    func getCampaign(_ id: String) async throws -> CampaignResponse {
        try await get("/api/campaigns/\(id)")
    }

    func startCampaign(_ id: String) async throws -> APICampaign {
        let r: CampaignCreatedResponse = try await post("/api/campaigns/\(id)/start")
        return r.campaign
    }
    func concludeCampaign(_ id: String) async throws -> APICampaign {
        let r: CampaignCreatedResponse = try await post("/api/campaigns/\(id)/conclude")
        return r.campaign
    }
    func reopenCampaign(_ id: String) async throws -> APICampaign {
        let r: CampaignCreatedResponse = try await post("/api/campaigns/\(id)/reopen")
        return r.campaign
    }

    // Forces
    func listForces(_ campaignId: String) async throws -> [APIForce] {
        let r: ForcesListResponse = try await get("/api/campaigns/\(campaignId)/forces")
        return r.forces
    }
    struct CreateForceBody: Encodable {
        let name: String; let player_name: String; let faction: String
        let team: String; let color_hex: String
    }
    func createForce(_ campaignId: String, name: String, playerName: String, faction: String, team: String, colorHex: String) async throws -> APIForce {
        let r: ForceResponse = try await post("/api/campaigns/\(campaignId)/forces",
            body: CreateForceBody(name: name, player_name: playerName, faction: faction, team: team, color_hex: colorHex))
        return r.force
    }
    func dropForce(_ campaignId: String, _ forceId: String) async throws {
        let _: ForceResponse = try await post("/api/campaigns/\(campaignId)/forces/\(forceId)/drop")
    }
    func rejoinForce(_ campaignId: String, _ forceId: String) async throws {
        let _: ForceResponse = try await post("/api/campaigns/\(campaignId)/forces/\(forceId)/rejoin")
    }

    // Units
    func listUnits(_ campaignId: String, forceId: String) async throws -> [APIUnit] {
        let r: UnitsListResponse = try await get("/api/campaigns/\(campaignId)/forces/\(forceId)/units")
        return r.units
    }
    struct CreateUnitBody: Encodable {
        let name: String; let datasheet: String; let points_cost: Int; let equipment: String
        let is_character: Bool; let is_titanic: Bool; let is_epic_hero: Bool
    }
    func createUnit(_ campaignId: String, forceId: String, name: String, datasheet: String, pointsCost: Int, equipment: String, isCharacter: Bool, isTitanic: Bool, isEpicHero: Bool) async throws -> APIUnit {
        let r: UnitResponse = try await post("/api/campaigns/\(campaignId)/forces/\(forceId)/units",
            body: CreateUnitBody(name: name, datasheet: datasheet, points_cost: pointsCost, equipment: equipment, is_character: isCharacter, is_titanic: isTitanic, is_epic_hero: isEpicHero))
        return r.unit
    }
    func deleteUnit(_ campaignId: String, unitId: String) async throws {
        let _: EmptyResponse = try await delete("/api/campaigns/\(campaignId)/units/\(unitId)")
    }
    func getUnitDetail(_ campaignId: String, unitId: String) async throws -> UnitDetailResponse {
        try await get("/api/campaigns/\(campaignId)/units/\(unitId)")
    }
    struct UpdateUnitBody: Encodable { let unit_type: String?; let status: String? }
    func updateUnit(_ campaignId: String, unitId: String, unitType: String?, status: String?) async throws -> APIUnit {
        let r: UnitResponse = try await patch("/api/campaigns/\(campaignId)/units/\(unitId)",
            body: UpdateUnitBody(unit_type: unitType, status: status))
        return r.unit
    }
    struct AddHonourBody: Encodable {
        let category: String; let name: String; let description: String
        let weapon_name: String; let relic_category: String?
    }
    struct HonourResponse: Decodable { let honour: APIHonour }
    func addHonour(_ campaignId: String, unitId: String, category: String, name: String,
                   description: String, weaponName: String, relicCategory: String?) async throws {
        let _: HonourResponse = try await post("/api/campaigns/\(campaignId)/units/\(unitId)/honours",
            body: AddHonourBody(category: category, name: name, description: description,
                                weapon_name: weaponName, relic_category: relicCategory))
    }
    func removeHonour(_ campaignId: String, unitId: String, honourId: String) async throws {
        let _: EmptyResponse = try await delete("/api/campaigns/\(campaignId)/units/\(unitId)/honours/\(honourId)")
    }
    struct AddScarBody: Encodable { let name: String; let description: String }
    struct ScarResponse: Decodable { let scar: APIScar }
    func addScar(_ campaignId: String, unitId: String, name: String) async throws {
        let _: ScarResponse = try await post("/api/campaigns/\(campaignId)/units/\(unitId)/scars",
            body: AddScarBody(name: name, description: ""))
    }
    func removeScar(_ campaignId: String, unitId: String, scarId: String) async throws {
        let _: EmptyResponse = try await delete("/api/campaigns/\(campaignId)/units/\(unitId)/scars/\(scarId)")
    }

    // Requisitions
    func requisitionLog(_ campaignId: String, forceId: String) async throws -> [RequisitionLogItem] {
        let r: RequisitionLogResponse = try await get("/api/campaigns/\(campaignId)/requisitions/\(forceId)/log")
        return r.log
    }
    func reqIncreaseSupplyLimit(_ campaignId: String, forceId: String) async throws -> APIForce {
        let r: RequisitionResult = try await post("/api/campaigns/\(campaignId)/requisitions/\(forceId)/increase-supply-limit")
        return r.force
    }
    struct RenownedHeroesBody: Encodable { let unit_id: String; let enhancement_name: String; let description: String }
    func reqRenownedHeroes(_ campaignId: String, forceId: String, unitId: String, name: String, description: String) async throws -> APIForce {
        let r: RequisitionResult = try await post("/api/campaigns/\(campaignId)/requisitions/\(forceId)/renowned-heroes",
            body: RenownedHeroesBody(unit_id: unitId, enhancement_name: name, description: description))
        return r.force
    }
    struct UnitIdBody: Encodable { let unit_id: String }
    func reqLegendaryVeterans(_ campaignId: String, forceId: String, unitId: String) async throws -> APIForce {
        let r: RequisitionResult = try await post("/api/campaigns/\(campaignId)/requisitions/\(forceId)/legendary-veterans",
            body: UnitIdBody(unit_id: unitId))
        return r.force
    }
    struct RearmBody: Encodable { let unit_id: String; let new_equipment: String; let new_points_cost: Int? }
    func reqRearmAndResupply(_ campaignId: String, forceId: String, unitId: String, equipment: String, pointsCost: Int?) async throws -> APIForce {
        let r: RequisitionResult = try await post("/api/campaigns/\(campaignId)/requisitions/\(forceId)/rearm-and-resupply",
            body: RearmBody(unit_id: unitId, new_equipment: equipment, new_points_cost: pointsCost))
        return r.force
    }
    struct ScarBody: Encodable { let unit_id: String; let scar_id: String }
    func reqRepairAndRecuperate(_ campaignId: String, forceId: String, unitId: String, scarId: String) async throws -> APIForce {
        let r: RequisitionResult = try await post("/api/campaigns/\(campaignId)/requisitions/\(forceId)/repair-and-recuperate",
            body: ScarBody(unit_id: unitId, scar_id: scarId))
        return r.force
    }
    struct FreshRecruitsBody: Encodable { let unit_id: String; let added_points: Int }
    func reqFreshRecruits(_ campaignId: String, forceId: String, unitId: String, addedPoints: Int) async throws -> APIForce {
        let r: RequisitionResult = try await post("/api/campaigns/\(campaignId)/requisitions/\(forceId)/fresh-recruits",
            body: FreshRecruitsBody(unit_id: unitId, added_points: addedPoints))
        return r.force
    }

    // Battles
    func listBattles(_ campaignId: String) async throws -> [APIBattle] {
        let r: BattlesListResponse = try await get("/api/campaigns/\(campaignId)/battles")
        return r.battles
    }
    struct CreateBattleBody: Encodable {
        let battle_size: String; let mission_name: String
        let deployment: String; let duration_turns: Int; let opposing_commander: String
        let attacker_force_id: String; let defender_force_id: String
        let outcome: String; let attacker_score: Int; let defender_score: Int
        let notes: String
    }
    struct BattleCreatedResponse: Decodable {
        let battle: APIBattle
        let needs_confirmation: Bool?
    }
    func createBattle(_ campaignId: String, battleSize: BattleSize, mission: String,
                      deployment: String, durationTurns: Int, opposingCommander: String,
                      attackerId: String, defenderId: String, outcome: BattleOutcome,
                      attackerScore: Int, defenderScore: Int, notes: String) async throws -> BattleCreatedResponse {
        try await post("/api/campaigns/\(campaignId)/battles", body: CreateBattleBody(
            battle_size: battleSize.rawValue, mission_name: mission,
            deployment: deployment, duration_turns: durationTurns, opposing_commander: opposingCommander,
            attacker_force_id: attackerId, defender_force_id: defenderId,
            outcome: outcome.rawValue, attacker_score: attackerScore, defender_score: defenderScore,
            notes: notes))
    }
    func confirmBattle(_ campaignId: String, _ battleId: String) async throws {
        let _: BattleCreatedResponse = try await post("/api/campaigns/\(campaignId)/battles/\(battleId)/confirm")
    }

    // Members + Invites
    func listMembers(_ campaignId: String) async throws -> [APIMember] {
        let r: MembersListResponse = try await get("/api/campaigns/\(campaignId)/members")
        return r.members
    }
    func listInvites(_ campaignId: String) async throws -> [APIInvite] {
        let r: InvitesListResponse = try await get("/api/campaigns/\(campaignId)/invites")
        return r.invites
    }
    struct CreateInviteBody: Encodable {
        let role_on_accept: String; let label: String; let max_uses: Int
        let expires_in_hours: Int?
    }
    func createInvite(_ campaignId: String, role: String, label: String, maxUses: Int, expiresInHours: Int?) async throws -> APIInvite {
        let r: InviteCreatedResponse = try await post("/api/campaigns/\(campaignId)/invites",
            body: CreateInviteBody(role_on_accept: role, label: label, max_uses: maxUses, expires_in_hours: expiresInHours))
        return r.invite
    }
    func previewInvite(_ code: String) async throws -> APIInvitePreview {
        try await get("/api/invites/\(code)")
    }
    struct InviteAcceptResponse: Decodable { let campaign_id: String; let role: String; let already_member: Bool }
    func acceptInvite(_ code: String) async throws -> InviteAcceptResponse {
        try await post("/api/invites/\(code)/accept")
    }
}
