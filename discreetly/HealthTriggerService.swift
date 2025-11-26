//
//  HealthTriggerService.swift
//  discreetly
//
//  Service for monitoring health metrics and triggering actions
//

import Foundation
import Combine
import UIKit

final class HealthTriggerService: ObservableObject {
    static let shared = HealthTriggerService()

    @Published var isMonitoring = false
    @Published var lastTriggerTime: Date?

    private var cancellables = Set<AnyCancellable>()
    private var healthKitService = HealthKitService.shared
    private var monitoringTimer: Timer?
    private let monitoringInterval: TimeInterval = 30.0 // Check every 30 seconds

    var onHealthTriggerActivated: ((TriggerType, Double, String) -> Void)?

    private init() {}

    func startMonitoring(for actions: [ActionConfig]) {
        guard !isMonitoring else { return }

        print("🫀 Health trigger monitoring started")
        isMonitoring = true

        // Start periodic health data collection
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: monitoringInterval, repeats: true) { [weak self] _ in
            self?.checkHealthTriggers(for: actions)
        }
    }

    func stopMonitoring() {
        guard isMonitoring else { return }

        print("🛑 Health trigger monitoring stopped")
        isMonitoring = false
        monitoringTimer?.invalidate()
        monitoringTimer = nil
    }

    private func checkHealthTriggers(for actions: [ActionConfig]) {
        Task {
            let healthData = await healthKitService.collectHealthData()

            await MainActor.run {
                for action in actions where action.isEnabled {
                    switch action.triggerType {
                    case .respiratoryRate:
                        checkRespiratoryRateTrigger(action: action, healthData: healthData)
                    case .heartRateVariability:
                        checkHRVTrigger(action: action, healthData: healthData)
                    default:
                        break
                    }
                }
            }
        }
    }

    private func checkRespiratoryRateTrigger(action: ActionConfig, healthData: HealthData) {
        guard let currentRate = healthData.respiratoryRate,
              let threshold = action.respiratoryRateThreshold,
              let healthOperator = action.respiratoryRateOperator else { return }

        let shouldTrigger = evaluateCondition(
            value: currentRate,
            threshold: threshold,
            operator: healthOperator
        )

        if shouldTrigger {
            let message = "Respiratory rate: \(Int(currentRate)) BPM (\(healthOperator.rawValue) \(Int(threshold)))"
            triggerAction(type: .respiratoryRate, value: currentRate, description: message)
        }
    }

    private func checkHRVTrigger(action: ActionConfig, healthData: HealthData) {
        guard let currentHRV = healthData.heartRateVariability,
              let threshold = action.hrvThreshold,
              let healthOperator = action.hrvOperator else { return }

        let shouldTrigger = evaluateCondition(
            value: currentHRV,
            threshold: threshold,
            operator: healthOperator
        )

        if shouldTrigger {
            let message = "Heart Rate Variability: \(String(format: "%.1f", currentHRV)) ms (\(healthOperator.rawValue) \(String(format: "%.1f", threshold)))"
            triggerAction(type: .heartRateVariability, value: currentHRV, description: message)
        }
    }

    private func evaluateCondition(value: Double, threshold: Double, operator healthOperator: HealthOperator) -> Bool {
        switch healthOperator {
        case .greaterThan:
            return value > threshold
        case .lessThan:
            return value < threshold
        case .greaterThanOrEqual:
            return value >= threshold
        case .lessThanOrEqual:
            return value <= threshold
        case .equals:
            return abs(value - threshold) < 0.1 // Allow small tolerance for doubles
        }
    }

    private func triggerAction(type: TriggerType, value: Double, description: String) {
        // Prevent triggering too frequently
        if let lastTrigger = lastTriggerTime,
           Date().timeIntervalSince(lastTrigger) < 60.0 { // 1 minute cooldown
            return
        }

        lastTriggerTime = Date()

        print("🚨 Health trigger activated: \(description)")

        DispatchQueue.main.async {
            // Haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.warning)

            // Execute the trigger callback
            self.onHealthTriggerActivated?(type, value, description)
        }
    }
}

// MARK: - Health Trigger Configuration Helper
extension HealthTriggerService {

    /// Get suggested respiratory rate thresholds
    static func getRespiratoryRateThresholds() -> [(String, Double)] {
        return [
            ("Very Low (< 8 BPM)", 8.0),
            ("Low (< 12 BPM)", 12.0),
            ("High (> 20 BPM)", 20.0),
            ("Very High (> 24 BPM)", 24.0)
        ]
    }

    /// Get suggested HRV thresholds
    static func getHRVThresholds() -> [(String, Double)] {
        return [
            ("Very Low (< 20 ms)", 20.0),
            ("Low (< 30 ms)", 30.0),
            ("High (> 60 ms)", 60.0),
            ("Very High (> 80 ms)", 80.0)
        ]
    }

    /// Get explanation for respiratory rate triggers
    static var respiratoryRateExplanation: String {
        return """
        Normal respiratory rate for adults is 12-20 breaths per minute.

        • Low rates (< 12 BPM) may indicate:
          - Medication effects
          - Respiratory depression
          - Medical emergency

        • High rates (> 20 BPM) may indicate:
          - Anxiety or panic
          - Physical exertion
          - Respiratory distress
          - Medical emergency
        """
    }

    /// Get explanation for HRV triggers
    static var hrvExplanation: String {
        return """
        Heart Rate Variability measures the variation in time between heartbeats.

        • Low HRV (< 30 ms) may indicate:
          - High stress levels
          - Poor recovery
          - Overtraining
          - Health issues

        • High HRV (> 60 ms) usually indicates:
          - Good autonomic balance
          - Better stress resilience
          - Good cardiovascular health
        """
    }
}