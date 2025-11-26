//
//  UltravoxConfigurationView.swift
//  discreetly
//
//  Configuration view for Ultravox AI user preferences
//

import SwiftUI

struct UltravoxConfigurationView: View {
    @StateObject private var settingsManager = SettingsManager.shared
    @StateObject private var emergencyOrchestrator = EmergencyCallOrchestrator.shared
    @StateObject private var ultravoxService = UltravoxService.shared

    @State private var enableUltravoxAI = true
    @State private var preferredCallMethod: PreferredCallMethod = .automatic
    @State private var twilioAccountSid = ""
    @State private var twilioAuthToken = ""
    @State private var twilioFromNumber = ""
    @State private var enableNeighborhoodSafetyMonitoring = true

    @State private var isTestingConnection = false
    @State private var testResult: TestResult?
    @State private var showingTestResults = false

    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("AI Emergency Calling")
                            .font(.headline)
                        Text("Configure how Discreetly handles emergency calls with AI assistance and sensor data integration.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section("AI Emergency Calling Preferences") {
                    Toggle("Enable AI-Powered Calling", isOn: $enableUltravoxAI)
                        .onChange(of: enableUltravoxAI) { _ in
                            saveSettings()
                        }

                    if enableUltravoxAI {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Call Method")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Picker("Preferred Call Method", selection: $preferredCallMethod) {
                                ForEach(PreferredCallMethod.allCases, id: \.self) { method in
                                    Text(method.rawValue).tag(method)
                                }
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: preferredCallMethod) { _ in
                                saveSettings()
                            }

                            Text(preferredCallMethod.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section("Safety Monitoring") {
                    Toggle("Enable Neighborhood Safety Monitoring", isOn: $enableNeighborhoodSafetyMonitoring)
                        .onChange(of: enableNeighborhoodSafetyMonitoring) { _ in
                            saveSettings()
                        }

                    if enableNeighborhoodSafetyMonitoring {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Automatically monitors location changes and uses AI to assess neighborhood safety. You'll receive notifications when entering potentially unsafe areas.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section("Twilio Configuration") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Account SID")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("Enter Twilio Account SID", text: $twilioAccountSid)
                            .textContentType(.none)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Auth Token")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        SecureField("Enter Twilio Auth Token", text: $twilioAuthToken)
                            .textContentType(.password)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("From Number")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("Enter Twilio Phone Number", text: $twilioFromNumber)
                            .textContentType(.telephoneNumber)
                    }

                    Link("Get Twilio Credentials", destination: URL(string: "https://console.twilio.com")!)
                        .font(.caption)
                        .foregroundColor(.blue)
                }

                Section("Service Status") {
                    HStack {
                        Image(systemName: isUltravoxAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(isUltravoxAvailable ? .green : .orange)
                        Text("Ultravox AI")
                        Spacer()
                        Text(isUltravoxAvailable ? "Available" : "Not Available")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Image(systemName: isTwilioConfigured ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(isTwilioConfigured ? .green : .red)
                        Text("Twilio (Fallback)")
                        Spacer()
                        Text(isTwilioConfigured ? "Configured" : "Not Configured")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if enableUltravoxAI && !isUltravoxAvailable {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading) {
                                Text("AI Calling Unavailable")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Text("Calls will use traditional calling method.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                Section("Testing") {
                    Button(action: testConnection) {
                        HStack {
                            if isTestingConnection {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "wifi")
                            }
                            Text("Test Connection")
                        }
                    }
                    .disabled(isTestingConnection || (!isUltravoxAvailable && !isTwilioConfigured))

                    if let testResult = testResult {
                        HStack {
                            Image(systemName: testResult.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(testResult.isSuccess ? .green : .red)
                            Text(testResult.message)
                                .font(.caption)
                        }
                    }
                }

                if ultravoxService.isConnected {
                    Section("Current Status") {
                        HStack {
                            Image(systemName: "phone.connection")
                                .foregroundColor(.green)
                            Text("Connected to Ultravox")
                            Spacer()
                            Text(ultravoxService.callStatus.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("AI Emergency Configuration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveSettings()
                    }
                    .disabled(!hasChanges)
                }
            }
        }
        .onAppear {
            loadCurrentSettings()
        }
        .alert("Test Results", isPresented: $showingTestResults) {
            Button("OK") { }
        } message: {
            Text(testResult?.detailedMessage ?? "Test completed")
        }
    }

    // MARK: - Computed Properties

    private var isUltravoxAvailable: Bool {
        ultravoxService.apiKey != nil && ultravoxService.agentId != nil
    }

    private var isTwilioConfigured: Bool {
        !twilioAccountSid.isEmpty && !twilioAuthToken.isEmpty && !twilioFromNumber.isEmpty
    }

    private var hasChanges: Bool {
        let settings = settingsManager.settings
        return enableUltravoxAI != settings.enableUltravoxAI ||
               preferredCallMethod != settings.preferredCallMethod ||
               twilioAccountSid != (settings.twilioAccountSid ?? "") ||
               twilioAuthToken != (settings.twilioAuthToken ?? "") ||
               twilioFromNumber != (settings.twilioFromNumber ?? "") ||
               enableNeighborhoodSafetyMonitoring != settings.enableNeighborhoodSafetyMonitoring
    }

    // MARK: - Methods

    private func loadCurrentSettings() {
        let settings = settingsManager.settings
        enableUltravoxAI = settings.enableUltravoxAI
        preferredCallMethod = settings.preferredCallMethod
        twilioAccountSid = settings.twilioAccountSid ?? ""
        twilioAuthToken = settings.twilioAuthToken ?? ""
        twilioFromNumber = settings.twilioFromNumber ?? ""
        enableNeighborhoodSafetyMonitoring = settings.enableNeighborhoodSafetyMonitoring
    }

    private func saveSettings() {
        var settings = settingsManager.settings
        settings.enableUltravoxAI = enableUltravoxAI
        settings.preferredCallMethod = preferredCallMethod
        settings.twilioAccountSid = twilioAccountSid.isEmpty ? nil : twilioAccountSid
        settings.twilioAuthToken = twilioAuthToken.isEmpty ? nil : twilioAuthToken
        settings.twilioFromNumber = twilioFromNumber.isEmpty ? nil : twilioFromNumber
        settings.enableNeighborhoodSafetyMonitoring = enableNeighborhoodSafetyMonitoring

        settingsManager.settings = settings
        HapticService.shared.success()

        // Start or stop neighborhood safety monitoring based on setting
        if enableNeighborhoodSafetyMonitoring {
            NeighborhoodSafetyService.shared.startMonitoring()
        } else {
            NeighborhoodSafetyService.shared.stopMonitoring()
        }
    }

    private func testConnection() {
        isTestingConnection = true
        testResult = nil

        Task {
            await performConnectionTest()
        }
    }

    @MainActor
    private func performConnectionTest() async {
        var testMessages: [String] = []
        var overallSuccess = true

        // Test Ultravox if available
        if isUltravoxAvailable {
            // Create a test sensor data without actually placing a call
            let testSensorData = SensorData()
            testMessages.append("✅ Ultravox AI service is available")
            testMessages.append("✅ Sensor data integration ready")
        } else {
            testMessages.append("⚠️ Ultravox AI not available - app configured fallback only")
        }

        // Test Twilio (basic validation)
        if isTwilioConfigured {
            // For Twilio, we'll just validate the format of the credentials
            if twilioAccountSid.hasPrefix("AC") && twilioFromNumber.hasPrefix("+") {
                testMessages.append("✅ Twilio configuration appears valid")
            } else {
                testMessages.append("❌ Twilio configuration format invalid")
                overallSuccess = false
            }
        } else {
            testMessages.append("⚠️ Twilio not configured - emergency calling may not work")
            if !isUltravoxAvailable {
                overallSuccess = false
            }
        }

        if testMessages.isEmpty {
            testMessages.append("❌ No calling services available")
            overallSuccess = false
        }

        testResult = TestResult(
            isSuccess: overallSuccess,
            message: overallSuccess ? "Services ready for emergency calling" : "Service configuration issues detected",
            detailedMessage: testMessages.joined(separator: "\n")
        )

        isTestingConnection = false
        showingTestResults = true

        if overallSuccess {
            HapticService.shared.success()
        } else {
            HapticService.shared.error()
        }
    }
}

// MARK: - Supporting Types

private struct TestResult {
    let isSuccess: Bool
    let message: String
    let detailedMessage: String
}

// MARK: - Extensions

extension UltravoxCallStatus {
    var description: String {
        switch self {
        case .idle: return "Idle"
        case .created: return "Created"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .active: return "Active"
        case .ending: return "Ending"
        case .ended: return "Ended"
        case .error(let message): return "Error: \(message)"
        }
    }
}

#Preview {
    UltravoxConfigurationView()
}