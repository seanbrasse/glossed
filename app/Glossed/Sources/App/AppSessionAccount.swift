import DataKit
import Foundation

// The account-path helpers, split from `AppSession.swift` for the 300-line
// ceiling when the sign-out fix (#501) and the phone's account path (#499)
// met on `main` — a mechanical move, the same shape as `AppSessionAnchors`.

extension AppSession {
    /// `seed.sql`'s maya — the dev sign-in's user, and the one account a
    /// phone must never keep.
    static let seededDevUserID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")

    /// `GLOSSED_DEV_SIGN_IN=0` in the launch environment or, for a phone
    /// that launches with none, `GlossedDevSignIn` in the bundle.
    /// A release build has no dev sign-in at all: the person's own account
    /// or FLOW 1, which is what a TestFlight build needs to boot (GLO-50).
    static func devSignInIsOff(_ environment: [String: String]) -> Bool {
        #if DEBUG
            let fromEnvironment = environment["GLOSSED_DEV_SIGN_IN"]
            let fromBundle = Bundle.main.object(forInfoDictionaryKey: "GlossedDevSignIn") as? String
            return (fromEnvironment ?? fromBundle) == "0"
        #else
            _ = environment
            return true
        #endif
    }

    /// Nil profile means the quiz was never answered. The env override exists
    /// because both seeded accounts already have a profiles row (GLO-182), so
    /// without it the flow is unreachable in every drive this project makes.
    static func needsOnboarding(
        _ profiles: ProfileRepository, environment: [String: String]
    ) async throws -> Bool {
        if environment["GLOSSED_ONBOARDING"] == "1" {
            return true
        }
        return try await profiles.own() == nil
    }
}
