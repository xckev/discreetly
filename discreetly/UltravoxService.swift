//
//  UltravoxService.swift
//  discreetly
//
//  Ultravox AI integration for agentic calling with real-time voice conversations
//

import Foundation
import Combine
import CoreLocation
import CoreMotion
import UIKit

final class UltravoxService: NSObject, ObservableObject {
    static let shared: UltravoxService = {
        print("🌟 Creating UltravoxService shared instance...")
        return UltravoxService()
    }()

    @Published var isConnected = false
    @Published var currentCall: UltravoxCall?
    @Published var callStatus: UltravoxCallStatus = .idle
    @Published var conversationHistory: [UltravoxMessage] = []

    private var webSocketTask: URLSessionWebSocketTask?
    private var session = URLSession.shared

    // Public read-only access for configuration status
    var apiKey: String? { _apiKey }
    var agentId: String? { _agentId }

    private var _apiKey: String?
    private var _agentId: String?
    private var _twilioFromNumber: String?

    private let baseURL = "https://api.ultravox.ai"
    private let websocketURL = "wss://api.ultravox.ai"

    override init() {
        super.init()
        print("🚀 Initializing UltravoxService...")
        print("🔍 Base URL: \(baseURL)")
        print("🔍 WebSocket URL: \(websocketURL)")
        loadConfiguration()
        validateConfiguration()
        print("✅ UltravoxService initialization complete")
    }

    private func loadConfiguration() {
        print("🔧 Loading Ultravox configuration...")

        // Load API key and agent ID from app configuration (not user settings)
        self._apiKey = getAppUltravoxApiKey()
        self._agentId = getAppUltravoxAgentId()
        self._twilioFromNumber = getTwilioFromNumber()

        // Log configuration status (safely)
        if let apiKey = _apiKey {
            print("🔍 API Key loaded: \(String(apiKey.prefix(10)))...")
        } else {
            print("❌ API Key not found")
        }

        if let agentId = _agentId {
            print("🔍 Agent ID loaded: \(agentId)")
        } else {
            print("❌ Agent ID not found")
        }

        if let fromNumber = _twilioFromNumber {
            print("🔍 Twilio from number loaded: \(fromNumber)")
        } else {
            print("❌ Twilio from number not found")
        }

        print("✅ Configuration loading complete")
    }

    private func getAppUltravoxApiKey() -> String? {
        print("🔑 Looking up Ultravox API key...")

        // In production, this would come from your secure app configuration
        // You could store this in your backend and fetch it, or include it in the app bundle

        // Check Info.plist first
        if let bundleKey = Bundle.main.object(forInfoDictionaryKey: "ULTRAVOX_API_KEY") as? String {
            print("🔍 Found API key in Info.plist")
            return bundleKey
        } else {
            print("🔍 API key not found in Info.plist")
        }

        // Check environment variables as fallback
        if let envKey = ProcessInfo.processInfo.environment["ULTRAVOX_API_KEY"] {
            print("🔍 Found API key in environment variables")
            return envKey
        } else {
            print("🔍 API key not found in environment variables")
        }

        print("❌ API key not found in any source")
        return nil
    }

    private func getAppUltravoxAgentId() -> String? {
        print("🤖 Looking up Ultravox Agent ID...")

        // Agent ID configured for your app

        // Check Info.plist first
        if let bundleAgentId = Bundle.main.object(forInfoDictionaryKey: "ULTRAVOX_AGENT_ID") as? String {
            print("🔍 Found Agent ID in Info.plist")
            return bundleAgentId
        } else {
            print("🔍 Agent ID not found in Info.plist")
        }

        // Check environment variables as fallback
        if let envAgentId = ProcessInfo.processInfo.environment["ULTRAVOX_AGENT_ID"] {
            print("🔍 Found Agent ID in environment variables")
            return envAgentId
        } else {
            print("🔍 Agent ID not found in environment variables")
        }

        print("❌ Agent ID not found in any source")
        return nil
    }

    private func getTwilioFromNumber() -> String? {
        print("📞 Looking up Twilio from number...")

        // Check Info.plist first
        if let bundleNumber = Bundle.main.object(forInfoDictionaryKey: "TWILIO_FROM_NUMBER") as? String {
            print("🔍 Found Twilio from number in Info.plist")
            return bundleNumber
        } else {
            print("🔍 Twilio from number not found in Info.plist")
        }

        // Check environment variables as fallback
        if let envNumber = ProcessInfo.processInfo.environment["TWILIO_FROM_NUMBER"] {
            print("🔍 Found Twilio from number in environment variables")
            return envNumber
        } else {
            print("🔍 Twilio from number not found in environment variables")
        }

        print("❌ Twilio from number not found in any source")
        return nil
    }

    private func validateConfiguration() {
        print("✅ Validating Ultravox configuration...")

        let hasApiKey = _apiKey != nil && !_apiKey!.isEmpty
        let hasAgentId = _agentId != nil && !_agentId!.isEmpty
        let hasTwilioFromNumber = _twilioFromNumber != nil && !_twilioFromNumber!.isEmpty

        print("🔍 Configuration validation results:")
        print("   API Key: \(hasApiKey ? "✅ Valid" : "❌ Missing")")
        print("   Agent ID: \(hasAgentId ? "✅ Valid" : "❌ Missing")")
        print("   Twilio From Number: \(hasTwilioFromNumber ? "✅ Valid" : "❌ Missing")")

        if hasApiKey && hasAgentId && hasTwilioFromNumber {
            print("✅ Ultravox fully configured and ready for telephony calls")
        } else {
            print("⚠️ Ultravox configuration incomplete - some features may not work")
            if !hasApiKey {
                print("💡 Add ULTRAVOX_API_KEY to Info.plist or environment variables")
            }
            if !hasAgentId {
                print("💡 Add ULTRAVOX_AGENT_ID to Info.plist or environment variables")
            }
            if !hasTwilioFromNumber {
                print("💡 Add TWILIO_FROM_NUMBER to Info.plist or environment variables")
            }
        }
    }

    // MARK: - Agent-Based Call Creation

    func createAgentCall(with sensorData: SensorData, emergencyLevel: EmergencyLevel = .medium) async throws -> UltravoxCall {
        print("🚀 Creating Ultravox agent call...")
        print("🔍 Emergency level: \(emergencyLevel)")

        guard let apiKey = _apiKey, let agentId = _agentId else {
            print("❌ Cannot create agent call - missing configuration")
            print("   API Key present: \(_apiKey != nil)")
            print("   Agent ID present: \(_agentId != nil)")
            throw UltravoxError.missingConfiguration
        }

        print("✅ Configuration verified for agent call")

        let contextVariables = createContextVariables(from: sensorData, emergencyLevel: emergencyLevel)
        let callRequest = UltravoxAgentCallRequest(
            agentId: agentId,
            templateContext: contextVariables,
            metadata: [
                "emergency_level": emergencyLevel.rawValue.description,
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "app_version": "discreetly_v1.0"
            ]
        )

        let url = URL(string: "\(baseURL)/api/agents/\(agentId)/calls")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

        do {
            request.httpBody = try JSONEncoder().encode(callRequest)

            // Debug request
            print("🔍 Ultravox Agent Call API Request:")
            print("   URL: \(url)")
            print("   Method: POST")
            print("   Headers: X-API-Key: \(String(apiKey.prefix(10)))...")
            if let requestBody = String(data: request.httpBody!, encoding: .utf8) {
                print("   Request Body:")
                print(requestBody)
            }

            let (data, response) = try await session.data(for: request)

            // Debug response
            if let httpResponse = response as? HTTPURLResponse {
                print("🔍 Ultravox Agent Call API Response:")
                print("   Status: \(httpResponse.statusCode)")
                print("   Headers: \(httpResponse.allHeaderFields)")
                if let responseBody = String(data: data, encoding: .utf8) {
                    print("   Response Body:")
                    print(responseBody)
                }
            }

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 201 else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("❌ Agent call creation failed with status: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                print("❌ Error response: \(errorMessage)")
                throw UltravoxError.apiError("Failed to create agent call: \(errorMessage)")
            }

            do {
                let ultravoxCall = try JSONDecoder().decode(UltravoxCall.self, from: data)
                print("✅ Agent call created successfully: \(ultravoxCall.id)")
                print("🔍 Decoded call details: Status=\(ultravoxCall.status ?? "unknown"), JoinURL=\(ultravoxCall.joinUrl ?? "none")")

                DispatchQueue.main.async {
                    self.currentCall = ultravoxCall
                    self.callStatus = .created
                }

                return ultravoxCall
            } catch {
                print("❌ JSON decoding failed for agent call response")
                print("   Decoding error: \(error)")
                if let decodingError = error as? DecodingError {
                    print("   DecodingError details: \(decodingError.localizedDescription)")
                }
                if let responseString = String(data: data, encoding: .utf8) {
                    print("   Raw response data: \(responseString)")
                }
                throw UltravoxError.apiError("Failed to decode agent call response: \(error.localizedDescription)")
            }
        } catch {
            print("❌ Agent call creation error: \(error)")
            throw UltravoxError.networkError(error)
        }
    }

    // MARK: - WebRTC Test Call (matches successful curl format)

    func createWebRTCTestCall(
        with sensorData: SensorData,
        emergencyLevel: EmergencyLevel = .medium
    ) async throws -> UltravoxCall {
        guard let apiKey = _apiKey else {
            print("❌ Cannot create test call - missing API key configuration")
            throw UltravoxError.missingConfiguration
        }

        let contextVariables = createContextVariables(from: sensorData, emergencyLevel: emergencyLevel)
        let systemPrompt = createSystemPrompt(for: emergencyLevel, with: contextVariables)

        // Use the exact same format that worked in curl test
        let callRequest: [String: Any] = [
            "systemPrompt": systemPrompt,
            "temperature": 0.3,
            "medium": [
                "webRtc": [:]
            ],
            "metadata": [
                "emergency_level": emergencyLevel.rawValue.description,
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "app_version": "discreetly_v1.0",
                "call_type": "emergency_test"
            ]
        ]

        let url = URL(string: "\(baseURL)/api/calls")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: callRequest, options: .prettyPrinted)

            print("🧪 Creating Ultravox WebRTC test call...")
            if let requestBody = String(data: request.httpBody!, encoding: .utf8) {
                print("🔍 Test call request body:")
                print(requestBody)
            }

            let (data, response) = try await session.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                print("🔍 Test call response status: \(httpResponse.statusCode)")
                if let responseBody = String(data: data, encoding: .utf8) {
                    print("🔍 Test call response body:")
                    print(responseBody)
                }
            }

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 201 else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("❌ Test call creation failed")
                throw UltravoxError.apiError("Failed to create test call: \(errorMessage)")
            }

            let ultravoxCall = try JSONDecoder().decode(UltravoxCall.self, from: data)
            print("✅ WebRTC test call created successfully: \(ultravoxCall.id)")

            DispatchQueue.main.async {
                self.currentCall = ultravoxCall
                self.callStatus = .created
            }

            return ultravoxCall
        } catch {
            print("❌ Test call creation error: \(error)")
            throw UltravoxError.networkError(error)
        }
    }

    // MARK: - Telephony Outbound Call Creation (Twilio Integration)

    // MARK: - Manual Twilio Integration (matches working Node.js approach)

    func createTelephonyCall(
        to phoneNumber: String,
        with sensorData: SensorData,
        emergencyLevel: EmergencyLevel = .medium
    ) async throws -> UltravoxCall {
        print("📞 Creating Manual Twilio Integration Call")
        print("🔍 Phone number: \(phoneNumber)")
        print("🔍 Emergency level: \(emergencyLevel)")

        guard let apiKey = _apiKey else {
            print("❌ Cannot create telephony call - missing API key configuration")
            throw UltravoxError.missingConfiguration
        }

        guard let fromNumber = _twilioFromNumber else {
            print("❌ Cannot create telephony call - missing Twilio from number configuration")
            throw UltravoxError.missingConfiguration
        }

        print("✅ Step 1: Creating Ultravox call (manual approach)")
        print("🔍 Using API key: \(String(apiKey.prefix(10)))...")

        let contextVariables = createContextVariables(from: sensorData, emergencyLevel: emergencyLevel)
        let systemPrompt = createSystemPrompt(for: emergencyLevel, with: contextVariables)

        // Use the exact same format that worked in Node.js manual approach
        let callRequest: [String: Any] = [
            "systemPrompt": systemPrompt,
            "temperature": 0.3,
            "medium": [
                "twilio": [:] // Empty twilio object - no outgoing config (manual approach)
            ],
            "firstSpeakerSettings": [
                "agent": [:] // Assistant speaks first in outbound calls
            ],
            "metadata": [
                "emergency_level": emergencyLevel.rawValue.description,
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "app_version": "discreetly_v1.0",
                "call_type": "emergency_outbound_manual",
                "destination_phone": phoneNumber
            ]
        ]

        let url = URL(string: "\(baseURL)/api/calls")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: callRequest, options: .prettyPrinted)

            // Debug logging - show ALL request details
            print("🔍 Ultravox API Request Details:")
            print("   URL: \(request.url?.absoluteString ?? "nil")")
            print("   Method: \(request.httpMethod ?? "nil")")
            print("   Headers:")
            request.allHTTPHeaderFields?.forEach { key, value in
                if key.lowercased().contains("key") {
                    print("     \(key): \(String(value.prefix(10)))...")
                } else {
                    print("     \(key): \(value)")
                }
            }

            if let requestBody = String(data: request.httpBody!, encoding: .utf8) {
                print("🔍 Ultravox API Request Body:")
                print(requestBody)
            }

            let (data, response) = try await session.data(for: request)

            // Debug response
            if let httpResponse = response as? HTTPURLResponse {
                print("🔍 Ultravox Telephony API Response:")
                print("   Status: \(httpResponse.statusCode)")
                print("   Headers:")
                httpResponse.allHeaderFields.forEach { key, value in
                    print("     \(key): \(value)")
                }
                if let responseBody = String(data: data, encoding: .utf8) {
                    print("   Response Body:")
                    print(responseBody)
                }
            }

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 201 else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                print("❌ Telephony call creation failed with status: \(statusCode)")
                print("❌ Error response: \(errorMessage)")
                throw UltravoxError.apiError("Failed to create telephony call: \(errorMessage)")
            }

            let ultravoxCall: UltravoxCall
            do {
                ultravoxCall = try JSONDecoder().decode(UltravoxCall.self, from: data)

                DispatchQueue.main.async {
                    self.currentCall = ultravoxCall
                    self.callStatus = .created
                }

                print("✅ Step 1 Complete: Ultravox call created successfully:")
                print("   Call ID: \(ultravoxCall.id)")
                print("   Status: \(ultravoxCall.status ?? "unknown")")
                print("   Join URL: \(ultravoxCall.joinUrl ?? "none")")
            } catch {
                print("❌ JSON decoding failed for telephony call response")
                print("   Decoding error: \(error)")
                if let decodingError = error as? DecodingError {
                    print("   DecodingError details: \(decodingError.localizedDescription)")
                }
                if let responseString = String(data: data, encoding: .utf8) {
                    print("   Raw response data: \(responseString)")
                }
                throw UltravoxError.apiError("Failed to decode telephony call response: \(error.localizedDescription)")
            }

            // Step 2: Use TwilioService to make the actual phone call with TwiML pointing to Ultravox
            guard let joinUrl = ultravoxCall.joinUrl else {
                print("❌ No joinUrl received from Ultravox")
                throw UltravoxError.invalidJoinURL
            }

            print("✅ Step 2: Creating Twilio call with joinUrl...")
            print("🔗 Using joinUrl: \(joinUrl)")

            do {
                let twilioCallSid = try await createTwilioCallWithUltravoxStream(
                    to: phoneNumber,
                    from: fromNumber,
                    joinUrl: joinUrl
                )
                print("✅ Manual Twilio integration completed successfully!")
                print("🎯 Starting comprehensive call monitoring...")
                
                // Start comprehensive monitoring with both call IDs
                Task {
                    await startDualCallMonitoring(
                        ultravoxCall: ultravoxCall,
                        twilioCallSid: twilioCallSid
                    )
                }
                
            } catch {
                print("❌ Twilio call creation failed: \(error)")
                throw error
            }

            return ultravoxCall
        } catch {
            print("❌ Ultravox telephony call creation failed: \(error)")
            throw UltravoxError.networkError(error)
        }
    }

    // MARK: - Manual Twilio Integration Helper

    private func createTwilioCallWithUltravoxStream(
        to phoneNumber: String,
        from fromNumber: String,
        joinUrl: String
    ) async throws -> String {
        print("📞 Creating Twilio call with Ultravox stream integration")
        print("   To: \(phoneNumber)")
        print("   From: \(fromNumber)")
        print("   Stream URL: \(joinUrl)")

        // Create TwiML that connects the call to Ultravox stream
        let twiml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Response>
            <Connect>
                <Stream url="\(joinUrl)" />
            </Connect>
        </Response>
        """

        print("📜 Generated TwiML:")
        print(twiml)

        // Use TwilioService to make the call and return the call SID
        do {
            let twilioCallSid = try await TwilioService.shared.makeOutboundCallWithTwiML(
                to: phoneNumber,
                from: fromNumber,
                twiml: twiml
            )
            print("✅ Twilio call initiated successfully with Ultravox stream")
            print("📞 Twilio Call SID: \(twilioCallSid)")
            
            return twilioCallSid
        } catch {
            print("❌ Failed to create Twilio call: \(error)")
            throw error
        }
    }

    // MARK: - Public Monitoring Interface
    
    /// Public function for EmergencyCallOrchestrator to start monitoring
    func startCallMonitoring(_ call: UltravoxCall) async {
        await startDualCallMonitoring(ultravoxCall: call, twilioCallSid: nil)
    }

    // MARK: - System Prompt Creation

    private func createSystemPrompt(for emergencyLevel: EmergencyLevel, with context: [String: String]) -> String {
        // Get user name from settings for personalization
        let userName = SettingsManager.shared.settings.userName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unnamed User"

        var prompt = """
        You are an AI emergency response agent calling on behalf of \(userName) who has triggered an emergency alert.

        CRITICAL: This is an automated emergency call. You are calling to report that \(userName) has activated their emergency distress signal.

        EMERGENCY DETAILS:
        - Alert Level: \(emergencyLevel.description)
        - Time Triggered: \(context["timestamp"] ?? "Unknown")
        - Person in Distress: \(userName)
        """

        // Add comprehensive location information
        if let locationName = context["user_location_name"], !locationName.isEmpty {
            prompt += """

        LOCATION INFORMATION:
        - Location: \(locationName)
        - Location Accuracy: \(context["user_location_accuracy"] ?? "Unknown")
        """
            if let altitude = context["user_altitude"], altitude != "unknown" {
                prompt += "\n- Altitude: \(altitude) meters"
            }

        } else if let latitude = context["user_latitude"], let longitude = context["user_longitude"] {
            prompt += """

        LOCATION INFORMATION:
        - GPS Coordinates: \(latitude), \(longitude)
        - Location Accuracy: \(context["user_location_accuracy"] ?? "Unknown")
        """
            if let altitude = context["user_altitude"], altitude != "unknown" {
                prompt += "\n- Altitude: \(altitude) meters"
            }

        } else {
            prompt += """

        LOCATION: GPS location not available
        """
        }

        // Add comprehensive device and sensor information
        prompt += """

        DEVICE STATUS:
        """
        if let battery = context["device_battery_level"] {
            prompt += "\n- Battery Level: \(battery) (\(context["device_battery_state"] ?? "Unknown state"))"
        }
        if let networkStatus = context["network_status"] {
            prompt += "\n- Network Status: \(networkStatus)"
        }
        if let cellularSignal = context["cellular_signal"] {
            prompt += "\n- Signal Strength: \(cellularSignal)"
        }

        // Add motion data if available
        if let gravityX = context["device_motion_gravity_x"], let gravityY = context["device_motion_gravity_y"], let gravityZ = context["device_motion_gravity_z"] {
            prompt += "\n- Device Motion: X:\(gravityX) Y:\(gravityY) Z:\(gravityZ) (may indicate fall or movement)"
        }

        // Add device capabilities
        prompt += """

        DEVICE CAPABILITIES:
        """
        if let micPermission = context["microphone_permission"] {
            prompt += "\n- Microphone: \(micPermission)"
        }
        if let cameraPermission = context["camera_permission"] {
            prompt += "\n- Camera: \(cameraPermission)"
        }
        if let audioAvailable = context["audio_input_available"] {
            prompt += "\n- Audio Input Available: \(audioAvailable)"
        }

        // Add Apple Watch health data if available
        if context["apple_watch_connected"] == "YES" {
            prompt += """

            APPLE WATCH HEALTH DATA:
            """
            
            // Critical health alerts
            if context["apple_watch_fall_detected"] == "YES - CRITICAL" {
                prompt += "\n- FALL DETECTED - CRITICAL ALERT"
                if let fallTime = context["apple_watch_last_fall_time"] {
                    prompt += "\n- Last Fall Time: \(fallTime)"
                }
            }
            
            // Heart rate data
            if let heartRate = context["apple_watch_heart_rate"] {
                prompt += "\n- Current Heart Rate: \(heartRate)"
            }
            if let restingHR = context["apple_watch_resting_hr"] {
                prompt += "\n- Resting Heart Rate: \(restingHR)"
            }
            if let hrv = context["apple_watch_hrv"] {
                prompt += "\n- Heart Rate Variability: \(hrv)"
            }
            
            // Activity today
            if let steps = context["apple_watch_steps"] {
                prompt += "\n- Steps Today: \(steps)"
            }
            if let activeEnergy = context["apple_watch_active_energy"] {
                prompt += "\n- Active Energy: \(activeEnergy)"
            }
            
            // Health metrics
            if let bloodOxygen = context["apple_watch_blood_oxygen"] {
                prompt += "\n- Blood Oxygen: \(bloodOxygen)"
            }
            if let bodyTemp = context["apple_watch_body_temperature"] {
                prompt += "\n- Body Temperature: \(bodyTemp)"
            }
            
            

        }

        // Add emergency contacts
        if let contacts = context["emergency_contacts_list"], !contacts.isEmpty {
            prompt += """

            EMERGENCY CONTACTS:
            \(contacts)
            """
        } else {
            prompt += "\n\nEMERGENCY CONTACTS: None configured"
        }

        prompt += """


        YOUR ROLE AND BEHAVIOR:
        1. IMMEDIATELY identify yourself as an AI emergency agent calling for \(userName)
        2. State that \(userName) has triggered an emergency alert and may need assistance.
        3. Provide the most important information upfront: location, time, or any critical health alerts.
        4. Let them know that you have sent them a text with the location coordinates.
        5. Always answer any questions asked by them.
        5. Be very CLEAR and CONCISE in your speech. Communication needs to be efficient.
        6. Ask if they can check on \(userName) or if emergency services should be contacted.
        7. Provide other contextual information on a need-to-know basis. You may be asked some questions by the responder.
        8. Stay on the line until the recipient confirms they understand and will take action (or if they hang up).

        SAMPLE OPENING: "This is an emergency AI agent calling on behalf of \(userName). They have activated an emergency alert and may need immediate assistance."

        Remember: Be thorough, clear, and helpful.
        """

        return prompt
    }

    // MARK: - WebSocket Connection for Real-time Communication (In-App Calls Only)
    // NOTE: Only use this for in-app voice calls. For telephony calls, audio is handled by Twilio infrastructure.

    func connectToCall(_ call: UltravoxCall) async throws {
        guard let joinUrl = call.joinUrl else {
            throw UltravoxError.invalidJoinURL
        }

        guard let url = URL(string: joinUrl) else {
            throw UltravoxError.invalidJoinURL
        }

        webSocketTask = session.webSocketTask(with: url)

        await MainActor.run {
            self.callStatus = .connecting
        }

        webSocketTask?.resume()

        // Start listening for messages
        await listenForMessages()

        await MainActor.run {
            self.isConnected = true
            self.callStatus = .connected
        }
    }

    private func listenForMessages() async {
        guard let webSocketTask = webSocketTask else { return }

        do {
            let message = try await webSocketTask.receive()

            switch message {
            case .string(let text):
                await handleTextMessage(text)
            case .data(let data):
                await handleDataMessage(data)
            @unknown default:
                print("Unknown WebSocket message type")
            }

            // Continue listening
            await listenForMessages()

        } catch {
            print("WebSocket error: \(error)")
            await MainActor.run {
                self.isConnected = false
                self.callStatus = .error(error.localizedDescription)
            }
        }
    }

    private func handleTextMessage(_ text: String) async {
        guard let data = text.data(using: .utf8) else { return }

        do {
            let message = try JSONDecoder().decode(UltravoxWebSocketMessage.self, from: data)

            await MainActor.run {
                switch message.type {
                case .transcript:
                    if let transcript = message.transcript {
                        self.conversationHistory.append(UltravoxMessage(
                            role: transcript.speaker == "user" ? .user : .assistant,
                            content: transcript.text,
                            timestamp: Date()
                        ))
                    }
                case .callStatus:
                    if let status = message.callStatus {
                        self.callStatus = UltravoxCallStatus(from: status)
                    }
                case .error:
                    self.callStatus = .error(message.error?.message ?? "Unknown error")
                }
            }
        } catch {
            print("Failed to decode WebSocket message: \(error)")
        }
    }

    private func handleDataMessage(_ data: Data) async {
        // Handle binary data (audio streams, etc.)
        print("Received binary data: \(data.count) bytes")
    }

    // MARK: - Send Messages

    func sendMessage(_ text: String) async throws {
        guard let webSocketTask = webSocketTask else {
            throw UltravoxError.notConnected
        }

        let message = UltravoxSendMessage(
            type: "user_message",
            text: text
        )

        let data = try JSONEncoder().encode(message)
        let messageString = String(data: data, encoding: .utf8)!

        try await webSocketTask.send(.string(messageString))
    }

    // MARK: - Context Variables Creation

    private func createContextVariables(from sensorData: SensorData, emergencyLevel: EmergencyLevel) -> [String: String] {
        var context: [String: String] = [:]

        // Get current date/time for detailed timestamp
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        dateFormatter.timeStyle = .full
        context["timestamp"] = dateFormatter.string(from: sensorData.timestamp)

        // Add timezone for better context
        let timeZone = TimeZone.current.identifier
        context["timezone"] = timeZone

        // Location data with enhanced details
        if let location = sensorData.location {
            // Add human-readable location name
            Task {
                let locationName = await LocationService.shared.getLocationName(from: location)
                context["user_location_name"] = locationName
            }

            context["user_latitude"] = String(format: "%.6f", location.coordinate.latitude)
            context["user_longitude"] = String(format: "%.6f", location.coordinate.longitude)
            context["user_location_accuracy"] = sensorData.locationAccuracy ?? "unknown"
            context["user_altitude"] = sensorData.altitude?.description ?? "unknown"

            // Add location name from LocationService if available
            if let locationName = LocationService.shared.currentLocationName {
                context["user_location_name"] = locationName
            }

            // Create multiple map service links for redundancy
            let lat = location.coordinate.latitude
            let lon = location.coordinate.longitude

            // Add location description if available (reverse geocoding could be added here)
            context["coordinates_readable"] = "Latitude: \(String(format: "%.6f", lat)), Longitude: \(String(format: "%.6f", lon))"
        } else {
            context["location_status"] = "GPS location unavailable - may be indoors or device issue"
        }

        // Enhanced device data
        // Handle battery level formatting (UIDevice returns -1.0 when monitoring unavailable)
        let batteryLevelFloat = Float(sensorData.batteryLevel)
        if batteryLevelFloat >= 0.0 && batteryLevelFloat <= 1.0 {
            let batteryPercentage = Int(batteryLevelFloat * 100)
            context["device_battery_level"] = "\(batteryPercentage)%"
        } else {
            context["device_battery_level"] = "Unknown"
        }
        context["device_battery_state"] = sensorData.batteryState
        context["device_orientation"] = sensorData.deviceOrientation

        // Add device model and OS info for emergency responders
        context["device_model"] = UIDevice.current.model
        context["device_os"] = "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"

        // Enhanced motion data for potential fall detection
        if let motion = sensorData.deviceMotion {
            context["device_motion_gravity_x"] = String(format: "%.2f", motion.gravity.x)
            context["device_motion_gravity_y"] = String(format: "%.2f", motion.gravity.y)
            context["device_motion_gravity_z"] = String(format: "%.2f", motion.gravity.z)

            // Calculate total gravity magnitude (useful for fall detection)
            let gravityMagnitude = sqrt(pow(motion.gravity.x, 2) + pow(motion.gravity.y, 2) + pow(motion.gravity.z, 2))
            context["gravity_magnitude"] = String(format: "%.2f", gravityMagnitude)

            // Add rotation rate if available
            context["rotation_rate_x"] = String(format: "%.2f", motion.rotationRate.x)
            context["rotation_rate_y"] = String(format: "%.2f", motion.rotationRate.y)
            context["rotation_rate_z"] = String(format: "%.2f", motion.rotationRate.z)
        }

        // Add accelerometer data if available
        if let accel = sensorData.accelerometerData {
            let accelMagnitude = sqrt(pow(accel.acceleration.x, 2) + pow(accel.acceleration.y, 2) + pow(accel.acceleration.z, 2))
            context["acceleration_magnitude"] = String(format: "%.2f", accelMagnitude)
            context["acceleration_details"] = "X:\(String(format: "%.2f", accel.acceleration.x)) Y:\(String(format: "%.2f", accel.acceleration.y)) Z:\(String(format: "%.2f", accel.acceleration.z))"
        }

        // Audio and communication capabilities
        context["microphone_permission"] = sensorData.microphonePermission
        context["audio_input_available"] = sensorData.audioInputAvailable ? "yes" : "no"
        context["audio_session_active"] = sensorData.audioSessionActive ? "yes" : "no"

        // Camera capabilities for potential evidence/verification
        context["camera_permission"] = sensorData.cameraPermission
        context["front_camera_available"] = sensorData.frontCameraAvailable ? "yes" : "no"
        context["back_camera_available"] = sensorData.backCameraAvailable ? "yes" : "no"

        // Contacts and emergency info
        context["emergency_contacts_count"] = "\(sensorData.emergencyContactsCount)"
        context["contacts_permission"] = sensorData.contactsPermission

        // Enhanced network status for emergency services
        context["network_status"] = sensorData.networkStatus
        if let signalStrength = sensorData.cellularSignalStrength {
            context["cellular_signal"] = signalStrength
        } else {
            context["cellular_signal"] = "Unknown"
        }

        // Emergency level and context with additional detail
        context["emergency_level"] = emergencyLevel.description
        context["emergency_priority"] = "\(emergencyLevel.rawValue)"
        context["emergency_escalation_time"] = "\(Int(emergencyLevel.escalationDelay)) seconds"

        // Add comprehensive emergency contacts list
        let emergencyContacts = SettingsManager.shared.settings.contacts
        if !emergencyContacts.isEmpty {
            let contactsInfo = emergencyContacts.map { contact in
                var info = "\(contact.name): \(contact.phoneNumber)"
                if let relationship = contact.relationship {
                    info += " (\(relationship))"
                }
                if contact.isPrimary {
                    info += " [PRIMARY]"
                }
                return info
            }.joined(separator: ", ")
            context["emergency_contacts_list"] = contactsInfo

            // Also provide primary contact separately
            if let primaryContact = emergencyContacts.first(where: { $0.isPrimary }) {
                context["primary_contact_name"] = primaryContact.name
                context["primary_contact_phone"] = primaryContact.phoneNumber
            }
        } else {
            context["emergency_contacts_list"] = "No emergency contacts configured"
        }

        // Add app-specific emergency context
        context["app_name"] = "Discreetly Emergency Alert"
        context["emergency_type"] = "Automated distress signal"

        // Calculate time since emergency was triggered (useful for response time)
        let timeSinceTrigger = Date().timeIntervalSince(sensorData.timestamp)
        context["time_since_trigger"] = "\(Int(timeSinceTrigger)) seconds ago"

        // Add Apple Watch Health Data if available
        if let healthData = sensorData.healthData {
            // Heart Rate Data
            if let heartRate = healthData.heartRate {
                context["apple_watch_heart_rate"] = "\(Int(heartRate)) BPM"
            }
            if let heartRateVariability = healthData.heartRateVariability {
                context["apple_watch_hrv"] = "\(String(format: "%.1f", heartRateVariability)) ms"
            }
            if let restingHeartRate = healthData.restingHeartRate {
                context["apple_watch_resting_hr"] = "\(Int(restingHeartRate)) BPM"
            }
            if let walkingHeartRateAverage = healthData.walkingHeartRateAverage {
                context["apple_watch_walking_hr_avg"] = "\(Int(walkingHeartRateAverage)) BPM"
            }

            // Activity Data
            if let activeEnergyBurned = healthData.activeEnergyBurned {
                context["apple_watch_active_energy"] = "\(Int(activeEnergyBurned)) kcal today"
            }
            if let stepCount = healthData.stepCount {
                context["apple_watch_steps"] = "\(Int(stepCount)) steps today"
            }
            if let distanceWalkingRunning = healthData.distanceWalkingRunning {
                context["apple_watch_distance"] = "\(String(format: "%.2f", distanceWalkingRunning/1000)) km today"
            }
            if let flightsClimbed = healthData.flightsClimbed {
                context["apple_watch_flights"] = "\(Int(flightsClimbed)) flights today"
            }
            if let appleExerciseTime = healthData.appleExerciseTime {
                context["apple_watch_exercise_time"] = "\(Int(appleExerciseTime)) minutes today"
            }
            if let appleStandHours = healthData.appleStandHours {
                context["apple_watch_stand_time"] = "\(Int(appleStandHours)) minutes today"
            }

            // Health Metrics
            if let oxygenSaturation = healthData.oxygenSaturation {
                context["apple_watch_blood_oxygen"] = "\(String(format: "%.1f", oxygenSaturation*100))%"
            }
            if let bodyTemperature = healthData.bodyTemperature {
                context["apple_watch_body_temperature"] = "\(String(format: "%.1f", bodyTemperature))°C"
            }
            if let respiratoryRate = healthData.respiratoryRate {
                context["apple_watch_respiratory_rate"] = "\(Int(respiratoryRate)) breaths/min"
            }

            // Environmental Data
            if let environmentalAudioExposure = healthData.environmentalAudioExposure {
                context["apple_watch_audio_exposure"] = "\(String(format: "%.1f", environmentalAudioExposure)) dB"
            }

            // Sleep Data
            if let sleepAnalysis = healthData.sleepAnalysis {
                context["apple_watch_sleep_analysis"] = sleepAnalysis
            }
            if let timeInBed = healthData.timeInBed {
                let hours = Int(timeInBed)
                let minutes = Int((timeInBed - Double(hours)) * 60)
                context["apple_watch_time_in_bed"] = "\(hours)h \(minutes)m"
            }
            if let timeAsleep = healthData.timeAsleep {
                let hours = Int(timeAsleep)
                let minutes = Int((timeAsleep - Double(hours)) * 60)
                context["apple_watch_time_asleep"] = "\(hours)h \(minutes)m"
            }

            // Fall Detection
            if healthData.fallDetected {
                context["apple_watch_fall_detected"] = "YES - CRITICAL"
                if let lastFallTime = healthData.lastFallTime {
                    let formatter = DateFormatter()
                    formatter.timeStyle = .short
                    context["apple_watch_last_fall_time"] = formatter.string(from: lastFallTime)
                }
            } else {
                context["apple_watch_fall_detected"] = "No"
            }

            // Mindfulness Data
            if let mindfulnessMinutes = healthData.mindfulnessMinutes {
                context["apple_watch_mindfulness"] = "\(Int(mindfulnessMinutes)) minutes today"
            }

            // Workout State
            context["apple_watch_in_workout"] = healthData.isInWorkout ? "YES" : "No"
            if let workoutType = healthData.workoutType {
                context["apple_watch_workout_type"] = workoutType
            }

            // Watch Hardware
            if let watchBatteryLevel = healthData.watchBatteryLevel {
                context["apple_watch_battery"] = "\(Int(watchBatteryLevel * 100))%"
            }
            if let watchOrientation = healthData.watchOrientation {
                context["apple_watch_orientation"] = watchOrientation
            }
            if let crownPosition = healthData.crownPosition {
                context["apple_watch_crown_position"] = crownPosition
            }

            // Apple Watch connectivity status
            let watchConnectivity = WatchConnectivityService.shared
            context["apple_watch_connected"] = watchConnectivity.isWatchConnected ? "YES" : "No"
            context["apple_watch_app_installed"] = watchConnectivity.isWatchAppInstalled ? "YES" : "No"
        } else {
            // Add Apple Watch status even if no health data
            let watchConnectivity = WatchConnectivityService.shared
            context["apple_watch_connected"] = watchConnectivity.isWatchConnected ? "YES" : "No"
            context["apple_watch_app_installed"] = watchConnectivity.isWatchAppInstalled ? "YES" : "No"
            context["apple_watch_health_data"] = "Not available"
        }

        return context
    }

    // MARK: - Twilio Outbound Call Initiation

    private func initiateTwilioOutboundCall(to phoneNumber: String, joinUrl: String) async throws {
        guard let accountSid = getTwilioAccountSid(),
              let authToken = getTwilioAuthToken(),
              let fromNumber = getTwilioFromNumber(),
              !accountSid.isEmpty,
              !authToken.isEmpty,
              !fromNumber.isEmpty else {
            throw UltravoxError.missingConfiguration
        }

        print("📞 Initiating Twilio outbound call to \(phoneNumber)")
        print("🔗 Connecting to Ultravox stream: \(joinUrl)")

        // Create TwiML that connects the call to Ultravox stream
        let twiml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Response>
            <Connect>
                <Stream url="\(joinUrl)" />
            </Connect>
        </Response>
        """

        // Base64 encode the TwiML for the Twilio API
        let twimlData = twiml.data(using: .utf8)!
        let base64TwiML = twimlData.base64EncodedString()

        // Create Twilio call request
        let twilioUrl = "https://api.twilio.com/2010-04-01/Accounts/\(accountSid)/Calls.json"
        var request = URLRequest(url: URL(string: twilioUrl)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        // HTTP Basic Auth with Account SID and Auth Token
        let credentials = "\(accountSid):\(authToken)"
        let credentialsData = credentials.data(using: .utf8)!
        let base64Credentials = credentialsData.base64EncodedString()
        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")

        // Request body parameters
        let bodyParams = [
            "To=\(phoneNumber)",
            "From=\(fromNumber)",
            "Twiml=\(base64TwiML)"
        ].joined(separator: "&")

        request.httpBody = bodyParams.data(using: .utf8)

        do {
            // Debug request
            print("🔍 Twilio Outbound API Request:")
            print("   URL: \(twilioUrl)")
            print("   Method: POST")
            if let requestBody = String(data: request.httpBody!, encoding: .utf8) {
                print("   Request Body:")
                print(requestBody)
            }

            let (data, response) = try await session.data(for: request)

            // Debug response
            if let httpResponse = response as? HTTPURLResponse {
                print("🔍 Twilio Outbound API Response:")
                print("   Status: \(httpResponse.statusCode)")
                if let responseBody = String(data: data, encoding: .utf8) {
                    print("   Response Body:")
                    print(responseBody)
                }
            }

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 201 else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                print("❌ Twilio outbound call failed with status: \(statusCode)")
                print("❌ Error response: \(errorMessage)")
                throw UltravoxError.apiError("Failed to create telephony call: \(errorMessage)")
            }

            print("✅ Twilio outbound call initiated successfully")
        } catch {
            print("❌ Twilio outbound call error: \(error)")
            throw UltravoxError.networkError(error)
        }
    }

    private func getTwilioAccountSid() -> String? {
        return SettingsManager.shared.settings.twilioAccountSid
    }

    private func getTwilioAuthToken() -> String? {
        return SettingsManager.shared.settings.twilioAuthToken
    }


    // MARK: - Call Status Monitoring (for Telephony Calls)

    // MARK: - Twilio Call Status Monitoring

    /// Monitor both Twilio and Ultravox call status, end Ultravox call when Twilio call ends
    /// 
    /// Test with curl:
    /// ```bash
    /// # Check Twilio call status
    /// curl -X GET "https://api.twilio.com/2010-04-01/Accounts/YOUR_ACCOUNT_SID/Calls/YOUR_CALL_SID.json" \
    ///   -u "YOUR_ACCOUNT_SID:YOUR_AUTH_TOKEN"
    /// 
    /// # Check Ultravox call status  
    /// curl -X GET "https://api.ultravox.ai/api/calls/YOUR_CALL_ID" \
    ///   -H "X-API-Key: YOUR_API_KEY"
    /// ```
    func monitorTwilioCallAndUpdateUltravox(
        twilioCallSid: String,
        ultravoxCallId: String
    ) async {
        print("👁️ Starting dual monitoring: Twilio SID=\(twilioCallSid), Ultravox ID=\(ultravoxCallId)")
        
        guard let accountSid = getTwilioAccountSid(),
              let authToken = getTwilioAuthToken() else {
            print("❌ Cannot monitor Twilio call - missing credentials")
            await monitorUltravoxTelephonyCall(currentCall!)
            return
        }
        
        var previousEndReason: String? = nil
        var monitoringActive = true
        
        while monitoringActive && currentCall?.id == ultravoxCallId {
            do {
                // Check Twilio call status
                let twilioStatus = try await getTwilioCallStatus(
                    callSid: twilioCallSid,
                    accountSid: accountSid,
                    authToken: authToken
                )
                
                print("📞 Twilio Call Status: \(twilioStatus.status)")
                print("🔚 End Reason: \(twilioStatus.endReason ?? "null")")
                
                // Check if call ended (endReason changed from null)
                if let endReason = twilioStatus.endReason, endReason != previousEndReason {
                    print("🚨 Twilio call ended with reason: \(endReason)")
                    
                    // Update Ultravox call status to reflect Twilio ending
                    try? await updateUltravoxCallStatus(ultravoxCallId, newStatus: "ended")
                    
                    // End the monitoring cycle
                    monitoringActive = false
                    
                    // End local Ultravox call state
                    await endCall()
                    
                    print("✅ Call monitoring ended - Twilio call completed")
                    return
                }
                
                // Update Ultravox status based on Twilio status
                let ultravoxStatus = mapTwilioToUltravoxStatus(twilioStatus.status)
                if !ultravoxStatus.isEmpty {
                    try? await updateUltravoxCallStatus(ultravoxCallId, newStatus: ultravoxStatus)
                }
                
                // Check if call is still active
                if twilioStatus.status.lowercased() == "completed" || 
                   twilioStatus.status.lowercased() == "failed" ||
                   twilioStatus.status.lowercased() == "canceled" {
                    print("🔚 Twilio call finished with status: \(twilioStatus.status)")
                    monitoringActive = false
                    await endCall()
                    return
                }
                
                previousEndReason = twilioStatus.endReason
                
                // Wait 5 seconds before next check
                try await Task.sleep(nanoseconds: 5_000_000_000)
                
            } catch {
                print("❌ Error monitoring calls: \(error)")
                // Continue monitoring on error, but with longer delay
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
        
        print("🔚 Dual call monitoring ended")
    }
    
    /// Get Twilio call status via API
    private func getTwilioCallStatus(
        callSid: String,
        accountSid: String,
        authToken: String
    ) async throws -> TwilioCallStatus {
        let url = URL(string: "https://api.twilio.com/2010-04-01/Accounts/\(accountSid)/Calls/\(callSid).json")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        // HTTP Basic Auth
        let credentials = "\(accountSid):\(authToken)"
        let credentialsData = credentials.data(using: .utf8)!
        let base64Credentials = credentialsData.base64EncodedString()
        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
        
        print("🔍 Twilio Call Status API Request:")
        print("   URL: \(url)")
        print("   Method: GET")
        print("   Curl equivalent:")
        print("   curl -X GET '\(url)' -u '\(accountSid):\(String(authToken.prefix(10)))...'")
        
        let (data, response) = try await session.data(for: request)
        
        // Debug response
        if let httpResponse = response as? HTTPURLResponse {
            print("🔍 Twilio Call Status API Response:")
            print("   Status: \(httpResponse.statusCode)")
            if let responseBody = String(data: data, encoding: .utf8) {
                print("   Response Body:")
                print(responseBody)
            }
        }
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw UltravoxError.apiError("Failed to get Twilio call status: \(errorMessage)")
        }
        
        // Parse Twilio response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UltravoxError.apiError("Invalid Twilio response format")
        }
        
        let status = json["status"] as? String ?? "unknown"
        let endReason = json["end_reason"] as? String // This will be null until call ends
        let duration = json["duration"] as? String
        let startTime = json["start_time"] as? String
        let endTime = json["end_time"] as? String
        
        return TwilioCallStatus(
            sid: callSid,
            status: status,
            endReason: endReason,
            duration: duration,
            startTime: startTime,
            endTime: endTime
        )
    }
    
    /// Update Ultravox call status via API
    private func updateUltravoxCallStatus(_ callId: String, newStatus: String) async throws {
        guard let apiKey = _apiKey else {
            throw UltravoxError.missingConfiguration
        }
        
        // Note: This may not be supported by Ultravox API - check documentation
        let url = URL(string: "\(baseURL)/api/calls/\(callId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        
        let updateData = ["status": newStatus]
        request.httpBody = try JSONSerialization.data(withJSONObject: updateData)
        
        print("🔄 Attempting to update Ultravox call status to: \(newStatus)")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("🔍 Ultravox Status Update Response: \(httpResponse.statusCode)")
                if let responseBody = String(data: data, encoding: .utf8) {
                    print("   Response: \(responseBody)")
                }
                
                if httpResponse.statusCode == 200 || httpResponse.statusCode == 204 {
                    print("✅ Ultravox call status updated to: \(newStatus)")
                } else {
                    print("⚠️ Ultravox status update failed (may not be supported)")
                }
            }
        } catch {
            print("⚠️ Could not update Ultravox status: \(error)")
            // Don't throw - status updates are nice-to-have, not critical
        }
    }
    
    /// Map Twilio call status to equivalent Ultravox status
    private func mapTwilioToUltravoxStatus(_ twilioStatus: String) -> String {
        switch twilioStatus.lowercased() {
        case "queued", "ringing":
            return "connecting"
        case "in-progress":
            return "active"
        case "completed":
            return "ended"
        case "failed", "canceled", "busy", "no-answer":
            return "ended"
        default:
            return ""
        }
    }

    // MARK: - Enhanced Call Monitoring

    /// Monitor Ultravox telephony call (fallback for when we don't have Twilio SID)
    func monitorUltravoxTelephonyCall(_ call: UltravoxCall) async {
        print("👁️ Monitoring Ultravox telephony call: \(call.id)")
        print("⚠️ Note: This is single-sided monitoring. For better results, use dual monitoring with Twilio SID")
        
        var consecutiveErrors = 0
        let maxConsecutiveErrors = 3
        
        while currentCall?.id == call.id {
            do {
                let status = try await getCallStatusWithRetry(call.id, maxRetries: 2)
                
                await MainActor.run {
                    switch status.lowercased() {
                    case "active", "in-progress", "connected":
                        self.callStatus = .active
                        print("✅ Call is active: \(status)")
                    case "completed", "ended":
                        self.callStatus = .ended
                        print("🔚 Call ended: \(status)")
                        Task { await self.endCall() }
                        return
                    case "failed", "error":
                        self.callStatus = .error("Call failed")
                        print("❌ Call failed: \(status)")
                        Task { await self.endCall() }
                        return
                    case "unknown":
                        print("⚠️ Call status unknown - continuing monitoring")
                    default:
                        print("🔍 Call status: \(status)")
                    }
                }
                
                consecutiveErrors = 0 // Reset error count on success
                
                // Wait 5 seconds before next check
                try await Task.sleep(nanoseconds: 5_000_000_000)
                
            } catch {
                consecutiveErrors += 1
                print("❌ Error monitoring call (attempt \(consecutiveErrors)/\(maxConsecutiveErrors)): \(error)")
                
                if consecutiveErrors >= maxConsecutiveErrors {
                    print("💥 Too many consecutive errors - stopping monitoring")
                    await MainActor.run {
                        self.callStatus = .error("Monitoring failed")
                    }
                    Task { await self.endCall() }
                    return
                }
                
                // Wait longer on error before retry
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
        
        print("🔚 Call monitoring ended - call object no longer current")
    }

    /// Start comprehensive monitoring of both Twilio and Ultravox calls
    func startDualCallMonitoring(
        ultravoxCall: UltravoxCall,
        twilioCallSid: String? = nil
    ) async {
        if let twilioSid = twilioCallSid {
            print("🎯 Starting dual monitoring: Ultravox + Twilio")
            await monitorTwilioCallAndUpdateUltravox(
                twilioCallSid: twilioSid,
                ultravoxCallId: ultravoxCall.id
            )
        } else {
            print("📞 Starting Ultravox-only monitoring (Twilio SID not available)")
            await monitorUltravoxTelephonyCall(ultravoxCall)
        }
    }

    func getCallStatus(_ callId: String) async throws -> String {
        guard let apiKey = _apiKey else {
            throw UltravoxError.missingConfiguration
        }

        let url = URL(string: "\(baseURL)/api/calls/\(callId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

        do {
            // Debug request
            print("🔍 Ultravox Call Status API Request:")
            print("   URL: \(url)")
            print("   Method: GET")
            print("   Headers: X-API-Key: \(String(apiKey.prefix(10)))...")

            let (data, response) = try await session.data(for: request)

            // Debug response
            if let httpResponse = response as? HTTPURLResponse {
                print("🔍 Ultravox Call Status API Response:")
                print("   Status: \(httpResponse.statusCode)")
                if let responseBody = String(data: data, encoding: .utf8) {
                    print("   Response Body:")
                    print(responseBody)
                }
            }

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                print("❌ Call status request failed with status: \(statusCode)")
                print("❌ Error response: \(errorMessage)")
                throw UltravoxError.apiError("Failed to get call status: \(errorMessage)")
            }

            do {
                let callData = try JSONDecoder().decode(UltravoxCall.self, from: data)
                print("✅ Call status retrieved: \(callData.status ?? "unknown")")
                print("🔍 Full call data: ID=\(callData.id), Status=\(callData.status ?? "unknown")")
                return callData.status ?? "unknown"
            } catch {
                print("❌ JSON decoding failed for call status response")
                print("   Decoding error: \(error)")
                if let decodingError = error as? DecodingError {
                    print("   DecodingError details: \(decodingError.localizedDescription)")
                }
                if let responseString = String(data: data, encoding: .utf8) {
                    print("   Raw response data: \(responseString)")
                }
                throw UltravoxError.apiError("Failed to decode call status response: \(error.localizedDescription)")
            }

        } catch {
            print("❌ Call status request error: \(error)")
            throw UltravoxError.networkError(error)
        }
    }
    
    /// Get call status with retry logic for handling "unknown" status
    func getCallStatusWithRetry(_ callId: String, maxRetries: Int = 3) async throws -> String {
        var lastStatus = "unknown"
        
        for attempt in 1...maxRetries {
            print("🔄 Attempt \(attempt)/\(maxRetries) to get call status")
            
            do {
                let status = try await getCallStatus(callId)
                
                if status != "unknown" && status != "null" {
                    print("✅ Got valid status: \(status)")
                    return status
                }
                
                lastStatus = status
                print("⏳ Status still unknown, waiting 3 seconds before retry...")
                
                // Wait 3 seconds before next attempt
                if attempt < maxRetries {
                    try await Task.sleep(nanoseconds: 3_000_000_000)
                }
                
            } catch {
                print("❌ Attempt \(attempt) failed: \(error)")
                if attempt == maxRetries {
                    throw error
                }
                // Wait before retry on error too
                try await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
        
        print("⚠️ All attempts exhausted, returning last known status: \(lastStatus)")
        return lastStatus
    }

    // MARK: - Call Management

    // MARK: - Call Management Utilities
    
    /// Force end a call immediately
    func forceEndCall(_ callId: String) async {
        print("🔚 Force ending call: \(callId)")
        
        // Try to update Ultravox call status to ended
        try? await updateUltravoxCallStatus(callId, newStatus: "ended")
        
        // End local call state
        await endCall()
        
        print("✅ Call force-ended")
    }
    
    /// Get comprehensive call information
    func getCallInfo(_ callId: String) async throws -> UltravoxCall {
        guard let apiKey = _apiKey else {
            throw UltravoxError.missingConfiguration
        }
        
        let url = URL(string: "\(baseURL)/api/calls/\(callId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw UltravoxError.apiError("Failed to get call info: \(errorMessage)")
        }
        
        let callInfo = try JSONDecoder().decode(UltravoxCall.self, from: data)
        return callInfo
    }

    func endCall() async {
        await MainActor.run {
            self.callStatus = .ending
        }

        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil

        await MainActor.run {
            self.isConnected = false
            self.callStatus = .ended
            self.currentCall = nil
        }
    }

}

// MARK: - Data Models

struct TwilioCallStatus {
    let sid: String
    let status: String
    let endReason: String?
    let duration: String?
    let startTime: String?
    let endTime: String?
}

struct UltravoxCall: Codable {
    let callId: String
    let agentId: String?
    let status: String?
    let joinUrl: String?
    let created: String
    let ended: String?
    let metadata: [String: String]?

    // Computed property for compatibility with existing code
    var id: String { callId }

    enum CodingKeys: String, CodingKey {
        case callId
        case agentId
        case status
        case joinUrl
        case created
        case ended
        case metadata
    }
}

struct UltravoxAgentCallRequest: Codable {
    let agentId: String
    let templateContext: [String: String]
    let metadata: [String: String]
}

// Note: Telephony call structs removed - now using simple dictionary format that matches working curl API

struct UltravoxMessage: Codable, Identifiable {
    var id = UUID()
    let role: MessageRole
    let content: String
    let timestamp: Date

    enum MessageRole: String, Codable {
        case user
        case assistant
    }
}

struct UltravoxWebSocketMessage: Codable {
    let type: MessageType
    let transcript: TranscriptData?
    let callStatus: String?
    let error: ErrorData?

    enum MessageType: String, Codable {
        case transcript
        case callStatus = "call_status"
        case error
    }

    struct TranscriptData: Codable {
        let speaker: String
        let text: String
        let isFinal: Bool
    }

    struct ErrorData: Codable {
        let message: String
        let code: String?
    }
}

struct UltravoxSendMessage: Codable {
    let type: String
    let text: String
}

enum UltravoxCallStatus: Equatable {
    case idle
    case created
    case connecting
    case connected
    case active
    case ending
    case ended
    case error(String)

    init(from statusString: String) {
        switch statusString.lowercased() {
        case "created": self = .created
        case "connecting": self = .connecting
        case "connected": self = .connected
        case "active": self = .active
        case "ending": self = .ending
        case "ended": self = .ended
        default: self = .idle
        }
    }
}

enum UltravoxError: Error, LocalizedError {
    case missingConfiguration
    case apiError(String)
    case networkError(Error)
    case invalidJoinURL
    case notConnected
    case decodingError

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "Ultravox API key or agent ID not configured"
        case .apiError(let message):
            return "Ultravox API error: \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidJoinURL:
            return "Invalid join URL for Ultravox call"
        case .notConnected:
            return "Not connected to Ultravox call"
        case .decodingError:
            return "Failed to decode Ultravox response"
        }
    }
}

