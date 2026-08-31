/// A field of the profile's identity block, editable from `edit profile`.
///
/// **Sean's ruling, Aug 31** (GLO-271, sweep finding 05): *"Edit profile
/// should allow users to update their bio, pfp, and maybe lock specific looks
/// and routines and collections as private."*
///
/// Name and bio are here because both editors already existed — `DisplayNameView`
/// and `BioView`, shipped under GLO-213 — reachable only through
/// settings → your profile. Nothing new is built; a second door opens onto
/// screens that already work.
///
/// **The photo is deliberately absent.** There is no photo column anywhere in
/// the schema: `profiles` carries `avatar_seed`, a seed for the drawn initial
/// avatar, and no URL — checked against the live database, not inferred. A
/// photo therefore needs a migration, and the migration slot was held when
/// this shipped. Adding a `photo` case here before that column exists would
/// be a door onto a room with no floor, which is the mistake GLO-189 named.
public enum ProfileIdentityField: String, CaseIterable, Identifiable, Sendable {
    case name
    case bio

    public var id: String {
        rawValue
    }

    /// Lowercase, per the house copy rule.
    var label: String {
        switch self {
        case .name: "your name"
        case .bio: "your bio"
        }
    }
}
