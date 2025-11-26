//
//  EmergencyCallOrchestrator.swift
//  discreetly
//
//  Orchestrates emergency calls with sensor data integration and Ultravox AI
//

import Foundation
import CoreLocation
import CoreMotion
import Combine

@MainActor
final class EmergencyCallOrchestrator: ObservableObject {
    static let shared = EmergencyCallOrchestrator()

    @Published var isEmergencyCallActive = false
    @Published var currentEmergencyCall: EmergencyCallSession?
    @Published var callProgress: EmergencyCallProgress = .idle

    private let sensorDataService = SensorDataService.shared
    private let ultravoxService = UltravoxService.shared
    private let twilioService = TwilioService.shared
    private let settingsManager = SettingsManager.shared

    private var cancellables = Set<AnyCancellable>()

    private init() {
        setupObservers()
    }

    private func setupObservers() {
        // Monitor Ultravox call status
        ultravoxService.$callStatus
            .sink { [weak self] status in
                self?.handleUltravoxStatusChange(status)
            }
            .store(in: &cancellables)

        // Monitor sensor data collection
        // Note: Removed automatic handling to prevent race conditions
        // Sensor data collection is now handled synchronously in the call flow
    }

    // MARK: - Emergency Call Initiation

    /// Initiate an emergency call with full sensor data integration
    func initiateEmergencyCall(
        to phoneNumber: String,
        emergencyLevel: EmergencyLevel,
        actionConfig: ActionConfig? = nil
    ) async {
        print("🚨🚨🚨 EmergencyCallOrchestrator.initiateEmergencyCall() CALLED")
        print("   📞 Phone Number: \(phoneNumber)")
        print("   🚨 Emergency Level: \(emergencyLevel.rawValue) (\(emergencyLevel.description))")
        print("   📱 Already Active: \(isEmergencyCallActive)")

        guard !isEmergencyCallActive else {
            print("❌ Emergency call already in progress - EXITING")
            return
        }

        print("✅ Starting emergency call process...")
        callProgress = .initiating
        isEmergencyCallActive = true

        // Create emergency call session
        currentEmergencyCall = EmergencyCallSession(
            phoneNumber: phoneNumber,
            emergencyLevel: emergencyLevel,
            actionConfig: actionConfig
        )

        print("🚨 Initiating emergency call to \(phoneNumber) - Level: \(emergencyLevel.description)")

        // Step 1: Collect comprehensive sensor data
        await collectSensorData()

        // Step 2: Determine call method based on configuration
        await initiateAppropriateCall()
    }

    // MARK: - Sensor Data Collection

    private func collectSensorData() async {
        callProgress = .collectingSensorData
        print("📊 Collecting sensor data for emergency call...")

        let sensorData = await sensorDataService.collectAllSensorData()

        print("🔍 Before assignment - currentEmergencyCall exists: \(currentEmergencyCall != nil)")

        // Update the struct properly
        if var session = currentEmergencyCall {
            session.sensorData = sensorData
            session.sensorDataCollectedAt = Date()
            currentEmergencyCall = session
            print("🔍 After assignment - sensorData assigned: \(session.sensorData != nil)")
        } else {
            print("❌ CRITICAL: currentEmergencyCall is nil during sensor data assignment!")
        }

        print("✅ Sensor data collected: Location: \(sensorData.location?.coordinate.description ?? "unknown"), Battery: \(sensorData.batteryLevel)%")
    }

    private func handleSensorDataCollected() {
        if callProgress == .collectingSensorData {
            Task {
                await initiateAppropriateCall()
            }
        }
    }

    // MARK: - Call Method Selection

    private func initiateAppropriateCall() async {
        guard let session = currentEmergencyCall,
              let sensorData = session.sensorData else {
            await handleEmergencyCallError(EmergencyCallError.missingSensorData)
            return
        }

        // Check if Ultravox is configured and preferred
        let ultravoxConfigured = isUltravoxConfigured()
        let shouldUseUltravoxForLevel = shouldUseUltravox(for: session.emergencyLevel)

        print("🔍 Emergency Call Decision:")
        print("   Emergency Level: \(session.emergencyLevel.rawValue) (\(session.emergencyLevel.description))")
        print("   Ultravox configured: \(ultravoxConfigured)")
        print("   Should use Ultravox for \(session.emergencyLevel): \(shouldUseUltravoxForLevel)")
        print("   API Key present: \(ultravoxService.apiKey != nil)")
        print("   Agent ID present: \(ultravoxService.agentId != nil)")
        print("   Settings enableUltravoxAI: \(settingsManager.settings.enableUltravoxAI)")
        print("   Settings preferredCallMethod: \(settingsManager.settings.preferredCallMethod.rawValue)")

        if ultravoxConfigured && shouldUseUltravoxForLevel {
            print("✅ Using Ultravox for emergency call")
            await initiateUltravoxCall(session: session, sensorData: sensorData)
        } else {
            print("⚠️ Falling back to Twilio for emergency call")
            await initiateTwilioCall(session: session, sensorData: sensorData)
        }
    }

    private func isUltravoxConfigured() -> Bool {
        return ultravoxService.apiKey != nil && ultravoxService.agentId != nil
    }

    private func shouldUseUltravox(for emergencyLevel: EmergencyLevel) -> Bool {
        let settings = settingsManager.settings

        print("🔍 Ultravox Settings Check:")
        print("   enableUltravoxAI: \(settings.enableUltravoxAI)")
        print("   preferredCallMethod: \(settings.preferredCallMethod)")

        // Check user preference first
        guard settings.enableUltravoxAI else {
            print("❌ Ultravox AI is disabled in settings")
            return false
        }

        switch settings.preferredCallMethod {
        case .ultravoxOnly:
            return true
        case .twilioOnly:
            return false
        default:
            // Use Ultravox for high priority emergencies (user cant talk)
            switch emergencyLevel {
            case .high:
                return true
            default:
                return false // Use Twilio
            }
        }
    }

    // MARK: - Ultravox Call Initiation

    private func initiateUltravoxCall(session: EmergencyCallSession, sensorData: SensorData) async {
        do {
            callProgress = .connectingUltravox
            print("🤖 Initiating Ultravox AI emergency call...")

            let ultravoxCall = try await ultravoxService.createTelephonyCall(
                to: session.phoneNumber,
                with: sensorData,
                emergencyLevel: session.emergencyLevel
            )

            var updatedSession = session
            updatedSession.ultravoxCall = ultravoxCall
            updatedSession.callMethod = .ultravox
            currentEmergencyCall = updatedSession
            callProgress = .connected

            print("✅ Ultravox emergency call initiated: \(ultravoxCall.id)")
            print("📞 Call is being routed through Twilio infrastructure - no app audio needed")

            // For telephony calls, monitor via API polling rather than WebSocket
            await monitorUltravoxTelephonyCall(ultravoxCall)

        } catch {
            print("❌ Ultravox call failed, falling back to Twilio: \(error)")
            await initiateTwilioCall(session: session, sensorData: sensorData)
        }
    }

    // MARK: - Twilio Call Initiation

    private func initiateTwilioCall(session: EmergencyCallSession, sensorData: SensorData) async {
        callProgress = .connectingTwilio
        print("📞 Initiating Twilio emergency call...")

        // Create enhanced message with sensor data
        let message = createEmergencyMessage(with: sensorData, emergencyLevel: session.emergencyLevel)

        // Use existing TwilioService for the call
        await twilioService.makeCovertCall(to: session.phoneNumber)

        var updatedSession = session
        updatedSession.callMethod = .twilio
        updatedSession.emergencyMessage = message
        currentEmergencyCall = updatedSession
        callProgress = .connected

        print("✅ Twilio emergency call initiated to \(session.phoneNumber)")
    }

    // MARK: - Message Creation

    private func createEmergencyMessage(with sensorData: SensorData, emergencyLevel: EmergencyLevel) -> String {
        // Get user name for personalization
        let userName = settingsManager.settings.contacts.first(where: { $0.isPrimary })?.name ?? "Emergency Contact"

        var message = "🚨 EMERGENCY ALERT - \(emergencyLevel.description)\n"
        message += "Person in Distress: \(userName)\n\n"

        // Add detailed timestamp with timezone
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .full
        message += "Alert Triggered: \(formatter.string(from: sensorData.timestamp))\n"
        message += "Timezone: \(TimeZone.current.identifier)\n\n"

        // Add comprehensive location information
        if let location = sensorData.location {
            message += "📍 LOCATION DETAILS:\n"

            // Add human-readable location name if available
            if let locationName = LocationService.shared.currentLocationName, !locationName.isEmpty {
                message += "Location: \(locationName)\n"
            }

            message += "GPS: \(String(format: "%.6f", location.coordinate.latitude)), \(String(format: "%.6f", location.coordinate.longitude))\n"
            message += "Google Maps: https://maps.google.com/?q=\(location.coordinate.latitude),\(location.coordinate.longitude)\n"
            message += "Apple Maps: https://maps.apple.com/?q=\(location.coordinate.latitude),\(location.coordinate.longitude)\n"

            if let accuracy = sensorData.locationAccuracy {
                message += "Accuracy: \(accuracy)\n"
            }
            if let altitude = sensorData.altitude {
                message += "Altitude: \(altitude)m\n"
            }
        } else {
            message += "📍 LOCATION: GPS unavailable (may be indoors)\n"
        }

        // Add device and sensor information
        message += "\n📱 DEVICE STATUS:\n"
        message += "Battery: \(sensorData.batteryLevel)% (\(sensorData.batteryState))\n"
        message += "Orientation: \(sensorData.deviceOrientation)\n"
        message += "Network: \(sensorData.networkStatus)\n"
        if let signal = sensorData.cellularSignalStrength {
            message += "Signal: \(signal)\n"
        }

        // Add motion data if significant (potential fall detection)
        if let motion = sensorData.deviceMotion {
            let gravityMagnitude = sqrt(pow(motion.gravity.x, 2) + pow(motion.gravity.y, 2) + pow(motion.gravity.z, 2))
            // Only include if magnitude suggests unusual movement
            if gravityMagnitude < 0.8 || gravityMagnitude > 1.2 {
                message += "Motion Alert: Unusual device movement detected\n"
            }
        }

        // Add device capabilities
        message += "\n📞 COMMUNICATION:\n"
        message += "Microphone: \(sensorData.microphonePermission)\n"
        message += "Camera: \(sensorData.cameraPermission)\n"

        // Add emergency escalation info
        message += "\n⏰ ESCALATION:\n"
        message += "Priority Level: \(emergencyLevel.rawValue)/5\n"
        if emergencyLevel.escalationDelay > 0 {
            message += "Next escalation in: \(Int(emergencyLevel.escalationDelay)) seconds\n"
        } else {
            message += "IMMEDIATE RESPONSE REQUIRED\n"
        }

        // Add emergency contacts
        let emergencyContacts = settingsManager.settings.contacts
        if !emergencyContacts.isEmpty {
            message += "\n👥 EMERGENCY CONTACTS:\n"
            for contact in emergencyContacts {
                var contactInfo = "- \(contact.name): \(contact.phoneNumber)"
                if let relationship = contact.relationship {
                    contactInfo += " (\(relationship))"
                }
                if contact.isPrimary {
                    contactInfo += " [PRIMARY]"
                }
                message += "\(contactInfo)\n"
            }
        } else {
            message += "\n⚠️ No emergency contacts configured\n"
        }

        // Add call to action
        message += "\n🚨 ACTION REQUIRED:\n"
        switch emergencyLevel {
        case .low, .medium:
            message += "Please check on \(userName) or call them back.\n"
        case .high:
            message += "Immediate contact recommended - \(userName) may need assistance.\n"
        case .critical, .extreme:
            message += "URGENT: Consider contacting emergency services for \(userName).\n"
        }

        message += "\nThis is an automated emergency alert from the Discreetly app."

        return message
    }

    // MARK: - Call Monitoring

    private func monitorUltravoxTelephonyCall(_ call: UltravoxCall) async {
        // Monitor telephony call status via API polling (not WebSocket)
        print("👁️ Monitoring Ultravox telephony call: \(call.id)")

        // Poll call status every 5 seconds
        while currentEmergencyCall?.callMethod == .ultravox {
            do {
                let callStatus = try await ultravoxService.getCallStatus(call.id)

                await MainActor.run {
                    switch callStatus.lowercased() {
                    case "active", "in-progress":
                        self.callProgress = .active
                    case "completed", "ended":
                        self.callProgress = .ending
                        Task { await self.endEmergencyCall() }
                        return
                    case "failed", "error":
                        Task { await self.handleEmergencyCallError(EmergencyCallError.callFailed("Ultravox call failed")) }
                        return
                    default:
                        break
                    }
                }

                // Wait 5 seconds before next poll
                try await Task.sleep(nanoseconds: 5_000_000_000)

            } catch {
                print("❌ Error monitoring Ultravox call: \(error)")
                await handleEmergencyCallError(EmergencyCallError.callFailed("Failed to monitor call"))
                return
            }
        }
    }

    private func handleUltravoxStatusChange(_ status: UltravoxCallStatus) {
        switch status {
        case .connected:
            callProgress = .active
        case .ended:
            Task { await endEmergencyCall() }
        case .error(let message):
            Task { await handleEmergencyCallError(EmergencyCallError.callFailed(message)) }
        default:
            break
        }
    }

    // MARK: - Call Termination

    func endEmergencyCall() async {
        guard isEmergencyCallActive else { return }

        callProgress = .ending
        print("🔚 Ending emergency call...")

        // End Ultravox call if active
        if currentEmergencyCall?.callMethod == .ultravox {
            await ultravoxService.endCall()
        }

        // End Twilio call if active
        if currentEmergencyCall?.callMethod == .twilio {
            twilioService.hangUp()
        }

        // Finalize session
        currentEmergencyCall?.endedAt = Date()
        currentEmergencyCall?.duration = currentEmergencyCall?.endedAt?.timeIntervalSince(currentEmergencyCall?.startedAt ?? Date())

        // Save to call history
        if let session = currentEmergencyCall {
            saveEmergencyCallToHistory(session)
        }

        // Reset state
        isEmergencyCallActive = false
        currentEmergencyCall = nil
        callProgress = .idle

        print("✅ Emergency call ended and saved to history")
    }

    // MARK: - Error Handling

    private func handleEmergencyCallError(_ error: Error) async {
        print("❌ Emergency call error: \(error.localizedDescription)")

        callProgress = .error(error.localizedDescription)
        currentEmergencyCall?.error = error.localizedDescription

        // Attempt fallback if this was an Ultravox call
        if let session = currentEmergencyCall,
           session.callMethod == .ultravox,
           let sensorData = session.sensorData {
            print("🔄 Attempting Twilio fallback...")
            await initiateTwilioCall(session: session, sensorData: sensorData)
        } else {
            // No more fallbacks, end the call attempt
            await endEmergencyCall()
        }
    }

    // MARK: - History Management

    private func saveEmergencyCallToHistory(_ session: EmergencyCallSession) {
        let callRecord = CallRecord(
            callerNumber: session.phoneNumber,
            callerName: "Emergency Call"
        )

        // Update call record with session data
        var updatedRecord = callRecord
        updatedRecord.endTime = session.endedAt
        updatedRecord.duration = session.duration
        updatedRecord.status = .ended
        updatedRecord.summary = "Emergency call - \(session.emergencyLevel.description)"

        if let message = session.emergencyMessage {
            updatedRecord.transcript = message
        }

        settingsManager.addCallRecord(updatedRecord)
    }

}

// MARK: - Supporting Types

struct EmergencyCallSession {
    let id = UUID()
    let phoneNumber: String
    let emergencyLevel: EmergencyLevel
    let actionConfig: ActionConfig?
    let startedAt = Date()

    var endedAt: Date?
    var duration: TimeInterval?
    var callMethod: EmergencyCallMethod?
    var sensorData: SensorData?
    var sensorDataCollectedAt: Date?
    var ultravoxCall: UltravoxCall?
    var emergencyMessage: String?
    var error: String?
}

enum EmergencyCallMethod {
    case ultravox
    case twilio
}

enum EmergencyCallProgress: Equatable {
    case idle
    case initiating
    case collectingSensorData
    case connectingUltravox
    case connectingTwilio
    case connected
    case active
    case ending
    case ended
    case error(String)

    var description: String {
        switch self {
        case .idle: return "Ready"
        case .initiating: return "Initiating Emergency Call"
        case .collectingSensorData: return "Collecting Sensor Data"
        case .connectingUltravox: return "Connecting via Ultravox AI"
        case .connectingTwilio: return "Connecting via Twilio"
        case .connected: return "Connected"
        case .active: return "Call Active"
        case .ending: return "Ending Call"
        case .ended: return "Call Ended"
        case .error(let message): return "Error: \(message)"
        }
    }
}

enum EmergencyCallError: Error, LocalizedError {
    case missingSensorData
    case callFailed(String)
    case configurationError

    var errorDescription: String? {
        switch self {
        case .missingSensorData:
            return "Failed to collect sensor data for emergency call"
        case .callFailed(let message):
            return "Emergency call failed: \(message)"
        case .configurationError:
            return "Emergency call configuration error"
        }
    }
}
