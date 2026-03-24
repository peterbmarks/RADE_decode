import CoreLocation

/// Low-power GPS tracker for reception logging.
/// Provides current location during RX sessions with minimal battery impact.
class LocationTracker: NSObject, CLLocationManagerDelegate {
    
    private let manager = CLLocationManager()
    
    /// Most recent location (updated on significant movement)
    private(set) var currentLocation: CLLocation?
    
    /// Whether tracking is actively running
    private(set) var isTracking = false
    
    /// User preference for GPS tracking
    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "gpsTrackingEnabled") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "gpsTrackingEnabled") }
    }
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters  // Low power
        manager.distanceFilter = 100  // Only update on 100m movement
        manager.activityType = .other
        manager.pausesLocationUpdatesAutomatically = true
    }
    
    /// Start tracking when RX begins (if enabled and authorized).
    func startTracking() {
        guard isEnabled else { return }
        
        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
            return
        }
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            appLog("LocationTracker: not authorized (status=\(status.rawValue))")
            return
        }
        
        manager.startUpdatingLocation()
        isTracking = true
        appLog("LocationTracker: started")
    }
    
    /// Stop tracking when RX stops.
    func stopTracking() {
        manager.stopUpdatingLocation()
        isTracking = false
        appLog("LocationTracker: stopped")
    }
    
    /// Current latitude or nil
    var latitude: Double? { currentLocation?.coordinate.latitude }
    
    /// Current longitude or nil
    var longitude: Double? { currentLocation?.coordinate.longitude }
    
    /// Current altitude or nil
    var altitude: Double? { currentLocation?.altitude }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if (manager.authorizationStatus == .authorizedWhenInUse ||
            manager.authorizationStatus == .authorizedAlways) && isEnabled {
            manager.startUpdatingLocation()
            isTracking = true
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        appLog("LocationTracker: error — \(error.localizedDescription)")
    }
}
