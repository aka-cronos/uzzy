import CommonCrypto
import Foundation
import Security

/// What reading the password of Cursor's safeStorage from the Keychain gave.
public enum SafeStoragePassword: Sendable, Equatable {
    case found(Data)
    /// The user denied the Keychain prompt.
    case denied
    case notFound
    /// The Keychain could not be read, e.g. because it is locked.
    case unavailable
}

/// Reads the password Cursor encrypts its session with. Only ever asked
/// after the user consents, and only on a user action.
public protocol SafeStorageKeychain: Sendable {
    func password() -> SafeStoragePassword
}

/// The Keychain item Electron's safeStorage keeps for Cursor: service
/// `Cursor Safe Storage`, account `Cursor`. Read by Uzzy itself, so an
/// "Always Allow" trusts Uzzy alone, never a tool any process can run, such
/// as `/usr/bin/security`. It only reads: it never adds, updates, deletes
/// the item or changes its access control.
public struct CursorSafeStorageKeychain: SafeStorageKeychain {
    public init() {}

    public func password() -> SafeStoragePassword {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "Cursor Safe Storage",
            kSecAttrAccount: "Cursor",
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        switch SecItemCopyMatching(query as CFDictionary, &result) {
        case errSecSuccess:
            guard let password = result as? Data, !password.isEmpty else { return .unavailable }
            return .found(password)
        case errSecItemNotFound:
            return .notFound
        case errSecUserCanceled, errSecAuthFailed:
            return .denied
        default:
            return .unavailable
        }
    }
}

/// The format Cursor stores its encrypted access token in since 3.27:
/// `cursor-safe-storage:v1:` and the base64 of Electron's safeStorage
/// ciphertext. On macOS that is `v10` and AES-128-CBC with an IV of 16
/// spaces, keyed by PBKDF2-HMAC-SHA1 over the Keychain password, with salt
/// `saltysalt` and 1003 rounds.
enum CursorSafeStorage {
    /// Any value with this prefix is encrypted, whatever its version.
    static let prefix = "cursor-safe-storage:"
    private static let versionOne = "cursor-safe-storage:v1:"
    private static let cipherVersion = Data("v10".utf8)
    /// Far above any real token (about 600 bytes), so a hostile value cannot
    /// make the app decode much.
    private static let longestValue = 16 * 1024
    private static let salt = Data("saltysalt".utf8)
    private static let rounds: UInt32 = 1003
    private static let keyLength = kCCKeySizeAES128
    private static let iv = [UInt8](repeating: 0x20, count: kCCBlockSizeAES128)

    /// The ciphertext of a stored value, or `nil` when the value is not one
    /// Uzzy can decrypt: another version, broken base64, or a shape AES-CBC
    /// cannot have. Never falls back to reading it as plaintext.
    static func ciphertext(of value: String) -> Data? {
        guard value.utf8.count <= longestValue, value.hasPrefix(versionOne),
              let sealed = Data(base64Encoded: String(value.dropFirst(versionOne.count))),
              sealed.starts(with: cipherVersion)
        else { return nil }
        let ciphertext = sealed.dropFirst(cipherVersion.count)
        guard !ciphertext.isEmpty, ciphertext.count % kCCBlockSizeAES128 == 0 else { return nil }
        return Data(ciphertext)
    }

    /// The access token, or `nil` when decryption fails or does not give a
    /// JWT. CBC is not authenticated: a wrong key can still unpad, so the
    /// result is checked before it is ever sent anywhere. The derived key
    /// and the plaintext buffer are wiped before returning.
    static func token(decrypting ciphertext: Data, password: Data) -> String? {
        var key = [UInt8](repeating: 0, count: keyLength)
        defer { wipe(&key) }
        let derived = password.withUnsafeBytes { password in
            salt.withUnsafeBytes { salt in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    password.baseAddress?.assumingMemoryBound(to: CChar.self), password.count,
                    salt.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), rounds,
                    &key, key.count
                )
            }
        }
        guard derived == kCCSuccess else { return nil }

        var plaintext = [UInt8](repeating: 0, count: ciphertext.count)
        defer { wipe(&plaintext) }
        var length = 0
        let status = ciphertext.withUnsafeBytes { ciphertext in
            CCCrypt(
                CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                key, key.count, iv,
                ciphertext.baseAddress, ciphertext.count,
                &plaintext, plaintext.count, &length
            )
        }
        guard status == kCCSuccess,
              let token = String(bytes: plaintext.prefix(length), encoding: .utf8),
              isJWT(token)
        else { return nil }
        return token
    }

    /// Three non-empty base64url parts, as Cursor's access tokens have.
    private static func isJWT(_ token: String) -> Bool {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        let alphabet = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        return parts.count == 3 && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(alphabet.contains) }
    }

    /// Zeroes bytes the app owns, in a way the compiler cannot skip. Copies
    /// that Swift, Foundation or Security made are out of its reach.
    static func wipe(_ bytes: inout [UInt8]) {
        let count = bytes.count
        bytes.withUnsafeMutableBytes { _ = memset_s($0.baseAddress, count, 0, count) }
    }

    static func wipe(_ data: inout Data) {
        let count = data.count
        data.withUnsafeMutableBytes { _ = memset_s($0.baseAddress, count, 0, count) }
    }
}
