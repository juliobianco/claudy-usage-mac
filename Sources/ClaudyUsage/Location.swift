import CoreLocation
import Foundation

/// Where the weather is for. CoreLocation (asked once, kept in UserDefaults) instead of the original's IP lookup,
/// so no third party learns the IP. A place typed in the settings wins (Prefs.manualPlace).
@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let mgr = CLLocationManager()
    var onFix: ((Double, Double) -> Void)?

    /// The last fix, or nil until the first one arrives.
    static var saved: (lat: Double, lon: Double)? {
        let d = UserDefaults.standard
        if let la = d.object(forKey: "lastLat") as? Double, let lo = d.object(forKey: "lastLon") as? Double { return (la, lo) }
        return nil
    }

    func start() {
        mgr.delegate = self
        mgr.desiredAccuracy = kCLLocationAccuracyKilometer      // a city is plenty for the weather
        if mgr.authorizationStatus == .notDetermined { mgr.requestWhenInUseAuthorization() }
        else { mgr.requestLocation() }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        if m.authorizationStatus == .authorizedAlways || m.authorizationStatus == .authorized { m.requestLocation() }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        guard let l = locs.last else { return }
        let (la, lo) = (l.coordinate.latitude, l.coordinate.longitude)
        Task { @MainActor in
            UserDefaults.standard.set(la, forKey: "lastLat"); UserDefaults.standard.set(lo, forKey: "lastLon")
            self.onFix?(la, lo)
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {}
}
