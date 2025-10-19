//
//  LocationService.swift
//  discreetly
//
//  Service for location tracking and sharing
//

import Foundation
import CoreLocation
import Combine
import MapKit

final class LocationService: NSObject, ObservableObject {
    static let shared = LocationService()

    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var locationError: Error?
    @Published private(set) var currentLocationName: String?

    private let locationManager: CLLocationManager
    private let geocoder = CLGeocoder()
    private var locationContinuations: [UUID: CheckedContinuation<CLLocation, Error>] = [:]
    private let continuationQueue = DispatchQueue(label: "locationContinuations", attributes: .concurrent)

    override init() {
        locationManager = CLLocationManager()
        authorizationStatus = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }

    /// Request location permissions
    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    /// Request always authorization for background mode
    func requestAlwaysAuthorization() {
        locationManager.requestAlwaysAuthorization()
    }

    /// Get current location (one-time)
    func getCurrentLocation() async throws -> CLLocation {
        // If we already have a recent location (within 30 seconds), return it
        if let currentLocation = currentLocation,
           currentLocation.timestamp.timeIntervalSinceNow > -30 {
            return currentLocation
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let requestId = UUID()
            
            continuationQueue.async(flags: .barrier) {
                self.locationContinuations[requestId] = continuation
            }
            
            // Start location request
            locationManager.requestLocation()
        }
    }

    /// Start continuous location updates
    func startUpdating() {
        locationManager.startUpdatingLocation()
    }

    /// Stop location updates
    func stopUpdating() {
        locationManager.stopUpdatingLocation()
    }

    /// Format location as shareable URL
    func getShareableLocationURL(from location: CLLocation) -> URL? {
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        return URL(string: "https://maps.google.com/?q=\(lat),\(lon)")
    }

    /// Get human-readable location name using reverse geocoding
    func getLocationName(from location: CLLocation) async -> String {
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else {
                return "Unknown location"
            }

            var components: [String] = []

            if let name = placemark.name {
                components.append(name)
            }
            if let thoroughfare = placemark.thoroughfare {
                components.append(thoroughfare)
            }
            if let locality = placemark.locality {
                components.append(locality)
            }
            if let administrativeArea = placemark.administrativeArea {
                components.append(administrativeArea)
            }

            return components.joined(separator: ", ")
        } catch {
            print("Reverse geocoding failed: \(error)")
            return "Location unavailable"
        }
    }

    /// Format location as human-readable text with address
    func getLocationText(from location: CLLocation) async -> String {
        let locationName = await getLocationName(from: location)
        let accuracy = String(format: "±%.0fm", location.horizontalAccuracy)
        return "Location: \(locationName) (Accuracy: \(accuracy))\nhttps://maps.google.com/?q=\(location.coordinate.latitude),\(location.coordinate.longitude)"
    }

    /// Format location as text (legacy synchronous method)
    func getLocationText(from location: CLLocation) -> String {
        let lat = String(format: "%.6f", location.coordinate.latitude)
        let lon = String(format: "%.6f", location.coordinate.longitude)
        let accuracy = String(format: "±%.0fm", location.horizontalAccuracy)
        return "Location: \(lat), \(lon) (Accuracy: \(accuracy))\nhttps://maps.google.com/?q=\(lat),\(lon)"
    }
}

// MARK: - CLLocationManagerDelegate
extension LocationService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        DispatchQueue.main.async {
            self.currentLocation = location
        }

        // Update location name asynchronously
        Task {
            let locationName = await self.getLocationName(from: location)
            DispatchQueue.main.async {
                self.currentLocationName = locationName
            }
        }

        // Resolve all waiting continuations
        continuationQueue.async(flags: .barrier) {
            let continuations = self.locationContinuations
            self.locationContinuations.removeAll()

            for (_, continuation) in continuations {
                continuation.resume(returning: location)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.locationError = error
        }

        // Resolve all waiting continuations with error
        continuationQueue.async(flags: .barrier) {
            let continuations = self.locationContinuations
            self.locationContinuations.removeAll()
            
            for (_, continuation) in continuations {
                continuation.resume(throwing: error)
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authorizationStatus = manager.authorizationStatus
        }
    }
}
