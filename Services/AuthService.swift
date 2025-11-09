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
    
    private init() {}
    
    // MARK: - Token Management
    
    var authToken: String? {
        get {
            return getTokenFromKeychain()
        }
        set {
            if let token = newValue {
                saveTokenToKeychain(token)
            } else {
                deleteTokenFromKeychain()
            }
        }
    }
    
    var isAuthenticated: Bool {
        guard let token = authToken else { return false }
        // Check if token is expired
        if let expiry = UserDefaults.standard.object(forKey: tokenExpiryKey) as? Date {
            return expiry > Date()
        }
        return true
    }
    
    // MARK: - Keychain Operations
    
    private func saveTokenToKeychain(_ token: String) {
        let data = token.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tokenKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // Delete existing item first
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            print("Failed to save token to keychain: \(status)")
            return
        }
    }
    
    private func getTokenFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tokenKey,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        
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
        // TODO: Replace with actual authentication endpoint
        // POST /v1/auth/login
        // Returns: { "token": "...", "expires_at": "..." }
        
        guard let url = URL(string: "https://api.example.com/v1/auth/login") else {
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
        // TODO: Implement token refresh logic
        // POST /v1/auth/refresh
        throw AuthError.notImplemented
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

