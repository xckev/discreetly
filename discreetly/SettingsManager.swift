//
//  SettingsManager.swift
//  discreetly
//
//  Manager for persisting user settings and configurations
//

import Foundation
import Combine

final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @Published var settings: UserSettings {
        didSet {
            save()
        }
    }

    private let settingsKey = "discreetly_user_settings"

    init() {
        // Load settings from UserDefaults
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(UserSettings.self, from: data) {
            self.settings = decoded
        } else {
            // Initialize with default test action for simulator
            self.settings = UserSettings()
            self.settings.contacts = getDefaultContacts()
            let actions = getDefaultActions()
            // Assign default contacts to actions
            for var action in actions {
                action.contacts = self.settings.contacts.map { $0.id }
                self.settings.actions.append(action)
            }
        }

        // Auto-configure Twilio credentials from Info.plist (like Ultravox does)
        autoConfigureTwilioCredentials()
    }

    /// Save settings to UserDefaults
    func save() {
        if let encoded = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(encoded, forKey: settingsKey)
        }
    }

    /// Auto-configure Twilio credentials from Info.plist
    private func autoConfigureTwilioCredentials() {
        print("🔧 Auto-configuring Twilio credentials from Info.plist...")

        // Load Twilio Account SID
        if let accountSid = Bundle.main.object(forInfoDictionaryKey: "TWILIO_ACCOUNT_SID") as? String {
            settings.twilioAccountSid = accountSid
            print("✅ Twilio Account SID loaded: \(String(accountSid.prefix(10)))...")
        } else {
            print("⚠️  Twilio Account SID not found in Info.plist")
        }

        // Load Twilio Auth Token
        if let authToken = Bundle.main.object(forInfoDictionaryKey: "TWILIO_AUTH_TOKEN") as? String {
            settings.twilioAuthToken = authToken
            print("✅ Twilio Auth Token loaded: \(String(authToken.prefix(10)))...")
        } else {
            print("⚠️  Twilio Auth Token not found in Info.plist")
        }

        // Load Twilio From Number
        if let fromNumber = Bundle.main.object(forInfoDictionaryKey: "TWILIO_FROM_NUMBER") as? String {
            settings.twilioFromNumber = fromNumber
            print("✅ Twilio From Number loaded: \(fromNumber)")
        } else {
            print("⚠️  Twilio From Number not found in Info.plist")
        }

        // Save the updated settings
        save()
        print("✅ Twilio credentials auto-configuration complete")
    }

    /// Add a contact
    func addContact(_ contact: EmergencyContact) {
        settings.contacts.append(contact)

        // Auto-assign primary contact to all actions that don't have contacts yet
        if contact.isPrimary || settings.contacts.count == 1 {
            updateActionsWithNewContact(contact)
        }
    }

    /// Update actions to include the new contact
    private func updateActionsWithNewContact(_ contact: EmergencyContact) {
        for i in 0..<settings.actions.count {
            // If action doesn't have any contacts, add this one
            if settings.actions[i].contacts.isEmpty {
                settings.actions[i].contacts.append(contact.id)
                print("📝 Auto-assigned contact '\(contact.name)' to action '\(settings.actions[i].name)'")
            }
        }
    }

    /// Remove a contact
    func removeContact(id: UUID) {
        settings.contacts.removeAll { $0.id == id }
    }

    /// Update a contact
    func updateContact(_ contact: EmergencyContact) {
        if let index = settings.contacts.firstIndex(where: { $0.id == contact.id }) {
            settings.contacts[index] = contact
        }
    }

    /// Add an action
    func addAction(_ action: ActionConfig) {
        // If this action is enabled, disable all other actions (only one can be active at a time)
        if action.isEnabled {
            for i in 0..<settings.actions.count {
                settings.actions[i].isEnabled = false
            }
        }

        settings.actions.append(action)
        notifyActionMapperOfChanges()
    }

    /// Remove an action
    func removeAction(id: UUID) {
        settings.actions.removeAll { $0.id == id }
        notifyActionMapperOfChanges()
    }

    /// Update an action
    func updateAction(_ action: ActionConfig) {
        if let index = settings.actions.firstIndex(where: { $0.id == action.id }) {
            let wasEnabled = settings.actions[index].isEnabled
            let willBeEnabled = action.isEnabled
            
            // If the action is being enabled and it wasn't before, disable all other actions
            if willBeEnabled && !wasEnabled {
                for i in 0..<settings.actions.count {
                    if settings.actions[i].id != action.id {
                        settings.actions[i].isEnabled = false
                    }
                }
            }
            
            // Create a new array to ensure @Published triggers
            var updatedActions = settings.actions
            updatedActions[index] = action
            settings.actions = updatedActions
            print("✅ Action updated: \(action.name)")
            notifyActionMapperOfChanges()
        } else {
            print("⚠️ Action not found for update: \(action.id)")
        }
    }

    /// Get primary contact
    func getPrimaryContact() -> EmergencyContact? {
        settings.contacts.first { $0.isPrimary }
    }

    /// Get enabled actions
    func getEnabledActions() -> [ActionConfig] {
        settings.actions.filter { $0.isEnabled }
    }

    /// Enable a distress call action and disable all other distress call actions
    func enableDistressCallAction(_ actionId: UUID, enabled: Bool) {
        if enabled {
            // First, disable all other distress call actions
            for i in 0..<settings.actions.count {
                if settings.actions[i].actionType == .distressCall && settings.actions[i].id != actionId {
                    settings.actions[i].isEnabled = false
                }
            }
        }

        // Then update the target action
        updateAction(actionId) { updatedAction in
            updatedAction.isEnabled = enabled
        }
        notifyActionMapperOfChanges()
    }
    
    /// Enable an action and disable all other actions (only one can be active at a time)
    func enableSingleAction(_ actionId: UUID, enabled: Bool) {
        if enabled {
            // First, disable all other actions
            for i in 0..<settings.actions.count {
                if settings.actions[i].id != actionId {
                    settings.actions[i].isEnabled = false
                }
            }
        }

        // Then update the target action
        updateAction(actionId) { updatedAction in
            updatedAction.isEnabled = enabled
        }
        notifyActionMapperOfChanges()
    }
    
    /// Disable all actions (used when system is deactivated)
    func disableAllActions() {
        for i in 0..<settings.actions.count {
            settings.actions[i].isEnabled = false
        }
        print("🚫 All actions disabled due to system deactivation")
        notifyActionMapperOfChanges()
    }

    /// Reset to defaults
    func resetToDefaults() {
        settings = UserSettings()
    }

    // MARK: - AI Agent Management

    /// Update AI agent configuration
    func updateAIAgentConfig(_ config: AIAgentConfig) {
        settings.aiAgentConfig = config
    }

    /// Add call record to history
    func addCallRecord(_ callRecord: CallRecord) {
        settings.callHistory.append(callRecord)

        // Keep only last 100 calls to prevent storage bloat
        if settings.callHistory.count > 100 {
            settings.callHistory.removeFirst(settings.callHistory.count - 100)
        }
    }

    /// Get recent call history
    func getRecentCallHistory(limit: Int = 10) -> [CallRecord] {
        return Array(settings.callHistory.suffix(limit))
    }

    /// Clear call history
    func clearCallHistory() {
        settings.callHistory.removeAll()
    }

    /// Get AI agent profile
    func getAIAgentProfile() -> AIAgentProfile {
        return settings.aiAgentConfig.profile
    }

    /// Update AI agent profile
    func updateAIAgentProfile(_ profile: AIAgentProfile) {
        settings.aiAgentConfig.profile = profile
    }

    /// Get call handling mode
    func getCallHandlingMode() -> CallHandlingMode {
        return settings.aiAgentConfig.callHandlingMode
    }

    /// Set call handling mode
    func setCallHandlingMode(_ mode: CallHandlingMode) {
        settings.aiAgentConfig.callHandlingMode = mode
    }

    /// Add whitelist number
    func addWhitelistNumber(_ number: String) {
        if !settings.aiAgentConfig.whitelistedNumbers.contains(number) {
            settings.aiAgentConfig.whitelistedNumbers.append(number)
        }
    }

    /// Remove whitelist number
    func removeWhitelistNumber(_ number: String) {
        settings.aiAgentConfig.whitelistedNumbers.removeAll { $0 == number }
    }

    /// Add blocked number
    func addBlockedNumber(_ number: String) {
        if !settings.aiAgentConfig.blockedNumbers.contains(number) {
            settings.aiAgentConfig.blockedNumbers.append(number)
        }
    }

    /// Remove blocked number
    func removeBlockedNumber(_ number: String) {
        settings.aiAgentConfig.blockedNumbers.removeAll { $0 == number }
    }

    /// Get default actions for quick setup
    private func getDefaultActions() -> [ActionConfig] {
        return [
//            ActionConfig(
//                name: "Emergency Call",
//                actionType: .distressCall,
//                triggerType: .actionButton,
//                message: "🚨 EMERGENCY: I need immediate help! Location: {location} Battery {battery} Time: {time}",
//                includeLocation: true,
//                includeDynamicInfo: true,
//                isEnabled: true
//            )
        ]
    }

    /// Get default emergency contacts for testing
    private func getDefaultContacts() -> [EmergencyContact] {
        return [
            EmergencyContact(
                name: "Arya",
                phoneNumber: "+14259791562", // Replace with actual test number
                relationship: "Developer",
                isPrimary: true
            ),
            EmergencyContact(
                name: "Kevin",
                phoneNumber: "+14255259964", // Replace with actual test number
                relationship: "Developer",
                isPrimary: false
            )
        ]
    }

    /// Create a default test action for simulator testing
    private func createDefaultTestAction() -> ActionConfig {
        return getDefaultActions()[0] // Return the first default action
    }

    /// Update an existing action
    func updateAction(_ actionId: UUID, update: (inout ActionConfig) -> Void) {
        if let index = settings.actions.firstIndex(where: { $0.id == actionId }) {
            update(&settings.actions[index])
            notifyActionMapperOfChanges()
        }
    }

    /// Remove an action
    func removeAction(_ actionId: UUID) {
        settings.actions.removeAll { $0.id == actionId }
        notifyActionMapperOfChanges()
    }

    /// Notify ActionMapper when actions change
    private func notifyActionMapperOfChanges() {
        // Use a small delay to avoid infinite loops and to ensure the settings are fully updated
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            print("🔄 [SETTINGS DEBUG] Notifying ActionMapper of action changes...")
            ActionMapper.shared.refreshTriggerMonitoring()
        }
    }
}
