//
//  EmergencyActionIntent.swift
//  discreetly
//
//  App Intent for Action Button emergency activation
//

import AppIntents
import Foundation

struct EmergencyActionIntent: AppIntent {
    static var title: LocalizedStringResource = "Action"
    static var description: IntentDescription? = IntentDescription("Trigger Action for Discreetly")
    
    // This makes it available to Action Button
    static var isDiscoverable: Bool = true
    
    // Specify that this intent should open the app
    static var openAppWhenRun: Bool = true
    
    func perform() async throws -> some IntentResult {
        print("🚨 Action Intent triggered!")
        
        // Post a notification that the main app can listen for
        await NotificationCenter.default.post(name: .emergencyActionTriggered, object: nil)
        
        return .result()
    }
}

// MARK: - App Shortcuts
struct DiscreetlyAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: EmergencyActionIntent(),
            phrases: [
                "Emergency with \(.applicationName)",
                "Activate emergency in \(.applicationName)",
                "Trigger \(.applicationName) emergency"
            ],
            systemImageName: "exclamationmark.triangle.fill"
        )
    }
}

// MARK: - Notification Extension
extension Notification.Name {
    static let emergencyActionTriggered = Notification.Name("EmergencyActionTriggered")
}
