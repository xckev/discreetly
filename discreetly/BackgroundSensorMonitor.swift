//
//  BackgroundSensorMonitor.swift
//  discreetly
//
//  Background monitoring service for continuous sensor data collection
//  Enables instant triggers without waiting for sensor screen loading
//

import Foundation
import CoreMotion
import CoreLocation
import AVFoundation
import UIKit
import Combine
import HealthKit
import Contacts

final class BackgroundSensorMonitor: NSObject, ObservableObject {
    static let shared = BackgroundSensorMonitor()

    @Published var isMonitoring = false
    @Published var lastSensorUpdate: Date?
    @Published var cachedSensorData = SensorData()

    private let motionManager = CMMotionManager()
    private let locationService = LocationService.shared
    private let healthKitService = HealthKitService.shared

    private var updateTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    // Background monitoring intervals
    private let fastUpdateInterval: TimeInterval = 0.5 // High frequency for critical sensors
    private let slowUpdateInterval: TimeInterval = 5.0 // Lower frequency for static data

    // Data freshness tracking
    private var lastLocationUpdate: Date?
    private var lastMotionUpdate: Date?
    private var lastDeviceUpdate: Date?
    private var lastHealthUpdate: Date?

    private override init() {
        super.init()
        setupMotionManager()
        setupNotifications()
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - Setup

    private func setupMotionManager() {
        motionManager.accelerometerUpdateInterval = fastUpdateInterval
        motionManager.gyroUpdateInterval = fastUpdateInterval
        motionManager.magnetometerUpdateInterval = fastUpdateInterval
        motionManager.deviceMotionUpdateInterval = fastUpdateInterval
    }

    private func setupNotifications() {
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                self?.handleAppBackground()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                self?.handleAppForeground()
            }
            .store(in: &cancellables)
    }

    // MARK: - Public Interface

    func startMonitoring() {
        guard !isMonitoring else {
            print("📡 Background sensor monitoring already running")
            return
        }

        print("📡 Starting background sensor monitoring...")
        isMonitoring = true

        // Start continuous motion monitoring
        startMotionMonitoring()

        // Start periodic updates for other sensors
        startPeriodicUpdates()

        // Initial data collection
        Task {
            await collectInitialData()
        }

        print("✅ Background sensor monitoring started")
    }

    func stopMonitoring() {
        guard isMonitoring else { return }

        print("📡 Stopping background sensor monitoring...")
        isMonitoring = false

        // Stop motion monitoring
        stopMotionMonitoring()

        // Stop periodic updates
        updateTimer?.invalidate()
        updateTimer = nil

        print("✅ Background sensor monitoring stopped")
    }

    func getCurrentSensorData() -> SensorData {
        // Return immediately available cached data
        var data = cachedSensorData
        data.timestamp = Date()
        return data
    }

    func refreshSensorData() async -> SensorData {
        // Force refresh all sensors and return updated data
        await updateAllSensors()
        return getCurrentSensorData()
    }

    // MARK: - Motion Monitoring

    private func startMotionMonitoring() {
        // Start continuous motion updates for immediate trigger detection
        if motionManager.isAccelerometerAvailable {
            motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, error in
                if let data = data, error == nil {
                    self?.updateMotionData(accelerometer: data)
                }
            }
        }

        if motionManager.isGyroAvailable {
            motionManager.startGyroUpdates(to: .main) { [weak self] data, error in
                if let data = data, error == nil {
                    self?.updateMotionData(gyro: data)
                }
            }
        }

        if motionManager.isDeviceMotionAvailable {
            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] data, error in
                if let data = data, error == nil {
                    self?.updateMotionData(deviceMotion: data)
                }
            }
        }

        print("📡 Continuous motion monitoring started")
    }

    private func stopMotionMonitoring() {
        motionManager.stopAccelerometerUpdates()
        motionManager.stopGyroUpdates()
        motionManager.stopDeviceMotionUpdates()
        print("📡 Motion monitoring stopped")
    }

    private func updateMotionData(accelerometer: CMAccelerometerData? = nil, gyro: CMGyroData? = nil, deviceMotion: CMDeviceMotion? = nil) {
        if let accelerometer = accelerometer {
            cachedSensorData.accelerometerData = accelerometer
        }
        if let gyro = gyro {
            cachedSensorData.gyroscopeData = gyro
        }
        if let deviceMotion = deviceMotion {
            cachedSensorData.deviceMotion = deviceMotion
        }

        lastMotionUpdate = Date()
        lastSensorUpdate = Date()
    }

    // MARK: - Periodic Updates

    private func startPeriodicUpdates() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: slowUpdateInterval, repeats: true) { [weak self] _ in
            Task {
                await self?.performPeriodicUpdate()
            }
        }
    }

    private func performPeriodicUpdate() async {
        await updateLocationIfNeeded()
        await updateDeviceDataIfNeeded()
        await updateHealthDataIfNeeded()

        // Update other relatively static data less frequently
        await updateAudioData()
        await updateCameraData()
        await updateContactsData()
        await updateNetworkData()

        lastSensorUpdate = Date()
    }

    // MARK: - Individual Sensor Updates

    private func collectInitialData() async {
        await updateAllSensors()
    }

    private func updateAllSensors() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.updateLocationData() }
            group.addTask { await self.updateDeviceData() }
            group.addTask { await self.updateAudioData() }
            group.addTask { await self.updateCameraData() }
            group.addTask { await self.updateContactsData() }
            group.addTask { await self.updateNetworkData() }
            group.addTask { await self.updateHealthData() }
        }
    }

    private func updateLocationIfNeeded() async {
        let now = Date()
        if lastLocationUpdate == nil || now.timeIntervalSince(lastLocationUpdate!) > 30.0 {
            await updateLocationData()
        }
    }

    private func updateLocationData() async {
        do {
            let location = try await locationService.getCurrentLocation()
            cachedSensorData.location = location
            cachedSensorData.locationAccuracy = String(format: "±%.0fm", location.horizontalAccuracy)
            cachedSensorData.altitude = location.altitude
            lastLocationUpdate = Date()
        } catch {
            // Keep previous location data if new request fails
            print("📡 Failed to update location: \(error)")
        }
    }

    private func updateDeviceDataIfNeeded() async {
        let now = Date()
        if lastDeviceUpdate == nil || now.timeIntervalSince(lastDeviceUpdate!) > 10.0 {
            await updateDeviceData()
        }
    }

    private func updateDeviceData() async {
        await MainActor.run {
            UIDevice.current.isBatteryMonitoringEnabled = true
            cachedSensorData.batteryLevel = Int(UIDevice.current.batteryLevel * 100)

            switch UIDevice.current.batteryState {
            case .unplugged: cachedSensorData.batteryState = "Unplugged"
            case .charging: cachedSensorData.batteryState = "Charging"
            case .full: cachedSensorData.batteryState = "Full"
            default: cachedSensorData.batteryState = "Unknown"
            }

            switch UIDevice.current.orientation {
            case .portrait: cachedSensorData.deviceOrientation = "Portrait"
            case .portraitUpsideDown: cachedSensorData.deviceOrientation = "Portrait Upside Down"
            case .landscapeLeft: cachedSensorData.deviceOrientation = "Landscape Left"
            case .landscapeRight: cachedSensorData.deviceOrientation = "Landscape Right"
            case .faceUp: cachedSensorData.deviceOrientation = "Face Up"
            case .faceDown: cachedSensorData.deviceOrientation = "Face Down"
            default: cachedSensorData.deviceOrientation = "Unknown"
            }

            lastDeviceUpdate = Date()
        }
    }

    private func updateAudioData() async {
        let audioSession = AVAudioSession.sharedInstance()

        cachedSensorData.audioSessionActive = audioSession.isOtherAudioPlaying == false
        cachedSensorData.audioInputAvailable = !(audioSession.availableInputs?.isEmpty ?? true)

        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted: cachedSensorData.microphonePermission = "Granted"
            case .denied: cachedSensorData.microphonePermission = "Denied"
            case .undetermined: cachedSensorData.microphonePermission = "Not Requested"
            @unknown default: cachedSensorData.microphonePermission = "Unknown"
            }
        } else {
            switch AVAudioSession.sharedInstance().recordPermission {
            case .granted: cachedSensorData.microphonePermission = "Granted"
            case .denied: cachedSensorData.microphonePermission = "Denied"
            case .undetermined: cachedSensorData.microphonePermission = "Not Requested"
            @unknown default: cachedSensorData.microphonePermission = "Unknown"
            }
        }
    }

    private func updateCameraData() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: cachedSensorData.cameraPermission = "Granted"
        case .denied: cachedSensorData.cameraPermission = "Denied"
        case .restricted: cachedSensorData.cameraPermission = "Restricted"
        case .notDetermined: cachedSensorData.cameraPermission = "Not Requested"
        @unknown default: cachedSensorData.cameraPermission = "Unknown"
        }

        cachedSensorData.frontCameraAvailable = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil
        cachedSensorData.backCameraAvailable = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    private func updateContactsData() async {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized: cachedSensorData.contactsPermission = "Granted"
        case .denied: cachedSensorData.contactsPermission = "Denied"
        case .restricted: cachedSensorData.contactsPermission = "Restricted"
        case .notDetermined: cachedSensorData.contactsPermission = "Not Requested"
        case .limited: cachedSensorData.contactsPermission = "Limited"
        @unknown default: cachedSensorData.contactsPermission = "Unknown"
        }

        cachedSensorData.emergencyContactsCount = SettingsManager.shared.settings.contacts.count
    }

    private func updateNetworkData() async {
        cachedSensorData.networkStatus = "Connected"
        cachedSensorData.cellularSignalStrength = "Good"
    }

    private func updateHealthDataIfNeeded() async {
        let now = Date()
        if lastHealthUpdate == nil || now.timeIntervalSince(lastHealthUpdate!) > 60.0 {
            await updateHealthData()
        }
    }

    private func updateHealthData() async {
        if healthKitService.healthKitAvailable {
            cachedSensorData.healthData = await healthKitService.collectHealthData()
            lastHealthUpdate = Date()
        }
    }

    // MARK: - App Lifecycle

    private func handleAppBackground() {
        print("📡 App backgrounded - reducing sensor monitoring frequency")
        // Reduce update frequency in background to conserve battery
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task {
                await self?.performPeriodicUpdate()
            }
        }
    }

    private func handleAppForeground() {
        print("📡 App foregrounded - restoring full sensor monitoring")
        // Restore full monitoring frequency
        updateTimer?.invalidate()
        startPeriodicUpdates()

        // Immediate refresh on foreground
        Task {
            await updateAllSensors()
        }
    }

    // MARK: - Debug

    func getMonitoringStatus() -> String {
        var status = "Background Sensor Monitor Status:\n"
        status += "- Monitoring: \(isMonitoring ? "Active" : "Inactive")\n"
        status += "- Last Update: \(lastSensorUpdate?.description ?? "Never")\n"
        status += "- Motion Manager Running: \(motionManager.isAccelerometerActive)\n"
        status += "- Timer Active: \(updateTimer != nil)\n"
        status += "- Cached Data Age: \(Date().timeIntervalSince(cachedSensorData.timestamp)) seconds"
        return status
    }
}

// MARK: - Extensions

extension BackgroundSensorMonitor {
    var isDataFresh: Bool {
        guard let lastUpdate = lastSensorUpdate else { return false }
        return Date().timeIntervalSince(lastUpdate) < 10.0
    }

    var dataAge: TimeInterval {
        guard let lastUpdate = lastSensorUpdate else { return Double.infinity }
        return Date().timeIntervalSince(lastUpdate)
    }
}