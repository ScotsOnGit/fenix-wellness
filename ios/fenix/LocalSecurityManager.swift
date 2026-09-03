//
//  LocalSecurityManager.swift
//  fenix
//
//  Created by Codex on 6/6/2026.
//

import CryptoKit
import Foundation
import LocalAuthentication
import Security

struct LocalSecuritySettings: Codable, Equatable, Sendable {
    var faceIDEnabled: Bool
    var pinEnabled: Bool
    var pinSalt: String?
    var pinHash: String?

    var isEnabled: Bool {
        faceIDEnabled || pinEnabled
    }
}

enum LocalSecurityError: LocalizedError, Equatable {
    case biometricsUnavailable
    case pinNotConfigured
    case invalidPIN
    case keychainFailed

    var errorDescription: String? {
        switch self {
        case .biometricsUnavailable:
            "Face ID is not available on this device."
        case .pinNotConfigured:
            "Set a PIN before enabling PIN unlock."
        case .invalidPIN:
            "That PIN is incorrect."
        case .keychainFailed:
            "Could not update secure storage."
        }
    }
}

@MainActor
final class LocalSecurityManager {
    static let shared = LocalSecurityManager()

    private let service = "com.fullarton.fenix.local-security"

    var biometryLabel: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        default:
            return "Face ID"
        }
    }

    func settings(for userID: UUID) -> LocalSecuritySettings {
        guard
            let data = read(account: settingsAccount(for: userID)),
            let settings = try? JSONDecoder().decode(LocalSecuritySettings.self, from: data)
        else {
            return LocalSecuritySettings(faceIDEnabled: false, pinEnabled: false)
        }
        return settings
    }

    func setFaceIDEnabled(_ isEnabled: Bool, for userID: UUID) throws -> LocalSecuritySettings {
        if isEnabled, !canUseBiometrics() {
            throw LocalSecurityError.biometricsUnavailable
        }
        var settings = settings(for: userID)
        settings.faceIDEnabled = isEnabled
        try save(settings, for: userID)
        return settings
    }

    func setPIN(_ pin: String, for userID: UUID) throws -> LocalSecuritySettings {
        // The PIN itself is never stored. A per-user salt means the same PIN produces
        // different hashes for different signed-in accounts on the same device.
        let salt = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        var settings = settings(for: userID)
        settings.pinEnabled = true
        settings.pinSalt = salt
        settings.pinHash = hash(pin: pin, salt: salt)
        try save(settings, for: userID)
        return settings
    }

    func setPINEnabled(_ isEnabled: Bool, for userID: UUID) throws -> LocalSecuritySettings {
        var settings = settings(for: userID)
        if isEnabled, settings.pinHash == nil {
            throw LocalSecurityError.pinNotConfigured
        }
        settings.pinEnabled = isEnabled
        try save(settings, for: userID)
        return settings
    }

    func verifyPIN(_ pin: String, for userID: UUID) throws -> Bool {
        let settings = settings(for: userID)
        guard let salt = settings.pinSalt, let expectedHash = settings.pinHash else {
            throw LocalSecurityError.pinNotConfigured
        }
        return hash(pin: pin, salt: salt) == expectedHash
    }

    func disableAll(for userID: UUID) throws {
        try delete(account: settingsAccount(for: userID))
    }

    func authenticateWithBiometrics(reason: String) async throws {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            throw LocalSecurityError.biometricsUnavailable
        }

        let success = try await context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: reason
        )
        if !success {
            throw LocalSecurityError.biometricsUnavailable
        }
    }

    private func canUseBiometrics() -> Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    private func save(_ settings: LocalSecuritySettings, for userID: UUID) throws {
        let data = try JSONEncoder().encode(settings)
        try write(data, account: settingsAccount(for: userID))
    }

    private func settingsAccount(for userID: UUID) -> String {
        "local-security-\(userID.uuidString)"
    }

    private func hash(pin: String, salt: String) -> String {
        let data = Data("\(salt):\(pin)".utf8)
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func read(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    private func write(_ data: Data, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            // Local app-lock settings should remain on this device only.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery.merge(attributes) { _, new in new }
            guard SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess else {
                throw LocalSecurityError.keychainFailed
            }
        } else if status != errSecSuccess {
            throw LocalSecurityError.keychainFailed
        }
    }

    private func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw LocalSecurityError.keychainFailed
        }
    }
}
