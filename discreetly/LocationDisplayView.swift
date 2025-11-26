//
//  LocationDisplayView.swift
//  discreetly
//
//  SwiftUI view for displaying location with human-readable address instead of coordinates
//

import SwiftUI
import MapKit
import CoreLocation

struct LocationDisplayView: View {
    @ObservedObject private var locationService = LocationService.shared
    let location: CLLocation?
    let showMap: Bool

    init(location: CLLocation? = nil, showMap: Bool = true) {
        self.location = location
        self.showMap = showMap
    }

    private var displayLocation: CLLocation? {
        location ?? locationService.currentLocation
    }

    private var displayLocationName: String {
        if let name = locationService.currentLocationName, !name.isEmpty {
            return name
        }
        return "Location unavailable"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let location = displayLocation {
                HStack {
                    Image(systemName: "location.fill")
                        .foregroundColor(.blue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayLocationName)
                            .font(.body)
                            .foregroundColor(.primary)

                        if location.horizontalAccuracy >= 0 {
                            Text("Accuracy: ±\(Int(location.horizontalAccuracy))m")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    Button(action: {
                        openInMaps(location: location)
                    }) {
                        Image(systemName: "map")
                            .foregroundColor(.blue)
                    }
                }

                if showMap {
                    MapView(location: location)
                        .frame(height: 200)
                        .cornerRadius(12)
                }
            } else {
                HStack {
                    Image(systemName: "location.slash")
                        .foregroundColor(.gray)

                    Text("Location unavailable")
                        .font(.body)
                        .foregroundColor(.secondary)

                    Spacer()
                }
            }
        }
    }

    private func openInMaps(location: CLLocation) {
        let coordinate = location.coordinate
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        mapItem.name = displayLocationName
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsMapTypeKey: MKMapType.standard.rawValue
        ])
    }
}

struct MapView: UIViewRepresentable {
    let location: CLLocation

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.isUserInteractionEnabled = true
        mapView.showsUserLocation = false
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let coordinate = location.coordinate
        let region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 1000,
            longitudinalMeters: 1000
        )

        mapView.setRegion(region, animated: true)

        // Remove existing annotations
        mapView.removeAnnotations(mapView.annotations)

        // Add annotation for the location
        let annotation = MKPointAnnotation()
        annotation.coordinate = coordinate
        annotation.title = "Current Location"
        mapView.addAnnotation(annotation)
    }
}

#Preview {
    LocationDisplayView(
        location: CLLocation(latitude: 37.7749, longitude: -122.4194),
        showMap: true
    )
    .padding()
}