import Foundation

/// Reusable authentication profile that can be applied to multiple sessions.
/// Changing the profile updates all associated sessions.
struct AuthProfile: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var authMethod: AuthMethod = .key
    var username: String = ""
    var privateKeyPath: String?
    var useAgent: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

/// Manages auth profiles, persisted to UserDefaults
final class AuthProfileManager: ObservableObject {
    @Published var profiles: [AuthProfile] = []
    private let key = "GhostX.authProfiles"
    private let defaults = UserDefaults.standard

    init() {
        if let data = defaults.data(forKey: key),
           let saved = try? JSONDecoder().decode([AuthProfile].self, from: data) {
            profiles = saved
        }
    }

    func save(_ profile: AuthProfile) {
        var p = profile
        p.updatedAt = Date()
        if let idx = profiles.firstIndex(where: { $0.id == p.id }) {
            profiles[idx] = p
        } else {
            profiles.append(p)
        }
        persist()

        // Propagate changes to all sessions using this profile
        if let repo = sessionRepo {
            for (i, var session) in repo.sessions.enumerated()
                where session.authProfileID == p.id {
                session.username = p.username
                session.authMethod = p.authMethod
                session.privateKeyPath = p.privateKeyPath
                try? repo.save(session)
            }
        }
    }

    func delete(id: UUID) {
        profiles.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(profiles) {
            defaults.set(data, forKey: key)
        }
    }

    /// Weak reference set by the app
    weak var sessionRepo: SessionRepository?
}
