//
//  ContentView.swift
//  AI Voice Copilot
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var settings: UserSettings = .shared
    @ObservedObject var appCoordinator: AppCoordinator = .shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var authAlertMessage: String?
    
    var body: some View {
        Group {
            if !settings.isSignedIn {
                SignInScreen()
            } else {
                MainAppView()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .authServiceDidSignOut)) { notification in
            settings.isSignedIn = false
            if let reason = notification.userInfo?["reason"] as? String {
                authAlertMessage = reason
            } else {
                authAlertMessage = nil
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                AuthService.shared.validateCredentialState()
            }
        }
        .alert("Sign In Required", isPresented: Binding(
            get: { authAlertMessage != nil },
            set: { newValue in
                if !newValue {
                    authAlertMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(authAlertMessage ?? "Please sign in again.")
        }
    }
}

struct MainAppView: View {
    @ObservedObject var appCoordinator: AppCoordinator = .shared
    @ObservedObject private var callCoordinator = AssistantCallCoordinator.shared
    
    var body: some View {
        ZStack {
            TabView(selection: $appCoordinator.selectedTab) {
                NavigationStack {
                    CallScreen()
                }
                .tabItem {
                    Label("Call", systemImage: "phone.fill")
                }
                .tag(0)
                
                NavigationStack(path: $appCoordinator.navigationPath) {
                    SessionsListScreen()
                }
                .tabItem {
                    Label("Sessions", systemImage: "clock.fill")
                }
                .tag(1)
                
                NavigationStack {
                    SettingsScreen()
                }
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(2)
            }
            if callCoordinator.showConnectingOverlay {
                ConnectingOverlayView(isDisconnecting: callCoordinator.overlayIsDisconnecting)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: callCoordinator.callState)
        .animation(.easeInOut(duration: 0.2), value: callCoordinator.showConnectingOverlay)
    }
}

#Preview {
    ContentView()
}
