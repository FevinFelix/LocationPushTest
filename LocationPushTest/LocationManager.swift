import CoreLocation
import Combine
import Firebase

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private var locationManager = CLLocationManager()
    @Published var currentLocation: CLLocation?
    private var locationDataBatch: [[String: Any]] = []
    private let batchSize = 20 // Change this to your desired batch size
    private var isSendingLocation = false
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var previousLocation: CLLocation?
    private var locationTimer: Timer?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = kCLDistanceFilterNone
        
        // Enable battery monitoring
        UIDevice.current.isBatteryMonitoringEnabled = true

        // Request location permissions
        requestLocationAuthorization()
        
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.showsBackgroundLocationIndicator = true
        locationManager.pausesLocationUpdatesAutomatically = false
        
        // Configure Firebase
        FirebaseApp.configure()
    }

    func startBackgroundTaskIfNeeded() {
        if backgroundTask == .invalid {
            startBackgroundTask()
        }
    }

    func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
    
    private func startBackgroundTask() {
        backgroundTask = UIApplication.shared.beginBackgroundTask {
            self.endBackgroundTask()
        }
    }

    private func requestLocationAuthorization() {
        locationManager.requestAlwaysAuthorization() // Request always authorization for background updates
        locationManager.allowsBackgroundLocationUpdates = true
    }

    func startUpdatingLocation() {
        isSendingLocation = true
        locationManager.startUpdatingLocation()
        
        // Start background task
        startBackgroundTask()

        // Start the timer to update location every second
        locationTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(updateLocationEverySecond), userInfo: nil, repeats: true)
    }

    func stopUpdatingLocation() {
        isSendingLocation = false
        locationManager.stopUpdatingLocation()
        locationTimer?.invalidate()
        endBackgroundTask()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location
        previousLocation = location // Update the previous location with the latest
    }

    @objc private func updateLocationEverySecond() {
        if let currentLocation = currentLocation {
            // If a new location is available, use it
            appendToBatch(location: currentLocation)
        } else if let previousLocation = previousLocation {
            // If no new location is available, reuse the previous one
            appendToBatch(location: previousLocation)
        }
        
        // Force a refresh for the next second
        locationManager.startUpdatingLocation()
    }

    private func appendToBatch(location: CLLocation) {
        let localTimestamp = Timestamp(date: Date())
        let locationData: [String: Any] = [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "altitude": location.altitude,
            "batteryLevel": UIDevice.current.batteryLevel * 100, // Get battery level as a percentage
            "speed": location.speed,
            "timestamp": localTimestamp
        ]

        locationDataBatch.append(locationData)

        // Check if batch size is met
        if locationDataBatch.count >= batchSize {
            sendBatchToFirestore()
        }
    }

    private func sendBatchToFirestore() {
        guard !locationDataBatch.isEmpty else { return }
        
        let db = Firestore.firestore()
        let batchDocument: [String: Any] = [
            "locations": locationDataBatch,
            "timestamp": Timestamp(date: Date())
        ]

        db.collection("locationBatches").addDocument(data: batchDocument) { [weak self] error in
            if let error = error {
                print("Error sending batch to Firestore: \(error)")
            } else {
                print("Batch data successfully sent to Firestore!")
                self?.locationDataBatch.removeAll() // Clear the batch after sending
            }
            self?.endBackgroundTask() // End background task
        }
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            if isSendingLocation {
                startUpdatingLocation()
            }
        case .denied, .restricted:
            print("Location access denied or restricted.")
        case .notDetermined:
            requestLocationAuthorization()
        @unknown default:
            break
        }
    }
}
