import Foundation
import UIKit
import CoreLocation
import CoreMotion
import SwiftUI
import Combine

final class ActionMapper: ObservableObject {
    static let shared = ActionMapper()

    private let settingsManager = SettingsManager.shared
    private let locationService = LocationService.shared
    private let hapticService = HapticService.shared
    private let aiAgentService = AIAgentService()
    private let locationManager = CLLocationManager()
    private let actionButtonDetector = ActionButtonDetector()
    private let sensorDataService = SensorDataService.shared
    private let backgroundSensorMonitor = BackgroundSensorMonitor.shared
    private let healthTriggerService = HealthTriggerService.shared
    private let triggerWordDetector = TriggerWordDetector.shared
    private let motionDetectionService = MotionDetectionService.shared

    private var actionContext = ActionContext()

    @Published var showingSensorData = false
    @Published var lastTriggerTime: Date?
    @Published var showingAskAI = false
    @Published var showingAIResponse = false
    @Published var aiResponse: String = ""
    @Published var aiQuestion: String = ""

    // Action execution popup properties
    @Published var showingActionExecutionPopup = false
    @Published var executingActionName: String = ""
    @Published var executingActionType: ActionType = .textMessage
    @Published var isActionExecuting = false
    
    // Delayed trigger properties
    @Published var delayedActionTimer: Timer?
    @Published var remainingDelayTime: TimeInterval = 0
    @Published var showingDelayCountdown = false
    @Published var pendingDelayedAction: ActionConfig?

    init() {
        setupActionButtonDetection()
        setupHealthTriggerDetection()
        setupVoiceTriggerDetection()
        setupMovementTriggerDetection()
    }

    /// Start monitoring for all trigger types
    func startMonitoring() {
        actionButtonDetector.start()
        startHealthTriggerMonitoring()
        startVoiceTriggerMonitoring()
        startMovementTriggerMonitoring()
        print("🎯 All trigger monitoring started")
    }

    /// Stop monitoring for all trigger types
    func stopMonitoring() {
        actionButtonDetector.stop()
        healthTriggerService.stopMonitoring()
        triggerWordDetector.stopListening()
        motionDetectionService.stopMotionDetection()
        print("🛑 All trigger monitoring stopped")
    }

    /// Manually trigger an action (for testing or manual activation)
    func manualTrigger() {
        actionButtonDetector.manualTrigger()
    }

    /// Manually trigger movement detection for testing
    func manualTriggerMovement() {
        motionDetectionService.manuallyTriggerMovementTransition()
    }

    /// Reset movement rate limit for testing
    func resetMovementRateLimit() {
        motionDetectionService.resetRateLimit()
    }

    /// Refresh all trigger monitoring when actions are updated
    func refreshTriggerMonitoring() {
        print("🔄 [ACTION DEBUG] refreshTriggerMonitoring called")

        // Refresh health trigger monitoring
        healthTriggerService.stopMonitoring()
        startHealthTriggerMonitoring()

        // Refresh voice trigger monitoring
        refreshVoiceTriggerMonitoring()

        // Refresh movement trigger monitoring
        refreshMovementTriggerMonitoring()

        print("✅ [ACTION DEBUG] All trigger monitoring refreshed")
    }

    /// Debug method to log current trigger monitoring state
    func logCurrentTriggerState() {
        print("📊 [ACTION DEBUG] === CURRENT TRIGGER STATE ===")
        let enabledActions = settingsManager.getEnabledActions()
        print("📊 [ACTION DEBUG] Total enabled actions: \(enabledActions.count)")

        for (index, action) in enabledActions.enumerated() {
            print("📊 [ACTION DEBUG] \(index + 1). \(action.name) (\(action.triggerType)) - \(action.actionType)")
            if action.triggerType == .voiceTriggerWord {
                print("📊 [ACTION DEBUG]    Voice trigger word: '\(action.voiceTriggerWord ?? "nil")'")
            }
        }

        print("📊 [ACTION DEBUG] Voice detector listening: \(triggerWordDetector.isListening)")
        triggerWordDetector.logCurrentState()
        print("📊 [ACTION DEBUG] ================================")
    }

    private func setupActionButtonDetection() {
        actionButtonDetector.onActionButtonPressed = { [weak self] in
            self?.handleActionButtonPress()
        }
    }

    private func setupHealthTriggerDetection() {
        healthTriggerService.onHealthTriggerActivated = { [weak self] triggerType, value, description in
            self?.handleHealthTrigger(type: triggerType, value: value, description: description)
        }
    }

    private func setupVoiceTriggerDetection() {
        triggerWordDetector.onTriggerWordDetected = { [weak self] word, action in
            self?.handleVoiceTrigger(word: word, action: action)
        }
    }

    private func setupMovementTriggerDetection() {
        print("🏃‍♂️ [ACTION DEBUG] Setting up movement trigger detection callback")
        motionDetectionService.onRapidMovementTransition = { [weak self] in
            print("🏃‍♂️ [ACTION DEBUG] Movement trigger callback invoked!")
            self?.handleMovementTrigger()
        }
        print("🏃‍♂️ [ACTION DEBUG] Movement trigger callback setup complete")
    }

    private func startHealthTriggerMonitoring() {
        let healthActions = settingsManager.getEnabledActions().filter { action in
            action.triggerType == .respiratoryRate || action.triggerType == .heartRateVariability
        }

        if !healthActions.isEmpty {
            healthTriggerService.startMonitoring(for: healthActions)
            print("🫀 Health trigger monitoring started for \(healthActions.count) actions")
        }
    }

    private func startVoiceTriggerMonitoring() {
        print("🎤 [ACTION DEBUG] startVoiceTriggerMonitoring called")

        let allActions = settingsManager.getEnabledActions()
        print("🎤 [ACTION DEBUG] Total enabled actions: \(allActions.count)")

        let voiceActions = allActions.filter { action in
            action.triggerType == .voiceTriggerWord
        }
        print("🎤 [ACTION DEBUG] Voice trigger actions found: \(voiceActions.count)")

        for (index, action) in voiceActions.enumerated() {
            print("🎤 [ACTION DEBUG] Voice action \(index + 1): '\(action.name)' - trigger: '\(action.voiceTriggerWord ?? "nil")' - enabled: \(action.isEnabled)")
        }

        if !voiceActions.isEmpty {
            print("🎤 [ACTION DEBUG] Starting TriggerWordDetector with \(voiceActions.count) actions...")
            triggerWordDetector.startListening(for: voiceActions)
            let triggerWords = voiceActions.compactMap { $0.voiceTriggerWord }.joined(separator: ", ")
            print("🎤 [ACTION DEBUG] Voice trigger monitoring started for words: [\(triggerWords)]")
        } else {
            print("🎤 [ACTION DEBUG] No voice trigger actions found - skipping voice monitoring")
        }
    }

    private func refreshVoiceTriggerMonitoring() {
        print("🔄 [ACTION DEBUG] refreshVoiceTriggerMonitoring called")

        // Stop current voice monitoring
        triggerWordDetector.stopListening()
        print("🔄 [ACTION DEBUG] Stopped existing voice monitoring")

        // Add a small delay to allow cleanup to complete before restarting
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.startVoiceTriggerMonitoring()
            print("🔄 [ACTION DEBUG] Restarted voice monitoring with updated actions")
        }
    }

    private func startMovementTriggerMonitoring() {
        let movementActions = settingsManager.getEnabledActions().filter { action in
            action.triggerType == .waitForMovement
        }

        if !movementActions.isEmpty {
            motionDetectionService.startMotionDetection()
        }
    }

    private func refreshMovementTriggerMonitoring() {
        // Check if we have movement trigger actions
        let movementActions = settingsManager.getEnabledActions().filter { action in
            action.triggerType == .waitForMovement
        }

        if movementActions.isEmpty {
            // Stop motion detection if no movement actions are enabled
            motionDetectionService.stopMotionDetection()
        } else {
            // Start motion detection if we have movement actions
            if !motionDetectionService.isActive {
                motionDetectionService.startMotionDetection()
            }
        }
    }

    private func handleActionButtonPress() {
        // Check if there's an active delayed timer - if so, cancel it
        if showingDelayCountdown, let pendingAction = pendingDelayedAction {
            print("🚫 Action Button pressed while timer active - canceling")
            cancelDelayedAction()
            return  // This exits the function early
        }
        
        // Find actions configured for Action Button or Delayed Trigger
        let actionButtonActions = settingsManager.getEnabledActions().filter { action in
            action.triggerType == .actionButton || action.triggerType == .delay
        }

        guard let action = actionButtonActions.first else {
            print("❌ No action found for Action Button press")
            return
        }

        print("✅ Action Button pressed -> \(action.name)")
        Task {
            await executeAction(action)
        }
    }

    private func handleHealthTrigger(type: TriggerType, value: Double, description: String) {
        // Find actions configured for this health trigger type
        let healthActions = settingsManager.getEnabledActions().filter { action in
            action.triggerType == type
        }

        guard let action = healthActions.first else {
            print("❌ No action found for health trigger: \(type)")
            return
        }

        print("✅ Health trigger activated: \(description) -> \(action.name)")
        Task {
            await executeAction(action)
        }
    }

    private func handleVoiceTrigger(word: String, action: ActionConfig) {
        print("🎬 [ACTION DEBUG] handleVoiceTrigger called")
        print("🎬 [ACTION DEBUG] Trigger word: '\(word)'")
        print("🎬 [ACTION DEBUG] Action: '\(action.name)'")
        print("🎬 [ACTION DEBUG] Action type: \(action.actionType)")
        print("✅ [ACTION DEBUG] Voice trigger activated: '\(word)' -> \(action.name)")

        Task {
            print("🎬 [ACTION DEBUG] Executing action asynchronously...")
            await executeAction(action)
            print("🎬 [ACTION DEBUG] Action execution completed")
        }
    }

    private func handleMovementTrigger() {
        // Find actions configured for movement trigger
        let movementActions = settingsManager.getEnabledActions().filter { action in
            action.triggerType == .waitForMovement
        }

        guard let action = movementActions.first else {
            return
        }

        // Double-check that the action is enabled
        if !action.isEnabled {
            return
        }

        Task { @MainActor in
            await executeAction(action)
        }
    }

    /// Execute an action configuration
    func executeAction(_ action: ActionConfig) async {
        print("🎯 Executing action: \(action.name)")
        
        // Handle delayed triggers
        if action.triggerType == .delay {
            await handleDelayedTrigger(action)
            return
        }

        // Execute immediate action
        await performActionExecution(action)
    }
    
    /// Handle delayed trigger - start timer and execute after delay
    private func handleDelayedTrigger(_ action: ActionConfig) async {
        guard let delayDuration = action.delayDuration else {
            print("❌ No delay duration specified for delayed trigger")
            await performActionExecution(action)
            return
        }
        
        print("⏱️ Starting delayed trigger: \(action.name) - Delay: \(delayDuration)s")
        
        await MainActor.run {
            // Cancel any existing delayed action
            self.cancelDelayedAction()
            
            // Set up new delayed action
            self.pendingDelayedAction = action
            self.remainingDelayTime = delayDuration
            self.showingDelayCountdown = true
            
            // Start countdown timer
            self.delayedActionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
                guard let self = self else {
                    timer.invalidate()
                    return
                }
                
                self.remainingDelayTime -= 1
                
                if self.remainingDelayTime <= 0 {
                    // Timer finished - execute the action
                    timer.invalidate()
                    self.delayedActionTimer = nil
                    self.showingDelayCountdown = false
                    
                    print("⏰ Delayed trigger timer expired - executing action: \(action.name)")
                    
                    Task {
                        await self.performActionExecution(action)
                    }
                }
            }
        }
        
        print("⏱️ Delayed action timer started - will execute in \(delayDuration) seconds")
    }
    
    /// Cancel any pending delayed action
    func cancelDelayedAction() {
        delayedActionTimer?.invalidate()
        delayedActionTimer = nil
        pendingDelayedAction = nil
        remainingDelayTime = 0
        showingDelayCountdown = false
        print("🚫 Delayed action canceled")
    }

    /// Dismiss the action execution popup
    func dismissActionExecutionPopup() {
        showingActionExecutionPopup = false
        executingActionName = ""
        isActionExecuting = false
    }
    
    /// Perform the actual action execution (extracted from executeAction)
    private func performActionExecution(_ action: ActionConfig) async {
        print("🎯 Executing action: \(action.name)")

        // 1. UI updates and haptic feedback (immediate)
        await MainActor.run {
            self.lastTriggerTime = Date()
            // Show action execution popup for all actions except Ask AI
            if action.actionType != .ask {
                self.executingActionName = action.name
                self.executingActionType = action.actionType
                self.isActionExecuting = true
                self.showingActionExecutionPopup = true
            }
        }

        // Haptic feedback
        if settingsManager.settings.enableHapticFeedback {
            hapticService.success()
        }

        // 2. Get contacts (immediate - no async needed)
        let contacts = action.contacts.compactMap { id in
            settingsManager.settings.contacts.first { $0.id == id }
        }

        // 3. Execute based on action type
        switch action.actionType {
        case .distressCall:
            await collectSensorDataAndSendMessages(action: action, contacts: contacts)
            // PRIORITY 1: START EMERGENCY CALL IMMEDIATELY (doesn't need location)
            await initiateEmergencyCallImmediately(contacts: contacts)

            // PRIORITY 2-4: Do these in parallel while call is connecting
            await startLocationTracking()
            await activateEmergencyAI()

        case .textMessage:
            // For text messages, collect sensor data first then send
            await executeTextMessageAction(action: action, contacts: contacts)

        case .ask:
            // Ask for confirmation before proceeding
            await executeAskAction(action: action, contacts: contacts)

        case .covertCall:
            // Make a discreet emergency call
            await executeCovertCallAction(action: action, contacts: contacts)
        }

        // 4. Mark action execution as complete (for popup display)
        await MainActor.run {
            if action.actionType != .ask {
                self.isActionExecuting = false
            }
        }
    }
    
    // MARK: - Text Message Action Execution

    /// Execute a text message action - collect sensor data then send messages
    private func executeTextMessageAction(action: ActionConfig, contacts: [EmergencyContact]) async {
        if contacts.isEmpty {
            print("❌ No contacts specified for text message action")
            print("💡 Tip: Add contacts in Settings → Contacts")
            return
        }

        print("💬 TEXT MESSAGE ACTION ACTIVATED")
        print("📱 Preparing to send messages to \(contacts.count) contact(s)")

        // Collect sensor data for enhanced messaging
        await collectSensorDataAndSendMessages(action: action, contacts: contacts)
    }

    // MARK: - Ask Gemini AI Action Execution

    /// Execute an ask Gemini AI action - use pre-configured prompt and show response
    private func executeAskAction(action: ActionConfig, contacts: [EmergencyContact]) async {
        print("🤖 ASK GEMINI AI ACTION ACTIVATED")

        let question = action.message ?? "What can you help me with today?"
        print("🧠 Using pre-configured prompt: \(question)")

        await MainActor.run {
            self.aiQuestion = question
            self.aiResponse = ""
            self.showingAIResponse = true
        }

        do {
            let response = try await GeminiService.shared.askQuestion(question)
            print("✅ Gemini AI response: \(response)")

            await MainActor.run {
                self.aiResponse = response
            }
        } catch {
            print("❌ Failed to get response from Gemini AI: \(error.localizedDescription)")
            await MainActor.run {
                self.aiResponse = "Error: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Covert Call Action Execution

    /// Execute a covert call action - make discreet emergency call
    private func executeCovertCallAction(action: ActionConfig, contacts: [EmergencyContact]) async {
        if contacts.isEmpty {
            print("❌ No contacts specified for covert call action")
            print("💡 Tip: Add contacts in Settings → Contacts")
            return
        }

        print("🤫 COVERT CALL ACTION ACTIVATED")
        print("📞 Initiating discreet emergency call...")

        // Make call without obvious notifications or haptic feedback
        if let primaryContact = contacts.first(where: { $0.isPrimary }) ?? contacts.first {
            await initiateCovertCall(to: primaryContact)
        }

        // Optionally collect sensor data in background
        Task.detached { [weak self] in
            await self?.collectSensorDataAndSendMessages(action: action, contacts: contacts)
        }
    }

    private func initiateCovertCall(to contact: EmergencyContact) async {
        print("📞 Initiating covert call to \(contact.name) at \(contact.phoneNumber)")

        // Use EmergencyCallOrchestrator for covert call
        await EmergencyCallOrchestrator.shared.initiateEmergencyCall(
            to: contact.phoneNumber,
            emergencyLevel: .medium // Medium priority for covert calls
        )

        print("✅ Covert call initiated to \(contact.name)")
    }

    // MARK: - Immediate Emergency Call (No Location Needed)
    
    /// Initiate emergency call immediately - doesn't need location data
    private func initiateEmergencyCallImmediately(contacts: [EmergencyContact]) async {
        if contacts.isEmpty {
            print("❌ No contact specified for emergency call")
            print("💡 Tip: Add a contact in Settings → Contacts")
            return
        }

        print("🚨 EMERGENCY CALL STARTING IMMEDIATELY")
        
        // Initiate emergency call to primary contact
        if let primaryContact = contacts.first(where: { $0.isPrimary }) ?? contacts.first {
            await initiateEmergencyCall(to: primaryContact)
        }
    }
    
    /// Collect sensor data and send messages with location information
    private func collectSensorDataAndSendMessages(action: ActionConfig, contacts: [EmergencyContact]) async {
        print("📊 Collecting sensor data for text messages...")

        // Use instant sensor data from background monitor for immediate response
        let sensorData = backgroundSensorMonitor.isDataFresh
            ? backgroundSensorMonitor.getCurrentSensorData()
            : await sensorDataService.collectAllSensorData()

        let dataAge = backgroundSensorMonitor.dataAge
        print("📊 Using sensor data (age: \(String(format: "%.1f", dataAge))s, timestamp: \(sensorData.timestamp))")
        
        // Get location from sensor data
        var location: CLLocation?
        if action.includeLocation {
            location = sensorData.location
            if let loc = location {
                print("📍 Got location: \(loc.coordinate.latitude), \(loc.coordinate.longitude)")
            } else {
                print("❌ Failed to get location from sensor data")
            }
        }

        // Build message with dynamic content
        var message = action.message ?? ""
        if !message.isEmpty {
            message = DynamicMessageBuilder.build(
                template: message,
                location: location,
                includeDynamicInfo: action.includeDynamicInfo
            )
        }

        // Send text messages to all contacts with location data
        print("📱 Sending distress messages with location data")
        for contact in contacts {
            await sendDistressMessage(to: contact, message: message, location: location)
        }
    }

    private func sendDistressMessage(to contact: EmergencyContact, message: String, location: CLLocation?) async {
        print("📱 Sending distress message to \(contact.name)")

        // Get user name from settings for personalization
        let userName = settingsManager.settings.userName ?? "Unknown User"
        
        let fullMessage = if message.isEmpty {
            "Notification from: \(userName). Live location and movement tracking enabled."
        } else {
            // If the message doesn't already contain the user's name, prepend it
            if !message.contains(userName) {
                "Notification - \(userName):\n\(message)"
            } else {
                message
            }
        }

        // Prefer E.164 numbers; otherwise pass as-is
        let phone = contact.phoneNumber

        do {
            let response = try await TextbeltClient.shared.send(phone: phone, message: fullMessage)

            // Add haptic feedback for text message sent
            await MainActor.run {
                HapticService.shared.threeVibrations()
            }

            print("✅ Textbelt SMS sent to \(contact.name) (\(phone))")
            if let textId = response.textId {
                print("🆔 Text ID: \(textId)")
            }
            if let remaining = response.quotaRemaining {
                print("📊 Quota remaining: \(remaining)")
            }
        } catch {
            print("❌ Failed to send Textbelt SMS to \(contact.name) (\(phone)): \(error.localizedDescription)")
        }
    }

    private func initiateEmergencyCall(to contact: EmergencyContact) async {
        print("📞 Initiating emergency call to \(contact.name) at \(contact.phoneNumber)")

        // Use EmergencyCallOrchestrator which handles Ultravox/Twilio decision logic
        await EmergencyCallOrchestrator.shared.initiateEmergencyCall(
            to: contact.phoneNumber,
            emergencyLevel: .high // High priority for distress calls
        )

        print("✅ Emergency call initiated to \(contact.name)")
    }

    private func startLocationTracking() async {
        print("📍 Starting continuous location tracking")
        // Enable high-frequency location updates
        locationManager.startUpdatingLocation()
        // This would typically start a background service for location tracking
    }

    private func activateEmergencyAI() async {
        print("🤖 Activating AI agent for emergency call screening")
        // Set AI to emergency mode
        var emergencyConfig = settingsManager.settings.aiAgentConfig
        emergencyConfig.callHandlingMode = .emergency
        aiAgentService.updateConfig(emergencyConfig)
        aiAgentService.startAgent()
    }

    /// Execute a branched action configuration
    func executeBranchedAction(_ branchedAction: BranchedActionConfig) async {
        print("🌳 Executing branched action: \(branchedAction.name)")

        // Update context with current state
        updateActionContext()

        // Execute root action first
        await executeAction(branchedAction.rootAction)

        // Evaluate and execute branches
        for branch in branchedAction.branches {
            if branch.shouldExecute(context: actionContext) {
                print("✅ Branch '\(branch.name)' conditions met")
                await executeBranch(branch)
            } else {
                print("❌ Branch '\(branch.name)' conditions not met")
            }
        }
    }

    private func executeBranch(_ branch: ActionBranch) async {
        // Execute action if specified
        if let actionId = branch.actionId,
           let action = settingsManager.settings.actions.first(where: { $0.id == actionId }) {
            await executeAction(action)
        }

        // Execute nested branches
        if let nextBranches = branch.nextBranches {
            for nextBranch in nextBranches {
                if nextBranch.shouldExecute(context: actionContext) {
                    await executeBranch(nextBranch)
                }
            }
        }
    }

    private func updateActionContext() {
        // Update location if available
        Task {
            do {
                actionContext.location = try await locationService.getCurrentLocation()
            } catch {
                print("Failed to get location for context: \(error)")
            }
        }

        // Update other context properties
        actionContext.currentTime = Date()

        // Update battery level
        UIDevice.current.isBatteryMonitoringEnabled = true
        actionContext.batteryLevel = Int(UIDevice.current.batteryLevel * 100)
    }

}
