//
//  NeighborhoodSafetyService.swift
//  discreetly
//
//  Service for monitoring neighborhood safety based on location changes
//

import Foundation
import CoreLocation
import UserNotifications
import Combine

final class NeighborhoodSafetyService: NSObject, ObservableObject {
    static let shared = NeighborhoodSafetyService()

    @Published private(set) var currentNeighborhood: String?
    @Published private(set) var currentSafetyStatus: SafetyStatus = .unknown
    @Published private(set) var currentSafetyInfo: NeighborhoodSafetyInfo?
    @Published private(set) var lastSafetyCheck: Date?
    @Published private(set) var isMonitoring: Bool = false

    private let locationService = LocationService.shared
    private let claudeService = ClaudeService.shared
    private var cancellables = Set<AnyCancellable>()
    private var lastKnownNeighborhood: String?
    private var lastLocationCheck: CLLocation?
    private let minimumDistanceForCheck: CLLocationDistance = 500 // 500 meters
    private let safetyCheckCooldown: TimeInterval = 300 // 5 minutes between checks

    enum SafetyStatus: String, Codable {
        case safe = "safe"
        case unsafe = "unsafe"
        case moderatelyUnsafe = "moderately_unsafe"
        case unknown = "unknown"

        var description: String {
            switch self {
            case .safe:
                return "Safe"
            case .unsafe:
                return "Unsafe"
            case .moderatelyUnsafe:
                return "Moderately Unsafe"
            case .unknown:
                return "Unknown"
            }
        }

        var shouldNotify: Bool {
            return self == .unsafe || self == .moderatelyUnsafe
        }
    }

    struct NeighborhoodSafetyInfo: Codable {
        let neighborhood: String
        let safetyStatus: SafetyStatus
        let safetyScore: Int // 1-10 scale
        let reasons: [String]
        let recommendations: [String]
        let timestamp: Date

        init(neighborhood: String, safetyStatus: SafetyStatus, safetyScore: Int, reasons: [String], recommendations: [String]) {
            self.neighborhood = neighborhood
            self.safetyStatus = safetyStatus
            self.safetyScore = safetyScore
            self.reasons = reasons
            self.recommendations = recommendations
            self.timestamp = Date()
        }
    }

    override init() {
        super.init()
        setupLocationMonitoring()
    }

    private func setupLocationMonitoring() {
        locationService.$currentLocation
            .compactMap { $0 }
            .sink { [weak self] location in
                self?.handleLocationUpdate(location)
            }
            .store(in: &cancellables)
    }

    private func handleLocationUpdate(_ location: CLLocation) {
        guard isMonitoring else { return }

        // Check if we've moved far enough or enough time has passed to warrant a new safety check
        guard shouldPerformSafetyCheck(for: location) else { return }

        Task {
            await checkNeighborhoodSafety(location: location)
        }
    }

    private func shouldPerformSafetyCheck(for location: CLLocation) -> Bool {
        // Check distance threshold
        if let lastLocation = lastLocationCheck {
            let distance = location.distance(from: lastLocation)
            if distance < minimumDistanceForCheck {
                return false
            }
        }

        // Check time threshold
        if let lastCheck = lastSafetyCheck {
            let timeSinceLastCheck = Date().timeIntervalSince(lastCheck)
            if timeSinceLastCheck < safetyCheckCooldown {
                return false
            }
        }

        return true
    }

    func startMonitoring() {
        guard !isMonitoring else { return }

        isMonitoring = true

        // Request always authorization for background location monitoring
        locationService.requestAlwaysAuthorization()
        locationService.startUpdating()

        print("🛡️ Neighborhood safety monitoring started")
    }

    func stopMonitoring() {
        isMonitoring = false
        locationService.stopUpdating()
        print("🛡️ Neighborhood safety monitoring stopped")
    }

    @MainActor
    private func checkNeighborhoodSafety(location: CLLocation) async {
        lastLocationCheck = location

        do {
            let neighborhood = await getNeighborhoodName(for: location)
            currentNeighborhood = neighborhood

            // Only check safety if we've entered a new neighborhood
            if neighborhood != lastKnownNeighborhood {
                print("🏘️ Entered new neighborhood: \(neighborhood)")

                let safetyInfo = try await assessNeighborhoodSafety(neighborhood: neighborhood, location: location)

                currentSafetyStatus = safetyInfo.safetyStatus
                currentSafetyInfo = safetyInfo
                lastSafetyCheck = Date()
                lastKnownNeighborhood = neighborhood

                print("🛡️ Safety assessment for \(neighborhood): \(safetyInfo.safetyStatus.description)")

                // Update the current safety information for UI display
                // No notification needed - will be shown on home screen
            }
        } catch {
            print("❌ Error checking neighborhood safety: \(error.localizedDescription)")
        }
    }

    private func getNeighborhoodName(for location: CLLocation) async -> String {
        return await withCheckedContinuation { continuation in
            let geocoder = CLGeocoder()
            geocoder.reverseGeocodeLocation(location) { placemarks, error in
                if let placemark = placemarks?.first {
                    // Try to get the most specific neighborhood identifier
                    let neighborhood = placemark.subLocality ??
                                     placemark.locality ??
                                     placemark.subAdministrativeArea ??
                                     placemark.administrativeArea ??
                                     "Unknown Area"
                    continuation.resume(returning: neighborhood)
                } else {
                    continuation.resume(returning: "Unknown Area")
                }
            }
        }
    }

    private func assessNeighborhoodSafety(neighborhood: String, location: CLLocation) async throws -> NeighborhoodSafetyInfo {
        let prompt = """
        Assess the safety of the neighborhood "\(neighborhood)" located at coordinates \(location.coordinate.latitude), \(location.coordinate.longitude).

        IMPORTANT: Respond ONLY with valid JSON in this exact format. Do not include any other text before or after the JSON:

        {
            "safetyStatus": "safe",
            "safetyScore": 8,
            "reasons": ["Well-lit area", "High foot traffic", "Near police station"],
            "recommendations": ["Stay aware of surroundings", "Keep valuables secure"]
        }

        Rules:
        - safetyStatus must be exactly one of: "safe", "moderately_unsafe", "unsafe"
        - safetyScore must be a number from 1-10 (where 10 is safest)
        - reasons and recommendations must be arrays of strings (2-4 items each)
        - Use current time context: \(Date().formatted())

        Consider: crime rates, lighting, foot traffic, time of day, proximity to emergency services, general area reputation.
        """

        let response = try await claudeService.askQuestion(prompt)

        // Extract JSON from the response (Claude might return text with JSON embedded)
        let jsonString = extractJSONFromResponse(response)

        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("❌ Failed to parse JSON from response: \(response)")
            // Fallback to basic assessment if JSON parsing fails
            return createFallbackSafetyInfo(neighborhood: neighborhood)
        }

        let safetyStatusString = json["safetyStatus"] as? String ?? "unknown"
        let safetyStatus = SafetyStatus(rawValue: safetyStatusString) ?? .unknown
        let safetyScore = json["safetyScore"] as? Int ?? 5
        let reasons = json["reasons"] as? [String] ?? ["Assessment unavailable"]
        let recommendations = json["recommendations"] as? [String] ?? ["Stay alert and aware of your surroundings"]

        return NeighborhoodSafetyInfo(
            neighborhood: neighborhood,
            safetyStatus: safetyStatus,
            safetyScore: safetyScore,
            reasons: reasons,
            recommendations: recommendations
        )
    }

    private func extractJSONFromResponse(_ response: String) -> String {
        // Look for JSON block in the response
        if let startRange = response.range(of: "{"),
           let endRange = response.range(of: "}", options: .backwards) {
            let jsonRange = startRange.lowerBound..<response.index(after: endRange.lowerBound)
            return String(response[jsonRange])
        }

        // If no JSON block found, return the whole response (might be pure JSON)
        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func createFallbackSafetyInfo(neighborhood: String) -> NeighborhoodSafetyInfo {
        return NeighborhoodSafetyInfo(
            neighborhood: neighborhood,
            safetyStatus: .unknown,
            safetyScore: 5,
            reasons: ["Safety assessment temporarily unavailable"],
            recommendations: ["Stay alert and aware of your surroundings", "Trust your instincts"]
        )
    }


    // Manual safety check for current location
    func performManualSafetyCheck() async {
        guard let location = locationService.currentLocation else {
            print("❌ No current location available for safety check")
            return
        }

        await checkNeighborhoodSafety(location: location)
    }

    // Get current safety information
    func getCurrentSafetyInfo() -> (neighborhood: String?, status: SafetyStatus, lastCheck: Date?) {
        return (currentNeighborhood, currentSafetyStatus, lastSafetyCheck)
    }
}

enum SafetyAssessmentError: LocalizedError {
    case invalidResponse
    case networkError
    case locationUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from safety assessment service"
        case .networkError:
            return "Network error during safety assessment"
        case .locationUnavailable:
            return "Location not available for safety assessment"
        }
    }
}