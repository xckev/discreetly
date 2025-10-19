//
//  SensorDataService.swift
//  discreetly
//
//  Service for collecting all sensor data when action is triggered
//

import Foundation
import CoreMotion
import CoreLocation
import AVFoundation
import Contacts
import UIKit
import Combine
import HealthKit

struct SensorData {
    // Location
    var location: CLLocation?
    var locationAccuracy: String?
    var altitude: Double?

    // Motion
    var accelerometerData: CMAccelerometerData?
    var gyroscopeData: CMGyroData?
    var magnetometerData: CMMagnetometerData?
    var deviceMotion: CMDeviceMotion?

    // Device
    var batteryLevel: Int
    var batteryState: String
    var deviceOrientation: String
    var timestamp: Date

    // Audio
    var audioSessionActive: Bool
    var audioInputAvailable: Bool
    var microphonePermission: String

    // Camera
    var cameraPermission: String
    var frontCameraAvailable: Bool
    var backCameraAvailable: Bool

    // Contacts
    var contactsPermission: String
    var emergencyContactsCount: Int

    // Network
    var networkStatus: String
    var cellularSignalStrength: String?

    // Apple Watch Health Data
    var healthData: HealthData?

    init() {
        self.timestamp = Date()
        self.batteryLevel = 0
        self.batteryState = "Unknown"
        self.deviceOrientation = "Unknown"
        self.audioSessionActive = false
        self.audioInputAvailable = false
        self.microphonePermission = "Unknown"
        self.cameraPermission = "Unknown"
        self.frontCameraAvailable = false
        self.backCameraAvailable = false
        self.contactsPermission = "Unknown"
        self.emergencyContactsCount = 0
        self.networkStatus = "Unknown"
    }
}

final class SensorDataService: ObservableObject {
    static let shared = SensorDataService()

    @Published var currentSensorData = SensorData()
    @Published var isCollecting = false

    private let motionManager = CMMotionManager()
    private let locationService = LocationService.shared
    private let healthKitService = HealthKitService.shared
    private let backgroundMonitor = BackgroundSensorMonitor.shared

    private init() {
        setupMotionManager()
    }

    private func setupMotionManager() {
        motionManager.accelerometerUpdateInterval = 0.1
        motionManager.gyroUpdateInterval = 0.1
        motionManager.magnetometerUpdateInterval = 0.1
        motionManager.deviceMotionUpdateInterval = 0.1
    }

    /// Collect all available sensor data - uses cached background data for instant response
    func collectAllSensorData() async -> SensorData {
        isCollecting = true

        // First, try to get fresh cached data from background monitor
        let cachedData = backgroundMonitor.getCurrentSensorData()

        // If background data is fresh (less than 5 seconds old), use it immediately
        if backgroundMonitor.isDataFresh {
            print("📱 Using fresh cached sensor data (age: \(String(format: "%.1f", backgroundMonitor.dataAge))s)")
            await MainActor.run {
                self.currentSensorData = cachedData
                self.isCollecting = false
            }
            return cachedData
        }

        // If cached data is stale, refresh it in background monitor
        print("📱 Refreshing stale sensor data (age: \(String(format: "%.1f", backgroundMonitor.dataAge))s)")
        let refreshedData = await backgroundMonitor.refreshSensorData()

        await MainActor.run {
            self.currentSensorData = refreshedData
            self.isCollecting = false
        }

        return refreshedData
    }

    /// Fallback method for comprehensive sensor collection when background monitor is unavailable
    func collectAllSensorDataDirect() async -> SensorData {
        isCollecting = true
        var sensorData = SensorData()

        // Collect data from all sensors concurrently
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.collectLocationData(&sensorData) }
            group.addTask { await self.collectMotionData(&sensorData) }
            group.addTask { await self.collectDeviceData(&sensorData) }
            group.addTask { await self.collectAudioData(&sensorData) }
            group.addTask { await self.collectCameraData(&sensorData) }
            group.addTask { await self.collectContactsData(&sensorData) }
            group.addTask { await self.collectNetworkData(&sensorData) }
            group.addTask { await self.collectHealthData(&sensorData) }
        }

        await MainActor.run {
            self.currentSensorData = sensorData
            self.isCollecting = false
        }

        return sensorData
    }

    /// Get instantly available sensor data without any collection delays
    func getInstantSensorData() -> SensorData {
        return backgroundMonitor.getCurrentSensorData()
    }

    private func collectLocationData(_ sensorData: inout SensorData) async {
        do {
            let location = try await locationService.getCurrentLocation()
            sensorData.location = location
            sensorData.locationAccuracy = String(format: "±%.0fm", location.horizontalAccuracy)
            sensorData.altitude = location.altitude
        } catch {
            print("Failed to get location: \(error)")
        }
    }

    private func collectMotionData(_ sensorData: inout SensorData) async {
        // Start motion updates briefly to get current data
        if motionManager.isAccelerometerAvailable {
            motionManager.startAccelerometerUpdates()
            sensorData.accelerometerData = motionManager.accelerometerData
        }

        if motionManager.isGyroAvailable {
            motionManager.startGyroUpdates()
            sensorData.gyroscopeData = motionManager.gyroData
        }

        if motionManager.isMagnetometerAvailable {
            motionManager.startMagnetometerUpdates()
            sensorData.magnetometerData = motionManager.magnetometerData
        }

        if motionManager.isDeviceMotionAvailable {
            motionManager.startDeviceMotionUpdates()
            sensorData.deviceMotion = motionManager.deviceMotion
        }

        // Wait a moment for data to be collected
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // Stop updates
        motionManager.stopAccelerometerUpdates()
        motionManager.stopGyroUpdates()
        motionManager.stopMagnetometerUpdates()
        motionManager.stopDeviceMotionUpdates()
    }

    private func collectDeviceData(_ sensorData: inout SensorData) async {
        await MainActor.run {
            UIDevice.current.isBatteryMonitoringEnabled = true
            sensorData.batteryLevel = Int(UIDevice.current.batteryLevel * 100)

            switch UIDevice.current.batteryState {
            case .unplugged: sensorData.batteryState = "Unplugged"
            case .charging: sensorData.batteryState = "Charging"
            case .full: sensorData.batteryState = "Full"
            default: sensorData.batteryState = "Unknown"
            }

            switch UIDevice.current.orientation {
            case .portrait: sensorData.deviceOrientation = "Portrait"
            case .portraitUpsideDown: sensorData.deviceOrientation = "Portrait Upside Down"
            case .landscapeLeft: sensorData.deviceOrientation = "Landscape Left"
            case .landscapeRight: sensorData.deviceOrientation = "Landscape Right"
            case .faceUp: sensorData.deviceOrientation = "Face Up"
            case .faceDown: sensorData.deviceOrientation = "Face Down"
            default: sensorData.deviceOrientation = "Unknown"
            }
        }
    }

    private func collectAudioData(_ sensorData: inout SensorData) async {
        let audioSession = AVAudioSession.sharedInstance()

        sensorData.audioSessionActive = audioSession.isOtherAudioPlaying == false
        sensorData.audioInputAvailable = !(audioSession.availableInputs?.isEmpty ?? true)

        // Check microphone permission using AVAudioApplication (iOS 17+)
        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted: sensorData.microphonePermission = "Granted"
            case .denied: sensorData.microphonePermission = "Denied"
            case .undetermined: sensorData.microphonePermission = "Not Requested"
            @unknown default: sensorData.microphonePermission = "Unknown"
            }
        } else {
            switch AVAudioSession.sharedInstance().recordPermission {
            case .granted: sensorData.microphonePermission = "Granted"
            case .denied: sensorData.microphonePermission = "Denied"
            case .undetermined: sensorData.microphonePermission = "Not Requested"
            @unknown default: sensorData.microphonePermission = "Unknown"
            }
        }
    }

    private func collectCameraData(_ sensorData: inout SensorData) async {
        // Check camera permission
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: sensorData.cameraPermission = "Granted"
        case .denied: sensorData.cameraPermission = "Denied"
        case .restricted: sensorData.cameraPermission = "Restricted"
        case .notDetermined: sensorData.cameraPermission = "Not Requested"
        @unknown default: sensorData.cameraPermission = "Unknown"
        }

        // Check camera availability
        sensorData.frontCameraAvailable = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil
        sensorData.backCameraAvailable = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    private func collectContactsData(_ sensorData: inout SensorData) async {
        // Check contacts permission
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized: sensorData.contactsPermission = "Granted"
        case .denied: sensorData.contactsPermission = "Denied"
        case .restricted: sensorData.contactsPermission = "Restricted"
        case .notDetermined: sensorData.contactsPermission = "Not Requested"
        case .limited: sensorData.contactsPermission = "Limited"
        @unknown default: sensorData.contactsPermission = "Unknown"
        }

        // Count emergency contacts from settings
        sensorData.emergencyContactsCount = SettingsManager.shared.settings.contacts.count
    }

    private func collectNetworkData(_ sensorData: inout SensorData) async {
        // Basic network connectivity check
        // In a full implementation, you might use Network framework
        sensorData.networkStatus = "Connected" // Simplified
        sensorData.cellularSignalStrength = "Good" // Simplified - would need private APIs for actual signal
    }

    private func collectHealthData(_ sensorData: inout SensorData) async {
        // Only collect health data if HealthKit is available and authorized
        if healthKitService.healthKitAvailable {
            print("📱 HealthKit available: \(healthKitService.healthKitAvailable)")
            print("📱 HealthKit authorization status: \(healthKitService.authorizationStatus)")

            // Try to collect health data regardless of authorization status
            // (individual data types may have different authorization levels)
            sensorData.healthData = await healthKitService.collectHealthData()

            if let healthData = sensorData.healthData {
                print("📱 Successfully collected health data")
            } else {
                print("📱 No health data collected")
            }
        } else {
            print("📱 HealthKit not available")
        }
    }

    /// Format sensor data for display
    func formatSensorDataForDisplay(_ sensorData: SensorData) -> [SensorDisplayItem] {
        var items: [SensorDisplayItem] = []

        // Location section
        items.append(SensorDisplayItem(category: "Location", items: [
            ("Coordinates", sensorData.location?.coordinate.description ?? "Unknown"),
            ("Accuracy", sensorData.locationAccuracy ?? "Unknown"),
            ("Altitude", sensorData.altitude?.description ?? "Unknown")
        ]))

        // Motion section
        var motionItems: [(String, String)] = []
        if let accel = sensorData.accelerometerData {
            motionItems.append(("Acceleration", "X: \(String(format: "%.2f", accel.acceleration.x)), Y: \(String(format: "%.2f", accel.acceleration.y)), Z: \(String(format: "%.2f", accel.acceleration.z))"))
        }
        if let gyro = sensorData.gyroscopeData {
            motionItems.append(("Rotation", "X: \(String(format: "%.2f", gyro.rotationRate.x)), Y: \(String(format: "%.2f", gyro.rotationRate.y)), Z: \(String(format: "%.2f", gyro.rotationRate.z))"))
        }
        if let motion = sensorData.deviceMotion {
            motionItems.append(("Gravity", "X: \(String(format: "%.2f", motion.gravity.x)), Y: \(String(format: "%.2f", motion.gravity.y)), Z: \(String(format: "%.2f", motion.gravity.z))"))
        }
        if !motionItems.isEmpty {
            items.append(SensorDisplayItem(category: "Motion", items: motionItems))
        }

        // Device section
        items.append(SensorDisplayItem(category: "Device", items: [
            ("Battery", "\(sensorData.batteryLevel)% (\(sensorData.batteryState))"),
            ("Orientation", sensorData.deviceOrientation),
            ("Timestamp", DateFormatter.localizedString(from: sensorData.timestamp, dateStyle: .none, timeStyle: .medium))
        ]))

        // Audio section
        items.append(SensorDisplayItem(category: "Audio", items: [
            ("Session Active", sensorData.audioSessionActive ? "Yes" : "No"),
            ("Input Available", sensorData.audioInputAvailable ? "Yes" : "No"),
            ("Microphone Permission", sensorData.microphonePermission)
        ]))

        // Camera section
        items.append(SensorDisplayItem(category: "Camera", items: [
            ("Permission", sensorData.cameraPermission),
            ("Front Camera", sensorData.frontCameraAvailable ? "Available" : "Not Available"),
            ("Back Camera", sensorData.backCameraAvailable ? "Available" : "Not Available")
        ]))

        // Contacts section
        items.append(SensorDisplayItem(category: "Contacts", items: [
            ("Permission", sensorData.contactsPermission),
            ("Emergency Contacts", "\(sensorData.emergencyContactsCount)")
        ]))

        // Network section
        items.append(SensorDisplayItem(category: "Network", items: [
            ("Status", sensorData.networkStatus),
            ("Signal Strength", sensorData.cellularSignalStrength ?? "Unknown")
        ]))

        // Apple Watch Health section
        if let healthData = sensorData.healthData {
            print("📱 Formatting health data for display")
            let healthItems = healthData.formatForDisplay()
            print("📱 Health items count: \(healthItems.count)")
            items.append(contentsOf: healthItems.map { healthItem in
                SensorDisplayItem(category: "Watch \(healthItem.category)", items: healthItem.items)
            })
        } else {
            print("📱 No health data to format")
            // Add Watch connectivity status even if no health data
            let watchConnectivity = WatchConnectivityService.shared
            items.append(SensorDisplayItem(category: "Watch Status", items: [
                ("Connectivity", watchConnectivity.watchStatusString),
                ("App Installed", watchConnectivity.isWatchAppInstalled ? "Yes" : "No"),
                ("HealthKit Available", HealthKitService.shared.healthKitAvailable ? "Yes" : "No")
            ]))
        }

        return items
    }
}

struct SensorDisplayItem {
    let category: String
    let items: [(String, String)]
}

extension CLLocationCoordinate2D {
    var description: String {
        return "\(String(format: "%.6f", latitude)), \(String(format: "%.6f", longitude))"
    }
}