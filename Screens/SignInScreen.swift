//
//  SignInScreen.swift
//  Roadtrip
//

import SwiftUI
import AuthenticationServices

struct SignInScreen: View {
    @ObservedObject private var settings = UserSettings.shared
    @State private var errorMessage: String?
    @State private var isProcessing = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "person.icloud")
                    .font(.system(size: 64))
                    .foregroundColor(.blue)

                Text("Sign in to Continue")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text("Use Sign in with Apple to link your sessions, enable iCloud sync, and restore purchases across devices.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            VStack(spacing: 16) {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    handleAuthorization(result: result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .disabled(isProcessing)

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                if isProcessing {
                    ProgressView("Signing in…")
                        .progressViewStyle(.circular)
                }
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding()
    }

    private func handleAuthorization(result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = "Invalid Apple credential."
                return
            }

            isProcessing = true
            errorMessage = nil

            Task {
                do {
                    try AuthService.shared.handleAppleSignIn(credential: credential)
                    await MainActor.run {
                        settings.isSignedIn = true
                        isProcessing = false
                    }
                } catch {
                    await MainActor.run {
                        errorMessage = "Failed to sign in. Please try again."
                        isProcessing = false
                    }
                }
            }

        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    SignInScreen()
}
