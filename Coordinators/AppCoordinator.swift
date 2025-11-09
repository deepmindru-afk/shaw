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
    
    private init() {}
    
    func navigate(to screen: AppScreen) {
        currentScreen = screen
    }
    
    func navigateBack() {
        if !navigationPath.isEmpty {
            navigationPath.removeLast()
        } else {
            currentScreen = .home
        }
    }
}

