//
//  AuthService.swift
//  AI Voice Copilot
//

import Foundation
import Security

class AuthService {
    static let shared = AuthService()

    private let tokenKey = "com.aivoicecopilot.authToken"
    private let tokenExpiryKey = "com.aivoicecopilot.tokenExpiry"
    private let configuration = Configuration.shared

    private init() {}
    
    // MARK: - Token Management
    
    var authToken: String? {
        get {
            // First check if we have a device token in UserDefaults (persistent across app launches)
            let deviceTokenKey = "com.aivoicecopilot.deviceToken"
            if let deviceToken = UserDefaults.standard.string(forKey: deviceTokenKey) {
                print("🔑 authToken getter: Found device token in UserDefaults: \(deviceToken.prefix(20))...")
                // Ensure it's also in keychain for consistency
                let keychainToken = getTokenFromKeychain()
                if keychainToken == nil {
                    print("🔑 Device token exists but not in keychain, saving to keychain...")
                    saveTokenToKeychain(deviceToken)
                }
                return deviceToken
            }

            // Fall back to checking keychain
            let token = getTokenFromKeychain()
            print("🔑 AuthService.authToken getter called, token exists: \(token != nil), length: \(token?.count ?? 0)")
            return token
        }
        set {
            if let token = newValue {
                print("🔑 AuthService.authToken setter called with token: \(token.prefix(20))...")
                let deviceTokenKey = "com.aivoicecopilot.deviceToken"
                UserDefaults.standard.set(token, forKey: deviceTokenKey)
                saveTokenToKeychain(token)
            } else {
                print("🔑 AuthService.authToken setter called with nil, deleting token")
                let deviceTokenKey = "com.aivoicecopilot.deviceToken"
                UserDefaults.standard.removeObject(forKey: deviceTokenKey)
                deleteTokenFromKeychain()
            }
        }
    }

    var isAuthenticated: Bool {
        print("🔑 isAuthenticated called")
        // Auto-authenticate with device token if no auth token exists
        if authToken == nil {
            print("🔑 No token found, generating device token...")
            generateDeviceToken()
        }
        guard authToken != nil else {
            print("❌ Still no token after generateDeviceToken()")
            return false
        }
        // Check if token is expired
        if let expiry = UserDefaults.standard.object(forKey: tokenExpiryKey) as? Date {
            let isValid = expiry > Date()
            print("🔑 Token expiry check: \(isValid), expires: \(expiry)")
            return isValid
        }
        print("🔑 No expiry date found, assuming valid")
        return true
    }

    private func generateDeviceToken() {
        print("🔑 generateDeviceToken() called")
        // Generate a persistent device-based token
        let deviceTokenKey = "com.aivoicecopilot.deviceToken"

        if let existingToken = UserDefaults.standard.string(forKey: deviceTokenKey) {
            print("🔑 Found existing device token: \(existingToken.prefix(20))...")
            // Use existing device token
            authToken = existingToken
        } else {
            // Create new device token (UUID-based)
            let deviceId = UUID().uuidString
            let deviceToken = "device_\(deviceId)"
            print("🔑 Generated new device token: \(deviceToken.prefix(20))...")
            UserDefaults.standard.set(deviceToken, forKey: deviceTokenKey)
            authToken = deviceToken
        }

        // Set expiry far in the future (10 years)
        let expiryDate = Date().addingTimeInterval(315360000)
        print("🔑 Setting token expiry to: \(expiryDate)")
        UserDefaults.standard.set(expiryDate, forKey: tokenExpiryKey)
    }
    
    // MARK: - Keychain Operations
    
    private func saveTokenToKeychain(_ token: String) {
        print("🔑 saveTokenToKeychain() called with token: \(token.prefix(20))...")
        let data = token.data(using: .utf8)!

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tokenKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        // Delete existing item first
        let deleteStatus = SecItemDelete(query as CFDictionary)
        print("🔑 Keychain delete status: \(deleteStatus)")

        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        print("🔑 Keychain add status: \(status)")
        guard status == errSecSuccess else {
            print("❌ Failed to save token to keychain: \(status)")
            return
        }
        print("✅ Token saved to keychain successfully")
    }
    
    private func getTokenFromKeychain() -> String? {
        print("🔑 getTokenFromKeychain() called")
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tokenKey,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        print("🔑 Keychain query status: \(status)")

        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            print("❌ Failed to retrieve token from keychain, status: \(status)")
            return nil
        }

        print("✅ Token retrieved from keychain: \(token.prefix(20))...")
        return token
    }
    
    private func deleteTokenFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tokenKey
        ]
        
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: tokenExpiryKey)
    }
    
    // MARK: - Authentication Methods
    
    /// Set a token directly (for development/testing)
    func setToken(_ token: String, expiresAt: Date? = nil) {
        authToken = token
        if let expiry = expiresAt {
            UserDefaults.standard.set(expiry, forKey: tokenExpiryKey)
        } else {
            // Default to 1 hour if not specified
            UserDefaults.standard.set(Date().addingTimeInterval(3600), forKey: tokenExpiryKey)
        }
    }
    
    func login(email: String, password: String) async throws -> String {
        guard let url = URL(string: configuration.authLoginURL) else {
            throw AuthError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "email": email,
            "password": password
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw AuthError.authenticationFailed
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let authResponse = try decoder.decode(AuthResponse.self, from: data)
        
        authToken = authResponse.token
        if let expiry = authResponse.expiresAt {
            UserDefaults.standard.set(expiry, forKey: tokenExpiryKey)
        }
        
        return authResponse.token
    }
    
    func logout() {
        authToken = nil
    }
    
    func refreshToken() async throws {
        guard let url = URL(string: configuration.authRefreshURL) else {
            throw AuthError.invalidURL
        }

        guard let currentToken = authToken else {
            throw AuthError.tokenExpired
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(currentToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw AuthError.authenticationFailed
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let authResponse = try decoder.decode(AuthResponse.self, from: data)

        authToken = authResponse.token
        if let expiry = authResponse.expiresAt {
            UserDefaults.standard.set(expiry, forKey: tokenExpiryKey)
        }
    }
}

enum AuthError: LocalizedError {
    case invalidURL
    case authenticationFailed
    case tokenExpired
    case notImplemented
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid authentication URL"
        case .authenticationFailed:
            return "Authentication failed. Please check your credentials."
        case .tokenExpired:
            return "Your session has expired. Please log in again."
        case .notImplemented:
            return "Token refresh not yet implemented"
        }
    }
}

struct AuthResponse: Codable {
    let token: String
    let expiresAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case token
        case expiresAt = "expires_at"
    }
}

