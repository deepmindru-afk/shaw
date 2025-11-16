//
//  AppCoordinator.swift
//  AI Voice Copilot
//

import SwiftUI

enum AppScreen {
    case home
    case sessions
    case sessionDetail(String)
    case settings
}

class AppCoordinator: ObservableObject {
    static let shared = AppCoordinator()
    
    @Published var currentScreen: AppScreen = .home
    @Published var navigationPath = NavigationPath()
    @Published var selectedTab: Int = 0
    
    private init() {}
    
    func navigate(to screen: AppScreen) {
        DispatchQueue.main.async {
            switch screen {
            case .home:
                self.selectedTab = 0
                self.navigationPath = NavigationPath()
            case .sessions:
                self.selectedTab = 1
            case .sessionDetail(let sessionID):
                self.selectedTab = 1
                self.navigationPath = NavigationPath()
                self.navigationPath.append(sessionID)
            case .settings:
                self.selectedTab = 2
            }
            
            self.currentScreen = screen
        }
    }
    
    func navigateBack() {
        if !navigationPath.isEmpty {
            navigationPath.removeLast()
        } else {
            selectedTab = 0
            currentScreen = .home
        }
    }
}
