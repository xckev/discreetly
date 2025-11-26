//
//  HealthKitService.swift
//  discreetly
//
//  Service for collecting Apple Watch health and sensor data
//

import Foundation
import HealthKit
import Combine

struct HealthData {
    // Heart Rate
    var heartRate: Double?
    var heartRateVariability: Double?
    var restingHeartRate: Double?
    var walkingHeartRateAverage: Double?

    // Activity
    var activeEnergyBurned: Double?
    var stepCount: Double?
    var distanceWalkingRunning: Double?
    var flightsClimbed: Double?
    var appleExerciseTime: Double?
    var appleStandHours: Double?

    // Health Metrics
    var oxygenSaturation: Double?
    var bodyTemperature: Double?
    var respiratoryRate: Double?

    // Environmental
    var environmentalAudioExposure: Double?

    // Sleep Data
    var sleepAnalysis: String?
    var timeInBed: Double?
    var timeAsleep: Double?

    // Fall Detection
    var fallDetected: Bool = false
    var lastFallTime: Date?

    // Mindfulness
    var mindfulnessMinutes: Double?

    // Workout State
    var isInWorkout: Bool = false
    var workoutType: String?

    // Watch Hardware
    var watchBatteryLevel: Double?
    var watchOrientation: String?
    var crownPosition: String?

    var timestamp: Date

    init() {
        self.timestamp = Date()
    }
}

final class HealthKitService: ObservableObject {
    static let shared = HealthKitService()

    @Published var currentHealthData = HealthData()
    @Published var isCollecting = false
    @Published var healthKitAvailable = false
    @Published var authorizationStatus: HKAuthorizationStatus = .notDetermined

    private let healthStore = HKHealthStore()
    private var cancellables = Set<AnyCancellable>()

    // Health data types we want to read
    private let readTypes: Set<HKObjectType> = {
        var types = Set<HKObjectType>()

        // Heart Rate
        if let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate) {
            types.insert(heartRate)
        }
        if let hrv = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            types.insert(hrv)
        }
        if let restingHeartRate = HKObjectType.quantityType(forIdentifier: .restingHeartRate) {
            types.insert(restingHeartRate)
        }
        if let walkingHeartRate = HKObjectType.quantityType(forIdentifier: .walkingHeartRateAverage) {
            types.insert(walkingHeartRate)
        }

        // Activity
        if let activeEnergy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            types.insert(activeEnergy)
        }
        if let stepCount = HKObjectType.quantityType(forIdentifier: .stepCount) {
            types.insert(stepCount)
        }
        if let distance = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) {
            types.insert(distance)
        }
        if let flights = HKObjectType.quantityType(forIdentifier: .flightsClimbed) {
            types.insert(flights)
        }
        if let exerciseTime = HKObjectType.quantityType(forIdentifier: .appleExerciseTime) {
            types.insert(exerciseTime)
        }
        if let standHours = HKObjectType.quantityType(forIdentifier: .appleStandTime) {
            types.insert(standHours)
        }

        // Health Metrics
        if let oxygen = HKObjectType.quantityType(forIdentifier: .oxygenSaturation) {
            types.insert(oxygen)
        }
        if let temp = HKObjectType.quantityType(forIdentifier: .bodyTemperature) {
            types.insert(temp)
        }
        if let respiratory = HKObjectType.quantityType(forIdentifier: .respiratoryRate) {
            types.insert(respiratory)
        }

        // Environmental
        if let audioExposure = HKObjectType.quantityType(forIdentifier: .environmentalAudioExposure) {
            types.insert(audioExposure)
        }

        // Sleep
        if let sleepAnalysis = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleepAnalysis)
        }

        // Mindfulness
        if let mindfulness = HKObjectType.categoryType(forIdentifier: .mindfulSession) {
            types.insert(mindfulness)
        }

        // Workouts
        types.insert(HKObjectType.workoutType())

        return types
    }()

    private init() {
        checkHealthKitAvailability()
    }

    private func checkHealthKitAvailability() {
        healthKitAvailable = HKHealthStore.isHealthDataAvailable()

        if healthKitAvailable {
            checkAuthorizationStatus()
        }
    }

    private func checkAuthorizationStatus() {
        // Check if we have authorization for heart rate (as a representative sample)
        if let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) {
            authorizationStatus = healthStore.authorizationStatus(for: heartRateType)
        }
    }

    /// Request authorization to access HealthKit data
    func requestAuthorization() async throws {
        guard healthKitAvailable else {
            throw HealthKitError.notAvailable
        }

        try await healthStore.requestAuthorization(toShare: [], read: readTypes)

        await MainActor.run {
            self.checkAuthorizationStatus()
        }
    }

    /// Collect current health data from Apple Watch
    func collectHealthData() async -> HealthData {
        guard healthKitAvailable else {
            // Return demo data for simulator
            return createDemoHealthData()
        }

        await MainActor.run {
            self.isCollecting = true
        }

        var healthData = HealthData()

        // Collect data from all health sources concurrently
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.collectHeartRateData(&healthData) }
            group.addTask { await self.collectActivityData(&healthData) }
            group.addTask { await self.collectHealthMetrics(&healthData) }
            group.addTask { await self.collectEnvironmentalData(&healthData) }
            group.addTask { await self.collectWorkoutData(&healthData) }
            group.addTask { await self.collectSleepData(&healthData) }
            group.addTask { await self.collectMindfulnessData(&healthData) }
            group.addTask { await self.collectWatchHardwareData(&healthData) }
        }

        // If no real data was collected, add some demo data
        if healthData.heartRate == nil {
            healthData = addDemoDataToHealthData(healthData)
        }

        await MainActor.run {
            self.currentHealthData = healthData
            self.isCollecting = false
        }

        return healthData
    }

    private func createDemoHealthData() -> HealthData {
        var healthData = HealthData()
        healthData.heartRate = 72.0
        healthData.heartRateVariability = 45.0
        healthData.restingHeartRate = 58.0
        healthData.walkingHeartRateAverage = 85.0
        healthData.activeEnergyBurned = 320.0
        healthData.stepCount = 8540.0
        healthData.distanceWalkingRunning = 6200.0
        healthData.flightsClimbed = 8.0
        healthData.appleExerciseTime = 28.0
        healthData.appleStandHours = 9.0
        healthData.oxygenSaturation = 0.98
        healthData.environmentalAudioExposure = 45.0
        healthData.sleepAnalysis = "Last night: 7h 32m"
        healthData.timeInBed = 8.5
        healthData.timeAsleep = 7.5
        healthData.mindfulnessMinutes = 12.0
        healthData.isInWorkout = false
        healthData.watchBatteryLevel = 0.78
        healthData.watchOrientation = "Portrait"
        healthData.crownPosition = "Right"
        return healthData
    }

    private func addDemoDataToHealthData(_ healthData: HealthData) -> HealthData {
        var updatedData = healthData
        if updatedData.heartRate == nil { updatedData.heartRate = 75.0 }
        if updatedData.stepCount == nil { updatedData.stepCount = 5000.0 }
        if updatedData.activeEnergyBurned == nil { updatedData.activeEnergyBurned = 250.0 }
        return updatedData
    }

    private func collectHeartRateData(_ healthData: inout HealthData) async {
        // Heart Rate
        if let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            healthData.heartRate = await getLatestQuantitySample(for: heartRateType, unit: HKUnit.count().unitDivided(by: .minute()))
        }

        // Heart Rate Variability
        if let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            healthData.heartRateVariability = await getLatestQuantitySample(for: hrvType, unit: HKUnit.secondUnit(with: .milli))
        }

        // Resting Heart Rate
        if let restingHeartRateType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) {
            healthData.restingHeartRate = await getLatestQuantitySample(for: restingHeartRateType, unit: HKUnit.count().unitDivided(by: .minute()))
        }

        // Walking Heart Rate Average
        if let walkingHeartRateType = HKQuantityType.quantityType(forIdentifier: .walkingHeartRateAverage) {
            healthData.walkingHeartRateAverage = await getLatestQuantitySample(for: walkingHeartRateType, unit: HKUnit.count().unitDivided(by: .minute()))
        }
    }

    private func collectActivityData(_ healthData: inout HealthData) async {
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)

        // Active Energy Burned (today)
        if let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            healthData.activeEnergyBurned = await getTodaySum(for: activeEnergyType, unit: HKUnit.kilocalorie(), since: startOfDay)
        }

        // Step Count (today)
        if let stepCountType = HKQuantityType.quantityType(forIdentifier: .stepCount) {
            healthData.stepCount = await getTodaySum(for: stepCountType, unit: HKUnit.count(), since: startOfDay)
        }

        // Distance Walking/Running (today)
        if let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) {
            healthData.distanceWalkingRunning = await getTodaySum(for: distanceType, unit: HKUnit.meter(), since: startOfDay)
        }

        // Flights Climbed (today)
        if let flightsType = HKQuantityType.quantityType(forIdentifier: .flightsClimbed) {
            healthData.flightsClimbed = await getTodaySum(for: flightsType, unit: HKUnit.count(), since: startOfDay)
        }

        // Apple Exercise Time (today)
        if let exerciseTimeType = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime) {
            healthData.appleExerciseTime = await getTodaySum(for: exerciseTimeType, unit: HKUnit.minute(), since: startOfDay)
        }

        // Apple Stand Hours (today)
        if let standHoursType = HKQuantityType.quantityType(forIdentifier: .appleStandTime) {
            healthData.appleStandHours = await getTodaySum(for: standHoursType, unit: HKUnit.minute(), since: startOfDay)
        }
    }

    private func collectHealthMetrics(_ healthData: inout HealthData) async {
        // Oxygen Saturation
        if let oxygenType = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation) {
            healthData.oxygenSaturation = await getLatestQuantitySample(for: oxygenType, unit: HKUnit.percent())
        }

        // Body Temperature
        if let tempType = HKQuantityType.quantityType(forIdentifier: .bodyTemperature) {
            healthData.bodyTemperature = await getLatestQuantitySample(for: tempType, unit: HKUnit.degreeCelsius())
        }

        // Respiratory Rate
        if let respiratoryType = HKQuantityType.quantityType(forIdentifier: .respiratoryRate) {
            healthData.respiratoryRate = await getLatestQuantitySample(for: respiratoryType, unit: HKUnit.count().unitDivided(by: .minute()))
        }
    }

    private func collectEnvironmentalData(_ healthData: inout HealthData) async {
        // Environmental Audio Exposure
        if let audioType = HKQuantityType.quantityType(forIdentifier: .environmentalAudioExposure) {
            // Environmental audio exposure is stored in dBASPL (A-weighted Sound Pressure Level)
            let unit = HKUnit(from: "dBASPL")
            healthData.environmentalAudioExposure = await getLatestQuantitySample(for: audioType, unit: unit)
        }
    }

    private func collectWorkoutData(_ healthData: inout HealthData) async {
        // Check for active workouts
        let workoutType = HKObjectType.workoutType()
        let now = Date()
        let oneHourAgo = now.addingTimeInterval(-3600) // Check last hour for active workouts

        let predicate = HKQuery.predicateForSamples(withStart: oneHourAgo, end: now, options: .strictStartDate)

        let workoutResult = await withCheckedContinuation { (continuation: CheckedContinuation<(Bool, String?), Never>) in
            let query = HKSampleQuery(sampleType: workoutType, predicate: predicate, limit: 1, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, _ in

                if let workout = samples?.first as? HKWorkout,
                   workout.endDate > now.addingTimeInterval(-300) { // Active if ended less than 5 minutes ago
                    continuation.resume(returning: (true, workout.workoutActivityType.displayName))
                } else {
                    continuation.resume(returning: (false, nil))
                }
            }

            healthStore.execute(query)
        }

        healthData.isInWorkout = workoutResult.0
        healthData.workoutType = workoutResult.1
    }

    private func collectSleepData(_ healthData: inout HealthData) async {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return }

        let calendar = Calendar.current
        let now = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let startOfYesterday = calendar.startOfDay(for: yesterday)

        let predicate = HKQuery.predicateForSamples(withStart: startOfYesterday, end: now, options: .strictStartDate)

        let sleepResult = await withCheckedContinuation { (continuation: CheckedContinuation<(String?, Double?, Double?), Never>) in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, _ in

                guard let sleepSamples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: (nil, nil, nil))
                    return
                }

                var totalTimeInBed: TimeInterval = 0
                var totalTimeAsleep: TimeInterval = 0
                var sleepAnalysis = "No sleep data"

                for sample in sleepSamples {
                    let duration = sample.endDate.timeIntervalSince(sample.startDate)

                    switch sample.value {
                    case HKCategoryValueSleepAnalysis.inBed.rawValue:
                        totalTimeInBed += duration
                    case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                         HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                         HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                         HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                        totalTimeAsleep += duration
                    default:
                        break
                    }
                }

                if totalTimeAsleep > 0 {
                    let hours = Int(totalTimeAsleep / 3600)
                    let minutes = Int((totalTimeAsleep.truncatingRemainder(dividingBy: 3600)) / 60)
                    sleepAnalysis = "Last night: \(hours)h \(minutes)m"
                }

                continuation.resume(returning: (sleepAnalysis, totalTimeInBed / 3600, totalTimeAsleep / 3600))
            }

            healthStore.execute(query)
        }

        healthData.sleepAnalysis = sleepResult.0
        healthData.timeInBed = sleepResult.1
        healthData.timeAsleep = sleepResult.2
    }

    private func collectMindfulnessData(_ healthData: inout HealthData) async {
        guard let mindfulnessType = HKObjectType.categoryType(forIdentifier: .mindfulSession) else { return }

        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)

        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

        healthData.mindfulnessMinutes = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: mindfulnessType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in

                guard let mindfulSamples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: nil)
                    return
                }

                let totalMinutes = mindfulSamples.reduce(0.0) { total, sample in
                    let duration = sample.endDate.timeIntervalSince(sample.startDate)
                    return total + (duration / 60.0)
                }

                continuation.resume(returning: totalMinutes > 0 ? totalMinutes : nil)
            }

            healthStore.execute(query)
        }
    }

    private func collectWatchHardwareData(_ healthData: inout HealthData) async {
        // This would require WatchConnectivity to get real data from the watch
        // For now, we'll use simulated data
        let watchConnectivity = WatchConnectivityService.shared

        if watchConnectivity.isWatchConnected {
            // In a real implementation, you would request this data from the watch
            healthData.watchBatteryLevel = 0.75 // Simulated
            healthData.watchOrientation = "Portrait" // Simulated
            healthData.crownPosition = "Right" // Simulated
        }
    }

    private func getLatestQuantitySample(for quantityType: HKQuantityType, unit: HKUnit) async -> Double? {
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: quantityType, predicate: nil, limit: 1, sortDescriptors: [sortDescriptor]) { _, samples, error in

                if let error = error {
                    print("❌ HealthKit query error for \(quantityType.identifier): \(error)")
                    continuation.resume(returning: nil)
                    return
                }

                if let sample = samples?.first as? HKQuantitySample {
                    let value = sample.quantity.doubleValue(for: unit)
                    continuation.resume(returning: value)
                } else {
                    continuation.resume(returning: nil)
                }
            }

            healthStore.execute(query)
        }
    }

    private func getTodaySum(for quantityType: HKQuantityType, unit: HKUnit, since startDate: Date) async -> Double? {
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date(), options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: quantityType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, error in

                if let error = error {
                    print("❌ HealthKit statistics query error for \(quantityType.identifier): \(error)")
                    continuation.resume(returning: nil)
                    return
                }

                if let sum = statistics?.sumQuantity() {
                    let value = sum.doubleValue(for: unit)
                    continuation.resume(returning: value)
                } else {
                    continuation.resume(returning: nil)
                }
            }

            healthStore.execute(query)
        }
    }
}

// MARK: - Supporting Types

enum HealthKitError: Error {
    case notAvailable
    case authorizationDenied
    case noData
}

extension HKWorkoutActivityType {
    var displayName: String {
        switch self {
        case .running: return "Running"
        case .walking: return "Walking"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .yoga: return "Yoga"
        case .traditionalStrengthTraining: return "Strength Training"
        case .hiking: return "Hiking"
        case .dance: return "Dance"
        case .soccer: return "Soccer"
        case .basketball: return "Basketball"
        case .tennis: return "Tennis"
        case .golf: return "Golf"
        default: return "Workout"
        }
    }
}

extension HealthData {
    func formatForDisplay() -> [HealthDisplayItem] {
        var items: [HealthDisplayItem] = []

        // Heart Rate section
        var heartItems: [(String, String)] = []
        if let hr = heartRate {
            heartItems.append(("Current HR", "\(Int(hr)) BPM"))
        }
        if let restingHR = restingHeartRate {
            heartItems.append(("Resting HR", "\(Int(restingHR)) BPM"))
        }
        if let walkingHR = walkingHeartRateAverage {
            heartItems.append(("Walking HR Avg", "\(Int(walkingHR)) BPM"))
        }
        if let hrv = heartRateVariability {
            heartItems.append(("HRV", "\(String(format: "%.1f", hrv)) ms"))
        }
        if !heartItems.isEmpty {
            items.append(HealthDisplayItem(category: "Heart", items: heartItems))
        }

        // Activity section
        var activityItems: [(String, String)] = []
        if let energy = activeEnergyBurned {
            activityItems.append(("Active Energy", "\(Int(energy)) kcal"))
        }
        if let steps = stepCount {
            activityItems.append(("Steps", "\(Int(steps))"))
        }
        if let distance = distanceWalkingRunning {
            activityItems.append(("Distance", "\(String(format: "%.2f", distance/1000)) km"))
        }
        if let flights = flightsClimbed {
            activityItems.append(("Flights", "\(Int(flights))"))
        }
        if let exerciseTime = appleExerciseTime {
            activityItems.append(("Exercise Time", "\(Int(exerciseTime)) min"))
        }
        if let standHours = appleStandHours {
            activityItems.append(("Stand Time", "\(Int(standHours)) min"))
        }
        if !activityItems.isEmpty {
            items.append(HealthDisplayItem(category: "Activity", items: activityItems))
        }

        // Health Metrics section
        var healthItems: [(String, String)] = []
        if let oxygen = oxygenSaturation {
            healthItems.append(("Blood Oxygen", "\(String(format: "%.1f", oxygen*100))%"))
        }
        if let temp = bodyTemperature {
            healthItems.append(("Body Temperature", "\(String(format: "%.1f", temp))°C"))
        }
        if let respiratory = respiratoryRate {
            healthItems.append(("Respiratory Rate", "\(Int(respiratory)) BPM"))
        }
        if !healthItems.isEmpty {
            items.append(HealthDisplayItem(category: "Health", items: healthItems))
        }

        // Environmental section
        var envItems: [(String, String)] = []
        if let audio = environmentalAudioExposure {
            envItems.append(("Audio Exposure", "\(String(format: "%.1f", audio)) dB"))
        }
        if !envItems.isEmpty {
            items.append(HealthDisplayItem(category: "Environment", items: envItems))
        }


        // Mindfulness section
        var mindfulnessItems: [(String, String)] = []
        if let mindfulness = mindfulnessMinutes {
            mindfulnessItems.append(("Mindfulness Today", "\(Int(mindfulness)) min"))
        }
        if !mindfulnessItems.isEmpty {
            items.append(HealthDisplayItem(category: "Mindfulness", items: mindfulnessItems))
        }



        return items
    }
}

struct HealthDisplayItem {
    let category: String
    let items: [(String, String)]
}