//
//  WatchConnectivityService.swift
//  discreetly
//
//  Service for real-time communication with Apple Watch
//

import Foundation
import WatchConnectivity
import Combine
import UIKit

final class WatchConnectivityService: NSObject, ObservableObject {
    static let shared = WatchConnectivityService()

    @Published var isWatchConnected = false
    @Published var isWatchAppInstalled = false
    @Published var watchState: WatchState = .unknown
    @Published var lastWatchSensorData: [String: Any]?

    private var session: WCSession?
    private var cancellables = Set<AnyCancellable>()

    enum WatchState {
        case unknown
        case notPaired
        case paired
        case appNotInstalled
        case ready
    }

    private override init() {
        super.init()
        setupWatchConnectivity()
    }

    private func setupWatchConnectivity() {
        guard WCSession.isSupported() else {
            print("Watch Connectivity not supported")
            return
        }

        session = WCSession.default
        session?.delegate = self
        session?.activate()
    }

    /// Request real-time sensor data from Apple Watch
    func requestWatchSensorData() {
        guard let session = session,
              session.isReachable else {
            print("Watch not reachable")
            return
        }

        let message: [String: Any] = [
            "action": "requestSensorData",
            "timestamp": Date().timeIntervalSince1970
        ]

        session.sendMessage(message, replyHandler: { [weak self] reply in
            DispatchQueue.main.async {
                self?.lastWatchSensorData = reply
                print("Received watch sensor data: \(reply)")
            }
        }, errorHandler: { error in
            print("Failed to request watch sensor data: \(error)")
        })
    }

    /// Send emergency trigger to Apple Watch
    func triggerEmergencyOnWatch() {
        guard let session = session else { return }

        let message: [String: Any] = [
            "action": "emergencyTriggered",
            "timestamp": Date().timeIntervalSince1970
        ]

        if session.isReachable {
            session.sendMessage(message, replyHandler: nil, errorHandler: { error in
                print("Failed to send emergency trigger to watch: \(error)")
            })
        } else {
            // Use user info for background delivery
            session.transferUserInfo(message)
        }
    }

    /// Send system state update to Apple Watch
    func updateWatchSystemState(isEnabled: Bool) {
        guard let session = session else {
            print("❌ No WatchConnectivity session available")
            return
        }

        guard session.activationState == .activated else {
            print("❌ WatchConnectivity session not activated (state: \(session.activationState.rawValue))")
            return
        }

        guard session.isPaired else {
            print("❌ Apple Watch not paired")
            return
        }

        let applicationContext: [String: Any] = [
            "isSystemEnabled": isEnabled,
            "timestamp": Date().timeIntervalSince1970
        ]

        do {
            try session.updateApplicationContext(applicationContext)
            print("✅ Updated watch system state: \(isEnabled) - Paired: \(session.isPaired), App Installed: \(session.isWatchAppInstalled)")
        } catch {
            print("❌ Failed to update watch system state: \(error)")
        }
    }

    /// Start continuous sensor monitoring on Apple Watch
    func startWatchSensorMonitoring() {
        guard let session = session,
              session.isReachable else { return }

        let message = [
            "action": "startSensorMonitoring",
            "interval": 1.0 // 1 second intervals
        ] as [String : Any]

        session.sendMessage(message, replyHandler: { reply in
            print("Watch sensor monitoring started: \(reply)")
        }, errorHandler: { error in
            print("Failed to start watch sensor monitoring: \(error)")
        })
    }

    /// Stop continuous sensor monitoring on Apple Watch
    func stopWatchSensorMonitoring() {
        guard let session = session,
              session.isReachable else { return }

        let message = ["action": "stopSensorMonitoring"]

        session.sendMessage(message, replyHandler: { reply in
            print("Watch sensor monitoring stopped: \(reply)")
        }, errorHandler: { error in
            print("Failed to stop watch sensor monitoring: \(error)")
        })
    }

    /// Get current Apple Watch sensor data if available
    func getCurrentWatchSensorData() -> [String: Any]? {
        return lastWatchSensorData
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityService: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            switch activationState {
            case .activated:
                self.isWatchConnected = session.isPaired
                self.isWatchAppInstalled = session.isWatchAppInstalled

                if session.isPaired && session.isWatchAppInstalled {
                    self.watchState = .ready
                } else if session.isPaired {
                    self.watchState = .appNotInstalled
                } else {
                    self.watchState = .notPaired
                }

                print("Watch Connectivity activated - Paired: \(session.isPaired), App Installed: \(session.isWatchAppInstalled)")

            case .inactive:
                self.watchState = .unknown
                print("Watch Connectivity inactive")

            case .notActivated:
                self.watchState = .unknown
                print("Watch Connectivity not activated")

            @unknown default:
                self.watchState = .unknown
                print("Watch Connectivity unknown state")
            }
        }

        if let error = error {
            print("Watch Connectivity activation error: \(error)")
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        DispatchQueue.main.async {
            self.watchState = .unknown
            self.isWatchConnected = false
        }
        print("Watch session became inactive")
    }

    func sessionDidDeactivate(_ session: WCSession) {
        DispatchQueue.main.async {
            self.watchState = .unknown
            self.isWatchConnected = false
        }
        print("Watch session deactivated")

        // Reactivate the session
        session.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isWatchConnected = session.isPaired
            self.isWatchAppInstalled = session.isWatchAppInstalled

            if session.isPaired && session.isWatchAppInstalled {
                self.watchState = .ready
            } else if session.isPaired {
                self.watchState = .appNotInstalled
            } else {
                self.watchState = .notPaired
            }
        }
        print("Watch state changed - Paired: \(session.isPaired), App Installed: \(session.isWatchAppInstalled)")
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        print("Received message from watch: \(message)")

        // Handle different message types from watch
        if let action = message["action"] as? String {
            switch action {
            case "sensorData":
                DispatchQueue.main.async {
                    self.lastWatchSensorData = message
                }
            case "emergencyDetected":
                // Handle emergency detected on watch
                print("Emergency detected on Apple Watch!")
                // Trigger emergency response

            case "heartRateAlert":
                // Handle heart rate alerts
                if let heartRate = message["heartRate"] as? Double {
                    print("Heart rate alert from watch: \(heartRate) BPM")
                }

            default:
                print("Unknown action from watch: \(action)")
            }
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        print("Received message from watch with reply handler: \(message)")

        // Handle messages that expect a reply
        if let action = message["action"] as? String {
            switch action {
            case "requestPhoneStatus":
                let reply: [String : Any] = [
                    "batteryLevel": UIDevice.current.batteryLevel,
                    "timestamp": Date().timeIntervalSince1970
                ]
                replyHandler(reply)

            case "triggerSOS":
                // Handle SOS trigger from watch
                print("🆘 SOS triggered from Apple Watch!")
                DispatchQueue.main.async {
                    // Trigger the currently enabled action via ActionMapper
                    ActionMapper.shared.manualTrigger()
                }

                let reply: [String : Any] = [
                    "status": "sos_triggered",
                    "timestamp": Date().timeIntervalSince1970
                ]
                replyHandler(reply)

            case "requestSystemState":
                // Send current system state to watch
                let isSystemEnabled = !SettingsManager.shared.getEnabledActions().isEmpty
                let reply: [String : Any] = [
                    "isSystemEnabled": isSystemEnabled,
                    "timestamp": Date().timeIntervalSince1970
                ]
                replyHandler(reply)
                print("📱 Sent system state to watch: \(isSystemEnabled)")

            default:
                replyHandler(["status": "unknown_action"])
            }
        } else {
            replyHandler(["status": "no_action"])
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any]) {
        print("Received user info from watch: \(userInfo)")

        DispatchQueue.main.async {
            // Handle background user info transfers
            if let action = userInfo["action"] as? String, action == "sensorData" {
                self.lastWatchSensorData = userInfo
            }
        }
    }

    func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        if let error = error {
            print("User info transfer error: \(error)")
        } else {
            print("User info transfer completed successfully")
        }
    }
}

// MARK: - Watch Sensor Data Structure

struct WatchSensorData {
    let heartRate: Double?
    let accelerometerData: [String: Double]?
    let gyroscopeData: [String: Double]?
    let crownRotation: Double?
    let isWornOnWrist: Bool
    let workoutState: String?
    let timestamp: Date

    init(from dictionary: [String: Any]) {
        self.heartRate = dictionary["heartRate"] as? Double
        self.accelerometerData = dictionary["accelerometer"] as? [String: Double]
        self.gyroscopeData = dictionary["gyroscope"] as? [String: Double]
        self.crownRotation = dictionary["crownRotation"] as? Double
        self.isWornOnWrist = dictionary["isWornOnWrist"] as? Bool ?? false
        self.workoutState = dictionary["workoutState"] as? String

        if let timestampInterval = dictionary["timestamp"] as? TimeInterval {
            self.timestamp = Date(timeIntervalSince1970: timestampInterval)
        } else {
            self.timestamp = Date()
        }
    }
}

extension WatchConnectivityService {
    var currentWatchSensorData: WatchSensorData? {
        guard let data = lastWatchSensorData else { return nil }
        return WatchSensorData(from: data)
    }

    var watchStatusString: String {
        switch watchState {
        case .unknown:
            return "Unknown"
        case .notPaired:
            return "Apple Watch not paired"
        case .paired:
            return "Apple Watch paired"
        case .appNotInstalled:
            return "App not installed on watch"
        case .ready:
            return "Ready - Watch app available"
        }
    }
}