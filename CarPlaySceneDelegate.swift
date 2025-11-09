//
//  CarPlaySceneDelegate.swift
//  AI Voice Copilot
//

import Foundation
import CarPlay

class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        setupCarPlayUI()
    }
    
    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
    }

    private func setupCarPlayUI() {
        let talkToAssistantItem = CPListItem(
            text: "Talk to Assistant",
            detailText: nil,
            image: nil
        )
        
        talkToAssistantItem.handler = { [weak self] _, completion in
            // Start assistant call from CarPlay context
            AssistantCallCoordinator.shared.startAssistantCall(context: "carplay")
            completion()
        }
        
        let section = CPListSection(items: [talkToAssistantItem])
        let listTemplate = CPListTemplate(title: "AI Voice Copilot", sections: [section])
        
        interfaceController?.setRootTemplate(listTemplate, animated: true) { success, error in
            if let error = error {
                print("Error setting CarPlay root template: \(error)")
            }
        }
    }
}
