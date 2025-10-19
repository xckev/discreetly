import Foundation
import TwilioVoice
import AVFoundation
import Combine

enum TwilioServiceError: Error, LocalizedError {
    case missingCredentials
    case invalidURL
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Twilio Account SID and Auth Token are required"
        case .invalidURL:
            return "Invalid Twilio API URL"
        case .apiError(let message):
            return "Twilio API Error: \(message)"
        }
    }
}

final class TwilioService: NSObject, ObservableObject {
    static let shared = TwilioService()

    @Published var isCallInProgress = false
    @Published var callStatus: String = "Ready"

    private var accessToken: String?
    private var activeCall: Call?
    private var audioDevice = DefaultAudioDevice()

    // Backend server URL - configurable based on environment
    private var backendURL: String {
//        #if DEBUG
        return "https://discreetly-backend.onrender.com" // Development server
//        #else
//        return "https://your-production-server.com" // Production server
//        #endif
    }

    override init() {
        super.init()

        // Setup TwilioVoice
        TwilioVoiceSDK.audioDevice = audioDevice

        // Setup audio session
        setupAudioSession()
    }

    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetoothA2DP, .defaultToSpeaker])
        } catch {
            print("❌ Failed to setup audio session: \(error)")
        }
    }

    private func activateAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setActive(true)
            audioDevice.isEnabled = true
            print("✅ Audio session activated")
        } catch {
            print("❌ Failed to activate audio session: \(error)")
        }
    }

    private func deactivateAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            audioDevice.isEnabled = false
            try audioSession.setActive(false)
            print("✅ Audio session deactivated")
        } catch {
            print("❌ Failed to deactivate audio session: \(error)")
        }
    }

    /// Fetch access token from backend server
    private func fetchAccessToken() async throws -> String {
        guard let url = URL(string: "\(backendURL)/token") else {
            throw TwilioError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw TwilioError.tokenFetchFailed
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        print("✅ Got Twilio access token for identity: \(tokenResponse.identity)")
        return tokenResponse.token
    }

    /// Make an emergency call to the specified phone number
    func makeCovertCall(to phoneNumber: String) async {
        do {
            print("📞 Initiating covert call to \(phoneNumber)")

            // Fetch fresh access token
            let token = try await fetchAccessToken()
            self.accessToken = token

            // Prepare call parameters
            let connectOptions = ConnectOptions(accessToken: token) { builder in
                builder.params = ["To": phoneNumber]
            }

            // Make the call
            DispatchQueue.main.async {
                self.isCallInProgress = true
                self.callStatus = "Connecting..."

                // Activate audio session before making call
                self.activateAudioSession()

                // Add haptic feedback for call initiation
                HapticService.shared.threeVibrations()

                self.activeCall = TwilioVoiceSDK.connect(options: connectOptions, delegate: self)
            }

        } catch {
            print("❌ Failed to make covert call: \(error)")
            DispatchQueue.main.async {
                self.callStatus = "Covert call failed: \(error.localizedDescription)"
                self.isCallInProgress = false
            }
        }
    }

    // MARK: - Manual Twilio Integration (for Ultravox)

    func makeOutboundCallWithTwiML(
        to phoneNumber: String,
        from fromNumber: String,
        twiml: String
    ) async throws -> String {
        print("📞 Making Twilio outbound call with TwiML")
        print("   To: \(phoneNumber)")
        print("   From: \(fromNumber)")

        // Get Twilio credentials from SettingsManager
        guard let accountSid = SettingsManager.shared.settings.twilioAccountSid,
              let authToken = SettingsManager.shared.settings.twilioAuthToken else {
            print("❌ Twilio credentials not configured")
            print("💡 Configure Twilio Account SID and Auth Token in Settings")
            throw TwilioServiceError.missingCredentials
        }

        print("🔑 Using Twilio Account SID: \(String(accountSid.prefix(10)))...")

        // Create Twilio REST API call
        let twilioUrl = "https://api.twilio.com/2010-04-01/Accounts/\(accountSid)/Calls.json"

        guard let url = URL(string: twilioUrl) else {
            throw TwilioServiceError.invalidURL
        }

        var request = URLRequest(url: url)
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
            "Twiml=\(twiml.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        ].joined(separator: "&")

        request.httpBody = bodyParams.data(using: .utf8)

        print("🌐 Making Twilio REST API call...")
        print("   URL: \(twilioUrl)")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw TwilioServiceError.apiError("Invalid response from Twilio API")
            }
            
            print("📡 Twilio API Response Status: \(httpResponse.statusCode)")

            if let responseBody = String(data: data, encoding: .utf8) {
                print("📡 Twilio API Response Body:")
                print(responseBody)
            }

            if httpResponse.statusCode == 201 {
                print("✅ Twilio call initiated successfully!")

                // Parse the response to get the Call SID
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let callSid = json["sid"] as? String else {
                    throw TwilioServiceError.apiError("Failed to parse Call SID from Twilio response")
                }

                print("📞 Twilio Call SID: \(callSid)")

                DispatchQueue.main.async {
                    self.isCallInProgress = true
                    self.callStatus = "Twilio call initiated with Ultravox"

                    // Add haptic feedback for call initiation
                    HapticService.shared.threeVibrations()
                }

                return callSid
            } else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("❌ Twilio API call failed: \(httpResponse.statusCode)")
                throw TwilioServiceError.apiError("Twilio API failed: \(errorMessage)")
            }
        } catch {
            print("❌ Twilio REST API call failed: \(error)")
            throw error
        }
    }

    /// Hang up the current call
    func hangUp() {
        guard let call = activeCall else { return }

        call.disconnect()
        activeCall = nil
        isCallInProgress = false
        callStatus = "Call ended"

        // Deactivate audio session
        deactivateAudioSession()

        print("📞 Call ended")
    }

}

// MARK: - TwilioVoice Call Delegate
extension TwilioService: CallDelegate {
    func callDidStartRinging(call: Call) {
        print("📞 Call is ringing...")
        DispatchQueue.main.async {
            self.callStatus = "Ringing..."
        }
    }

    func callDidConnect(call: Call) {
        print("✅ Call connected!")
        DispatchQueue.main.async {
            self.callStatus = "Connected"
            self.isCallInProgress = true
        }
    }

    func callDidFailToConnect(call: Call, error: Error) {
        print("❌ Call failed to connect: \(error)")
        DispatchQueue.main.async {
            self.callStatus = "Failed: \(error.localizedDescription)"
            self.isCallInProgress = false
        }
        activeCall = nil
    }

    func callDidDisconnect(call: Call, error: Error?) {
        if let error = error {
            print("📞 Call disconnected with error: \(error)")
        } else {
            print("📞 Call disconnected")
        }

        DispatchQueue.main.async {
            self.callStatus = error != nil ? "Disconnected: \(error!.localizedDescription)" : "Disconnected"
            self.isCallInProgress = false
        }
        activeCall = nil

        // Deactivate audio session when call ends
        deactivateAudioSession()
    }
}


// MARK: - Supporting Types
struct TokenResponse: Codable {
    let identity: String
    let token: String
    let expires_in: Int
}

enum TwilioError: Error, LocalizedError {
    case invalidURL
    case tokenFetchFailed
    case noActiveCall

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid backend URL"
        case .tokenFetchFailed:
            return "Failed to fetch access token from server"
        case .noActiveCall:
            return "No active call to disconnect"
        }
    }
}
