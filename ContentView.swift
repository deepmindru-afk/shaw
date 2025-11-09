//
//  ContentView.swift
//  AI Voice Copilot
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var settings = UserSettings.shared
    @ObservedObject var appCoordinator = AppCoordinator.shared
    
    var body: some View {
        Group {
            if !settings.hasSeenOnboarding {
                OnboardingScreen()
            } else {
                MainAppView()
            }
        }
    }
}

struct MainAppView: View {
    @ObservedObject var appCoordinator = AppCoordinator.shared
    
    var body: some View {
        switch appCoordinator.currentScreen {
        case .home:
            HomeScreen()
        case .sessions:
            SessionsListScreen()
        case .sessionDetail(let id):
            SessionDetailScreen(sessionID: id)
        case .settings:
            SettingsScreen()
        }
    }
}

#Preview {
    ContentView()
}
