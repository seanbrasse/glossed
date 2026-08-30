import DataKit
import Foundation
import Observation

/// The account steps (`G.OnbAccount`): one decision per screen — method →
/// (phone → code) → birthday — and every screen backs up one. Apple skips
/// the phone pair; login mode skips the birthday and the quiz entirely
/// (returning users answer nothing again).
///
/// Auth MECHANICS are GLO-23's and absent here on purpose: the model talks
/// to seams (`AccountStore`) the app fills — with the dev session today,
/// with Apple/OTP when GLO-23 lands. What IS here is the ticket's gate:
/// the birthday is collected with the native wheel, under-13 is a typed
/// `under_age_minimum` rejection (PRD §17, COPPA), and account creation
/// batches the quiz's whole prior into one `ProfileDraft` write.
@MainActor
@Observable
public final class AccountModel {
    public enum Stage: String, Equatable {
        case method, phone, code, birthday
    }

    public enum Method: Equatable {
        case apple, phone
    }

    public enum Mode: Equatable {
        case signup, login
    }

    /// Where "back" from the method stage goes — the caller's screen, not
    /// ours (payoff on signup, the hook on login).
    public private(set) var stage = Stage.method
    public private(set) var method: Method?
    public var phoneNumber = ""
    public private(set) var codeDigits = ""
    public var birthday: Date?
    /// The typed under-13 rejection, set only by an attempted create —
    /// the screen renders its `userMessage`, never a raw string.
    public private(set) var ageError: GlossedError?
    public private(set) var isCreating = false
    /// The login path's terminal. Signup ends at `createAccount`'s
    /// `onCreated`; login had no equivalent, so `verifyCode` and
    /// `chooseApple` in `.login` mode set a stage they were already on and
    /// the returning user stopped dead on the code screen. The map's
    /// returning path is `log in → phone → code → straight to discover`, so
    /// the walk has to be able to SAY it is done — the caller reads this and
    /// lands them.
    public private(set) var isAuthenticated = false

    public let mode: Mode
    private let store: AccountStore?
    /// Injected so the age math is a fact in tests, not a race with the
    /// wall clock.
    private let today: Date
    var createTask: Task<Void, Never>?

    public init(mode: Mode = .signup, store: AccountStore? = nil, today: Date = Date()) {
        self.mode = mode
        self.store = store
        self.today = today
    }

    // MARK: - the walk

    public func chooseApple() {
        method = .apple
        // Login lands straight in — nothing re-asked. Signup still owes the
        // birthday, the one thing Apple cannot supply.
        if mode == .login {
            isAuthenticated = true
        } else {
            stage = .birthday
        }
    }

    public func choosePhone() {
        method = .phone
        stage = .phone
    }

    public func sendCode() {
        guard canSendCode else { return }
        stage = .code
        codeDigits = ""
    }

    public func verifyCode() {
        guard canVerify else { return }
        // "same six digits, no birthday, no quiz" — login ends here, and
        // says so rather than re-entering the stage it is already on.
        if mode == .login {
            isAuthenticated = true
        } else {
            stage = .birthday
        }
    }

    /// The kit's back map, verbatim. Returns false when back leaves the
    /// account flow entirely — the caller owns what came before.
    public func back() -> Bool {
        switch stage {
        case .method:
            return false
        case .phone:
            if mode == .login {
                return false
            }
            stage = .method
        case .code:
            stage = .phone
        case .birthday:
            stage = method == .phone ? .code : .method
        }
        return true
    }

    // MARK: - input rules

    public func enterCode(_ raw: String) {
        codeDigits = String(raw.filter(\.isNumber).prefix(6))
    }

    public var phoneDigits: String {
        phoneNumber.filter(\.isNumber)
    }

    public var canSendCode: Bool {
        phoneDigits.count >= 7
    }

    public var canVerify: Bool {
        codeDigits.count == 6
    }

    // MARK: - the birthday gate

    /// Whole years old on `today`, or nil without a birthday.
    public var age: Int? {
        guard let birthday else { return nil }
        return Calendar(identifier: .gregorian)
            .dateComponents([.year], from: birthday, to: today).year
    }

    public var birthdayChosen: Bool {
        birthday != nil
    }

    /// The wheel's bounds, the kit's own: 1930 through 2012.
    public nonisolated static let birthdayRange: ClosedRange<Date> = {
        let calendar = Calendar(identifier: .gregorian)
        let lower = calendar.date(from: DateComponents(year: 1930, month: 1, day: 1)) ?? .distantPast
        let upper = calendar.date(from: DateComponents(year: 2012, month: 12, day: 31)) ?? .distantPast
        return lower ... upper
    }()

    /// "9 march 1999 · 27" — the mono echo under the wheel.
    public func birthdayEcho() -> String? {
        guard let birthday, let age else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "d MMMM yyyy"
        return "\(formatter.string(from: birthday).lowercased()) \u{00B7} \(age)"
    }

    /// "1999-03" — what `profiles` stores. The day is collected for the
    /// gate's math and deliberately not persisted (birth_year_month is the
    /// column, month precision is the design).
    public func birthYearMonth() -> String? {
        guard let birthday else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: birthday)
    }

    // MARK: - create

    /// The batch write: the quiz's prior plus the birthday, one call. The
    /// under-13 rejection happens HERE, typed, before any seam is touched —
    /// a hard block, not a validation hint (PRD §17).
    public func createAccount(quiz: OnboardingModel, onCreated: @escaping () -> Void) {
        guard let wire = birthYearMonth() else { return }
        if let age, age < 13 {
            ageError = GlossedError(
                .underAgeMinimum,
                userMessage: "glossed is for ages 13 and up — see you in a few years.",
                debugDetail: "onboarding birthday gate: age \(age)"
            )
            return
        }
        ageError = nil
        let draft = quiz.draft(birthYearMonth: wire)
        guard let store else {
            onCreated()
            return
        }
        isCreating = true
        createTask = Task {
            defer { isCreating = false }
            do {
                try await store.finish(draft)
                onCreated()
            } catch {
                ageError = nil
                creationError = GlossedError.from(error)
            }
        }
    }

    /// A failed finish — network, RLS, constraint — rendered in words.
    public private(set) var creationError: GlossedError?
}

/// The seams the app fills: nothing here knows transports. `finish` is the
/// batch profile write (dev session today; the real auth handoff is
/// GLO-23's, and it slots in without changing this shape).
public struct AccountStore: Sendable {
    public var sendCode: @Sendable (_ phone: String) async throws -> Void
    public var verifyCode: @Sendable (_ phone: String, _ code: String) async throws -> Void
    public var finish: @Sendable (_ draft: ProfileDraft) async throws -> Void

    public init(
        sendCode: @escaping @Sendable (String) async throws -> Void = { _ in },
        verifyCode: @escaping @Sendable (String, String) async throws -> Void = { _, _ in },
        finish: @escaping @Sendable (ProfileDraft) async throws -> Void
    ) {
        self.sendCode = sendCode
        self.verifyCode = verifyCode
        self.finish = finish
    }

    /// The live write: the quiz's prior lands through the repository the
    /// DataKit opening added.
    public static func repository(_ profiles: ProfileRepository) -> AccountStore {
        AccountStore(finish: { try await profiles.saveProfile($0) })
    }
}
