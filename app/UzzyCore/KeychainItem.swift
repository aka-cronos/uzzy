import Foundation

/// A generic password in the login Keychain, read through `/usr/bin/security`
/// as the official app that writes it does. Never written.
enum KeychainItem {
    case found(Data)
    case notFound
    case denied
    case failed

    /// `security` exits with the low byte of the Keychain error it got.
    private enum ExitStatus {
        static let itemNotFound: Int32 = 44 // errSecItemNotFound
        static let authFailed: Int32 = 51 // errSecAuthFailed
        static let userCanceled: Int32 = 128 // errSecUserCanceled
    }

    /// The item of `service`, and of `account` when given. Blocks while the
    /// system access prompt is shown, so it must run off the main actor.
    static func read(service: String, account: String? = nil, with securityTool: URL) -> KeychainItem {
        let tool = Process()
        tool.executableURL = securityTool
        tool.arguments = ["find-generic-password", "-s", service] + (account.map { ["-a", $0] } ?? []) + ["-w"]
        let output = Pipe()
        tool.standardOutput = output
        tool.standardError = FileHandle.nullDevice
        do {
            try tool.run()
        } catch {
            return .failed
        }
        // Reads before waiting, so a full pipe never blocks the tool.
        let data = (try? output.fileHandleForReading.readToEnd()) ?? Data()
        tool.waitUntilExit()
        guard tool.terminationReason == .exit else { return .failed }
        switch tool.terminationStatus {
        case 0: return .found(data)
        case ExitStatus.itemNotFound: return .notFound
        // The user denied the prompt. If the prompt could not be shown, the
        // Keychain is unavailable rather than denied or malformed.
        case ExitStatus.userCanceled, ExitStatus.authFailed: return .denied
        default: return .failed
        }
    }
}
