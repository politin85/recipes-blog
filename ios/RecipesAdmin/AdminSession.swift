import LocalAuthentication
import Security
import SwiftUI

/// The admin password, kept in the Keychain (this device only, readable only while unlocked).
enum PasswordStore {
    private static let service = "com.nirpoliti.recipes.admin"
    private static let account = "admin-password"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    static func load() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ password: String) {
        delete()
        var q = query
        q[kSecValueData as String] = Data(password.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}

@MainActor
@Observable
final class AdminSession {
    private(set) var password: String?
    /// True while a stored login waits for Face ID / passcode.
    private(set) var locked: Bool
    var toast: Toast?

    struct Toast: Equatable {
        enum Kind { case success, error, info }
        var message: String
        var kind: Kind
        var id = UUID()
    }

    init() {
        let stored = PasswordStore.load()
        password = stored
        locked = stored != nil
        #if DEBUG
        // UI tests cannot answer the device passcode prompt.
        if ProcessInfo.processInfo.arguments.contains("-skipLock") { locked = false }
        #endif
    }

    var api: AdminAPI? { password.map(AdminAPI.init(password:)) }
    var isLoggedIn: Bool { password != nil }

    func login(_ password: String) async throws {
        try await AdminAPI(password: password).verify()
        PasswordStore.save(password)
        self.password = password
        locked = false
    }

    func logout() {
        PasswordStore.delete()
        password = nil
        locked = false
    }

    /// Locks again when the app leaves the foreground.
    func lock() {
        if password != nil { locked = true }
    }

    /// Asks for Face ID / Touch ID / the device passcode.
    func unlock() async {
        guard locked else { return }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No passcode on this device, so there is nothing to authenticate with.
            locked = false
            return
        }
        if (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "כניסה לניהול המתכונים")) == true {
            locked = false
        }
    }

    func show(_ message: String, _ kind: Toast.Kind = .success) {
        toast = Toast(message: message, kind: kind)
    }

    @discardableResult
    func run<T>(_ work: (AdminAPI) async throws -> T) async -> T? {
        await run("שגיאה", work)
    }

    /// Runs an admin request, reporting failures as a toast. A rejected password signs out.
    @discardableResult
    func run<T>(_ failureMessage: String = "שגיאה", _ work: (AdminAPI) async throws -> T) async -> T? {
        guard let api else { return nil }
        do {
            return try await work(api)
        } catch AdminAPI.AdminError.unauthorized {
            logout()
            show("הסיסמה כבר לא תקפה — יש להתחבר מחדש", .error)
        } catch let AdminAPI.AdminError.server(message) {
            show(message, .error)
        } catch {
            show(failureMessage, .error)
        }
        return nil
    }
}
