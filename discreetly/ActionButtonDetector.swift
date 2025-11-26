import UIKit
import Combine

final class ActionButtonDetector: ObservableObject {
    var onActionButtonPressed: (() -> Void)?

    private var isMonitoring = false
    private var lastTriggerTime: Date?
    private let minimumTimeBetweenTriggers: TimeInterval = 2.0 // 2 seconds

    func start() {
        stop()
        isMonitoring = true
        lastTriggerTime = nil

        // Listen for the App Intent notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEmergencyActionIntent),
            name: .emergencyActionTriggered,
            object: nil
        )

        print("🎯 Action Button monitoring started (App Intent method)")
    }

    func stop() {
        NotificationCenter.default.removeObserver(self)
        isMonitoring = false
        print("🛑 Action Button monitoring stopped")
    }

    deinit {
        stop()
    }

    @objc private func handleEmergencyActionIntent() {
        guard isMonitoring && shouldTriggerAction() else { return }
        
        print("⚡ Action Intent received!")
        triggerActionButtonEvent()
    }

    private func shouldTriggerAction() -> Bool {
        let now = Date()

        // Check if enough time has passed since last trigger
        if let lastTrigger = lastTriggerTime,
           now.timeIntervalSince(lastTrigger) < minimumTimeBetweenTriggers {
            return false
        }

        return true
    }

    private func triggerActionButtonEvent() {
        guard isMonitoring && shouldTriggerAction() else { return }

        lastTriggerTime = Date()
        print("⚡ Action Button pressed via App Intent!")

        DispatchQueue.main.async {
            // Haptic feedback for button press
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            // Execute the action
            self.onActionButtonPressed?()
        }
    }

    /// Manually trigger an action button event (for testing or manual activation)
    func manualTrigger() {
        print("🔘 Manual Action Button trigger")
        lastTriggerTime = Date()

        DispatchQueue.main.async {
            // Haptic feedback for button press
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            // Execute the action
            self.onActionButtonPressed?()
        }
    }
}

// MARK: - Action Button Configuration Helper
extension ActionButtonDetector {
    /// Check if device supports Action Button
    static var isActionButtonSupported: Bool {
        // Action Button is available on iPhone 15 Pro and later
        let deviceModel = UIDevice.current.userInterfaceIdiom
        return deviceModel == .phone && ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 17
    }

    /// Instructions for setting up Action Button
    static var setupInstructions: String {
        return """
        To use the Action Button with discreetly:

        1. Open Settings app
        2. Go to Action Button
        3. Select "Shortcut"
        4. Choose "Action" (from discreetly)
        5. Press Action Button to test

        The Action Button will now trigger actions directly!
        """
    }
}
