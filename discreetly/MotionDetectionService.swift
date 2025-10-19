//
//  MotionDetectionService.swift
//  discreetly
//
//  Comprehensive motion detection and analysis service
//

import Foundation
import CoreMotion
import CoreLocation
import Combine
import UIKit

// MARK: - Movement State Tracking

/// Represents a movement state with timestamp for tracking transitions
struct MovementState {
    let state: MotionActivityState
    let timestamp: Date
    let accelerationMagnitude: Double

    init(state: MotionActivityState, accelerationMagnitude: Double) {
        self.state = state
        self.timestamp = Date()
        self.accelerationMagnitude = accelerationMagnitude
    }
}

/// Enhanced movement states for better transition detection
enum MotionActivityState: String, CaseIterable {
    case stationary = "Stationary"
    case walking = "Walking"
    case running = "Running"
    case driving = "Driving"
    case falling = "Falling"
    case shaking = "Shaking"
    case highActivity = "High Activity"
}

/// Configuration for rapid movement transition detection
struct MovementTransitionConfig {
    // Time window for rapid transitions (seconds)
    static let rapidTransitionWindow: TimeInterval = 3.0

    // Minimum duration to stay in stationary state before detecting rapid transition (reduced for testing)
    static let stationaryMinDuration: TimeInterval = 0.1  // Reduced to 0.1 seconds for immediate testing

    // Thresholds for movement classification (made more sensitive for testing)
    static let stationaryThreshold: Double = 0.1
    static let walkingThreshold: Double = 0.5  // Lowered from 1.5 to 0.5
    static let runningThreshold: Double = 1.0  // Lowered from 3.0 to 1.0

    // Transition patterns that trigger actions
    static let triggerTransitions: [(from: MotionActivityState, to: MotionActivityState)] = [
        (.stationary, .running),     // Direct stationary to running (high threat response)
        (.stationary, .walking)      // Stationary to walking (could be followed by running)
    ]
}

struct MotionAnalytics {
    // Raw motion data
    var accelerometerData: CMAccelerometerData?
    var gyroscopeData: CMGyroData?
    var magnetometerData: CMMagnetometerData?
    var deviceMotion: CMDeviceMotion?

    // Calculated metrics
    var totalAcceleration: Double = 0.0
    var accelerationMagnitude: Double = 0.0
    var estimatedSpeed: Double = 0.0 // m/s
    var estimatedDistance: Double = 0.0 // meters
    var rotationRate: Double = 0.0 // rad/s
    var deviceOrientation: String = "Unknown"
    var motionActivity: String = "Unknown"

    // Movement patterns
    var isStationary: Bool = false
    var isWalking: Bool = false
    var isRunning: Bool = false
    var isDriving: Bool = false
    var isFalling: Bool = false
    var isShaking: Bool = false

    // Historical data for analysis
    var accelerationHistory: [Double] = []
    var speedHistory: [Double] = []
    var timestamp: Date = Date()

    // Movement state tracking for rapid transition detection
    var movementStateHistory: [MovementState] = []

    // Thresholds and constants
    static let stationaryThreshold: Double = 0.1
    static let walkingThreshold: Double = 1.5
    static let runningThreshold: Double = 3.0
    static let drivingThreshold: Double = 5.0
    static let fallThreshold: Double = 8.0
    static let shakeThreshold: Double = 2.5

    mutating func calculateMetrics() {
        if let accel = accelerometerData {
            // Calculate total acceleration magnitude
            totalAcceleration = sqrt(
                accel.acceleration.x * accel.acceleration.x +
                accel.acceleration.y * accel.acceleration.y +
                accel.acceleration.z * accel.acceleration.z
            )

            // Remove gravity component for net acceleration
            accelerationMagnitude = abs(totalAcceleration - 1.0) // 1.0g is gravity

            // Update acceleration history
            accelerationHistory.append(accelerationMagnitude)
            if accelerationHistory.count > 100 { // Keep last 100 readings
                accelerationHistory.removeFirst()
            }

            // Estimate speed based on acceleration integration (simplified)
            let deltaTime = 0.1 // Update interval
            estimatedSpeed += accelerationMagnitude * deltaTime

            // Apply decay to prevent unrealistic speed buildup
            estimatedSpeed *= 0.98

            // Update speed history
            speedHistory.append(estimatedSpeed)
            if speedHistory.count > 50 { // Keep last 50 readings
                speedHistory.removeFirst()
            }

            // Estimate distance (simplified integration)
            estimatedDistance += estimatedSpeed * deltaTime

            // Analyze motion patterns
            analyzeMotionPatterns()
        }

        if let gyro = gyroscopeData {
            // Calculate rotation rate magnitude
            rotationRate = sqrt(
                gyro.rotationRate.x * gyro.rotationRate.x +
                gyro.rotationRate.y * gyro.rotationRate.y +
                gyro.rotationRate.z * gyro.rotationRate.z
            )
        }

        if let motion = deviceMotion {
            // Get device orientation from attitude
            let pitch = motion.attitude.pitch
            let roll = motion.attitude.roll

            if abs(pitch) < 0.5 && abs(roll) < 0.5 {
                deviceOrientation = "Flat"
            } else if pitch > 1.0 {
                deviceOrientation = "Face Down"
            } else if pitch < -1.0 {
                deviceOrientation = "Face Up"
            } else if roll > 1.0 {
                deviceOrientation = "Left Side"
            } else if roll < -1.0 {
                deviceOrientation = "Right Side"
            } else {
                deviceOrientation = "Tilted"
            }
        }
    }

    private mutating func analyzeMotionPatterns() {
        guard accelerationHistory.count >= 10 else { return }

        let recentAcceleration = accelerationHistory.suffix(10)
        let avgAcceleration = recentAcceleration.reduce(0, +) / Double(recentAcceleration.count)
        let maxAcceleration = recentAcceleration.max() ?? 0


        // Reset all states
        isStationary = false
        isWalking = false
        isRunning = false
        isDriving = false
        isFalling = false
        isShaking = false

        // Determine current movement state
        var currentState: MotionActivityState

        // Analyze patterns
        if maxAcceleration > Self.fallThreshold {
            isFalling = true
            motionActivity = "Falling"
            currentState = .falling
        } else if avgAcceleration > Self.shakeThreshold && maxAcceleration > Self.shakeThreshold * 1.5 {
            isShaking = true
            motionActivity = "Shaking"
            currentState = .shaking
        } else if avgAcceleration < MovementTransitionConfig.stationaryThreshold {
            isStationary = true
            motionActivity = "Stationary"
            currentState = .stationary
        } else if avgAcceleration < MovementTransitionConfig.walkingThreshold {
            isWalking = true
            motionActivity = "Walking"
            currentState = .walking
        } else if avgAcceleration < MovementTransitionConfig.runningThreshold {
            isRunning = true
            motionActivity = "Running"
            currentState = .running
        } else if avgAcceleration < Self.drivingThreshold {
            isDriving = true
            motionActivity = "Driving"
            currentState = .driving
        } else {
            motionActivity = "High Activity"
            currentState = .highActivity
        }

        // Update movement state history for transition detection
        updateMovementStateHistory(currentState: currentState, accelerationMagnitude: accelerationMagnitude)
    }

    /// Update movement state history and clean old entries
    private mutating func updateMovementStateHistory(currentState: MotionActivityState, accelerationMagnitude: Double) {
        let now = Date()

        // Add current state if it's different from the last recorded state
        if movementStateHistory.isEmpty || movementStateHistory.last?.state != currentState {
            let newMovementState = MovementState(state: currentState, accelerationMagnitude: accelerationMagnitude)
            movementStateHistory.append(newMovementState)
        }

        // Clean old entries (keep only last 30 seconds of history)
        movementStateHistory = movementStateHistory.filter { state in
            now.timeIntervalSince(state.timestamp) <= 30.0
        }
    }

    /// Detect rapid movement transitions that could indicate emergency situations
    func detectRapidMovementTransition() -> Bool {
        guard movementStateHistory.count >= 2 else {
            return false
        }

        let now = Date()
        let recentHistory = movementStateHistory.filter { state in
            now.timeIntervalSince(state.timestamp) <= MovementTransitionConfig.rapidTransitionWindow
        }

        guard recentHistory.count >= 2 else {
            return false
        }

        // Look for rapid transitions from stationary to walking/running
        // Note: recentHistory is in reverse chronological order (newest first), so we need to check backwards
        for i in (1..<recentHistory.count).reversed() {
            let fromState = recentHistory[i]     // Earlier state (older)
            let toState = recentHistory[i - 1]   // Later state (newer)

            // Check if this transition matches our trigger patterns
            for triggerTransition in MovementTransitionConfig.triggerTransitions {
                if fromState.state == triggerTransition.from && toState.state == triggerTransition.to {
                    return true
                }
            }
        }

        // Also check for rapid escalation: stationary → walking → running within time window
        // Note: recentHistory is in reverse chronological order, so index 2 is oldest, index 0 is newest
        if recentHistory.count >= 3 {
            for i in (2..<recentHistory.count).reversed() {
                let firstState = recentHistory[i]     // Oldest (stationary)
                let secondState = recentHistory[i - 1] // Middle (walking)
                let thirdState = recentHistory[i - 2]  // Newest (running)

                if firstState.state == .stationary &&
                   secondState.state == .walking &&
                   thirdState.state == .running {

                    let totalTransitionTime = firstState.timestamp.timeIntervalSince(thirdState.timestamp)
                    if totalTransitionTime <= MovementTransitionConfig.rapidTransitionWindow {
                        return true
                    }
                }
            }
        }

        return false
    }

    /// Get duration that user was stationary before a given timestamp
    private func getStationaryDuration(before timestamp: Date) -> TimeInterval {
        var stationaryDuration: TimeInterval = 0

        // Look backwards through history to find how long they were stationary
        for state in movementStateHistory.reversed() {
            if state.timestamp >= timestamp { continue }

            if state.state == .stationary {
                stationaryDuration = timestamp.timeIntervalSince(state.timestamp)
            } else {
                break // Found non-stationary state, stop counting
            }
        }

        return stationaryDuration
    }

    func getSpeedKmh() -> Double {
        return estimatedSpeed * 3.6 // Convert m/s to km/h
    }

    func getSpeedMph() -> Double {
        return estimatedSpeed * 2.237 // Convert m/s to mph
    }

    func getAverageAcceleration() -> Double {
        guard !accelerationHistory.isEmpty else { return 0.0 }
        return accelerationHistory.reduce(0, +) / Double(accelerationHistory.count)
    }

    func getPeakAcceleration() -> Double {
        return accelerationHistory.max() ?? 0.0
    }
}

final class MotionDetectionService: ObservableObject {
    static let shared = MotionDetectionService()

    @Published var currentMotionAnalytics = MotionAnalytics()
    @Published var isActive = false
    @Published var permissionStatus: String = "Unknown"

    private let motionManager = CMMotionManager()
    private let pedometer = CMPedometer()
    private let motionActivityManager = CMMotionActivityManager()
    private var updateTimer: Timer?

    // Movement trigger callback
    var onRapidMovementTransition: (() -> Void)?

    // Rate limiting: only trigger once per app launch
    private var hasTriggeredThisSession = false

    private init() {
        setupMotionManager()
        checkPermissions()
    }

    private func setupMotionManager() {
        // Set update intervals
        motionManager.accelerometerUpdateInterval = 0.1 // 10 Hz
        motionManager.gyroUpdateInterval = 0.1
        motionManager.magnetometerUpdateInterval = 0.1
        motionManager.deviceMotionUpdateInterval = 0.1
    }

    func checkPermissions() {
        // Check motion permission - prioritize basic sensors over activity manager
        let hasBasicMotion = motionManager.isAccelerometerAvailable || motionManager.isGyroAvailable

        if hasBasicMotion {
            // Basic motion sensors are available
            if CMMotionActivityManager.isActivityAvailable() {
                let authStatus = CMMotionActivityManager.authorizationStatus()
                switch authStatus {
                case .authorized:
                    permissionStatus = "Authorized (Full)"
                case .denied:
                    permissionStatus = "Basic Sensors Only"
                case .restricted:
                    permissionStatus = "Basic Sensors Only"
                case .notDetermined:
                    permissionStatus = "Basic Sensors Available"
                @unknown default:
                    permissionStatus = "Basic Sensors Available"
                }
            } else {
                // Activity manager not available but basic sensors work
                permissionStatus = "Basic Sensors Only"
            }
        } else {
            // Likely simulator or no motion hardware
            permissionStatus = "Simulator/Not Available"
        }

        print("🏃‍♂️ Motion detection capability check:")
        print("  - Accelerometer available: \(motionManager.isAccelerometerAvailable)")
        print("  - Gyroscope available: \(motionManager.isGyroAvailable)")
        print("  - Activity manager available: \(CMMotionActivityManager.isActivityAvailable())")
        print("  - Status: \(permissionStatus)")
    }

    func requestPermissions() async {
        guard CMMotionActivityManager.isActivityAvailable() else {
            await MainActor.run {
                permissionStatus = "Not Available"
            }
            return
        }

        return await withCheckedContinuation { continuation in
            motionActivityManager.startActivityUpdates(to: .main) { [weak self] (activity: CMMotionActivity?) in
                self?.motionActivityManager.stopActivityUpdates()

                DispatchQueue.main.async {
                    if activity != nil {
                        self?.permissionStatus = "Authorized"
                    } else {
                        self?.permissionStatus = "Denied"
                    }
                    continuation.resume()
                }
            }
        }
    }

    func startMotionDetection() {
        guard !isActive else { return }

        isActive = true
        print("🏃‍♂️ Starting motion detection with available sensors")

        var sensorsStarted = 0

        // Start accelerometer updates
        if motionManager.isAccelerometerAvailable {
            motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, error in
                if let data = data {
                    self?.currentMotionAnalytics.accelerometerData = data
                }
            }
            sensorsStarted += 1
            print("  ✅ Accelerometer started")
        } else {
            print("  ❌ Accelerometer not available")
        }

        // Start gyroscope updates
        if motionManager.isGyroAvailable {
            motionManager.startGyroUpdates(to: .main) { [weak self] data, error in
                if let data = data {
                    self?.currentMotionAnalytics.gyroscopeData = data
                }
            }
            sensorsStarted += 1
            print("  ✅ Gyroscope started")
        } else {
            print("  ❌ Gyroscope not available")
        }

        // Start magnetometer updates
        if motionManager.isMagnetometerAvailable {
            motionManager.startMagnetometerUpdates(to: .main) { [weak self] data, error in
                if let data = data {
                    self?.currentMotionAnalytics.magnetometerData = data
                }
            }
            sensorsStarted += 1
            print("  ✅ Magnetometer started")
        } else {
            print("  ❌ Magnetometer not available")
        }

        // Start device motion updates (combines all sensors)
        if motionManager.isDeviceMotionAvailable {
            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] data, error in
                if let data = data {
                    self?.currentMotionAnalytics.deviceMotion = data
                }
            }
            sensorsStarted += 1
            print("  ✅ Device Motion started")
        } else {
            print("  ❌ Device Motion not available")
        }

        // Start motion activity detection (if available and authorized)
        if CMMotionActivityManager.isActivityAvailable() && permissionStatus.contains("Authorized") {
            startMotionActivityUpdates()
            print("  ✅ Motion Activity started")
        } else {
            print("  ⚠️ Motion Activity not available or not authorized")
        }

        // Start step counting (if available)
        if CMPedometer.isStepCountingAvailable() {
            startStepCounting()
            print("  ✅ Step counting started")
        } else {
            print("  ⚠️ Step counting not available")
        }

        print("🏃‍♂️ Motion detection started with \(sensorsStarted) sensors")

        // Start periodic analytics calculation
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateAnalytics()
        }
    }

    func stopMotionDetection() {
        guard isActive else { return }

        isActive = false
        print("⏹️ Stopping motion detection")

        motionManager.stopAccelerometerUpdates()
        motionManager.stopGyroUpdates()
        motionManager.stopMagnetometerUpdates()
        motionManager.stopDeviceMotionUpdates()
        motionActivityManager.stopActivityUpdates()
        pedometer.stopUpdates()

        updateTimer?.invalidate()
        updateTimer = nil
    }

    private func startMotionActivityUpdates() {
        motionActivityManager.startActivityUpdates(to: .main) { [weak self] (activity: CMMotionActivity?) in
            guard let activity = activity else { return }

            var activityString = "Unknown"
            if activity.stationary {
                activityString = "Stationary"
            } else if activity.walking {
                activityString = "Walking"
            } else if activity.running {
                activityString = "Running"
            } else if activity.automotive {
                activityString = "Driving"
            } else if activity.cycling {
                activityString = "Cycling"
            }

            DispatchQueue.main.async {
                self?.currentMotionAnalytics.motionActivity = activityString
            }
        }
    }

    private func startStepCounting() {
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)

        pedometer.startUpdates(from: startOfDay) { data, error in
            // This gives us step count and other metrics
            // We can use this for additional context
        }
    }

    private func updateAnalytics() {
        currentMotionAnalytics.timestamp = Date()
        currentMotionAnalytics.calculateMetrics()

        // Check for rapid movement transitions
        if currentMotionAnalytics.detectRapidMovementTransition() {
            if !hasTriggeredThisSession {
                hasTriggeredThisSession = true
                onRapidMovementTransition?()
            }
        }

        objectWillChange.send()
    }

    // MARK: - Testing & Debug Methods

    /// Reset the rate limit for testing (allows triggering again)
    func resetRateLimit() {
        hasTriggeredThisSession = false
    }

    /// Manually trigger a movement transition for testing
    func manuallyTriggerMovementTransition() {
        // Add fake movement states to trigger the detection
        let now = Date()
        let stationaryState = MovementState(state: .stationary, accelerationMagnitude: 0.05)
        let runningState = MovementState(state: .running, accelerationMagnitude: 1.2)

        // Manually add to history with proper timing
        var modifiedHistory = currentMotionAnalytics.movementStateHistory
        modifiedHistory.append(MovementState(state: .stationary, accelerationMagnitude: 0.05))

        // Add a short delay then running state
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.currentMotionAnalytics.movementStateHistory.append(MovementState(state: .running, accelerationMagnitude: 1.2))

            // Force detection check
            if self?.currentMotionAnalytics.detectRapidMovementTransition() == true {
                if self?.hasTriggeredThisSession == false {
                    self?.hasTriggeredThisSession = true
                    self?.onRapidMovementTransition?()
                }
            }
        }
    }

    // MARK: - Emergency Detection

    func detectEmergencyMotion() -> Bool {
        let analytics = currentMotionAnalytics

        // Fall detection
        if analytics.isFalling {
            print("🚨 FALL DETECTED")
            return true
        }

        // Violent shaking (potential distress)
        if analytics.isShaking && analytics.getPeakAcceleration() > 5.0 {
            print("🚨 VIOLENT MOTION DETECTED")
            return true
        }

        // Sudden stop from high speed (potential accident)
        if analytics.speedHistory.count >= 2 {
            let currentSpeed = analytics.speedHistory.last ?? 0
            let previousSpeed = analytics.speedHistory[analytics.speedHistory.count - 2]

            if previousSpeed > 10.0 && currentSpeed < 2.0 { // Sudden deceleration
                print("🚨 SUDDEN STOP DETECTED")
                return true
            }
        }

        return false
    }

    // MARK: - Data Export

    func exportMotionData() -> [String: Any] {
        let analytics = currentMotionAnalytics

        return [
            "timestamp": analytics.timestamp.timeIntervalSince1970,
            "totalAcceleration": analytics.totalAcceleration,
            "accelerationMagnitude": analytics.accelerationMagnitude,
            "estimatedSpeed_ms": analytics.estimatedSpeed,
            "estimatedSpeed_kmh": analytics.getSpeedKmh(),
            "estimatedSpeed_mph": analytics.getSpeedMph(),
            "estimatedDistance": analytics.estimatedDistance,
            "rotationRate": analytics.rotationRate,
            "deviceOrientation": analytics.deviceOrientation,
            "motionActivity": analytics.motionActivity,
            "isStationary": analytics.isStationary,
            "isWalking": analytics.isWalking,
            "isRunning": analytics.isRunning,
            "isDriving": analytics.isDriving,
            "isFalling": analytics.isFalling,
            "isShaking": analytics.isShaking,
            "averageAcceleration": analytics.getAverageAcceleration(),
            "peakAcceleration": analytics.getPeakAcceleration(),
            "accelerometerX": analytics.accelerometerData?.acceleration.x ?? 0,
            "accelerometerY": analytics.accelerometerData?.acceleration.y ?? 0,
            "accelerometerZ": analytics.accelerometerData?.acceleration.z ?? 0,
            "gyroscopeX": analytics.gyroscopeData?.rotationRate.x ?? 0,
            "gyroscopeY": analytics.gyroscopeData?.rotationRate.y ?? 0,
            "gyroscopeZ": analytics.gyroscopeData?.rotationRate.z ?? 0
        ]
    }
}

// MARK: - Motion Analytics Extensions

extension MotionAnalytics {
    var formattedData: [(String, String)] {
        return [
            ("Activity", motionActivity),
            ("Speed", String(format: "%.1f km/h (%.1f mph)", getSpeedKmh(), getSpeedMph())),
            ("Acceleration", String(format: "%.2f m/s²", accelerationMagnitude)),
            ("Total G-Force", String(format: "%.2f g", totalAcceleration)),
            ("Distance", String(format: "%.0f m", estimatedDistance)),
            ("Rotation Rate", String(format: "%.2f rad/s", rotationRate)),
            ("Orientation", deviceOrientation),
            ("Avg Acceleration", String(format: "%.2f m/s²", getAverageAcceleration())),
            ("Peak Acceleration", String(format: "%.2f m/s²", getPeakAcceleration()))
        ]
    }

    var statusData: [(String, String)] {
        return [
            ("Stationary", isStationary ? "Yes" : "No"),
            ("Walking", isWalking ? "Yes" : "No"),
            ("Running", isRunning ? "Yes" : "No"),
            ("Driving", isDriving ? "Yes" : "No"),
            ("Falling", isFalling ? "⚠️ YES" : "No"),
            ("Shaking", isShaking ? "⚠️ YES" : "No")
        ]
    }

    var rawSensorData: [(String, String)] {
        var data: [(String, String)] = []

        if let accel = accelerometerData {
            data.append(("Accel X", String(format: "%.3f g", accel.acceleration.x)))
            data.append(("Accel Y", String(format: "%.3f g", accel.acceleration.y)))
            data.append(("Accel Z", String(format: "%.3f g", accel.acceleration.z)))
        }

        if let gyro = gyroscopeData {
            data.append(("Gyro X", String(format: "%.3f rad/s", gyro.rotationRate.x)))
            data.append(("Gyro Y", String(format: "%.3f rad/s", gyro.rotationRate.y)))
            data.append(("Gyro Z", String(format: "%.3f rad/s", gyro.rotationRate.z)))
        }

        if let mag = magnetometerData {
            data.append(("Mag X", String(format: "%.3f µT", mag.magneticField.x)))
            data.append(("Mag Y", String(format: "%.3f µT", mag.magneticField.y)))
            data.append(("Mag Z", String(format: "%.3f µT", mag.magneticField.z)))
        }

        return data
    }
}