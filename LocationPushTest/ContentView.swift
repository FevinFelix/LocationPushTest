import SwiftUI
import CoreLocation

struct ContentView: View {
    @StateObject private var locationManager = LocationManager()
    @State private var isSendingLocation = false

    var body: some View {
        VStack {
            Toggle("Send Location", isOn: $isSendingLocation)
                .onChange(of: isSendingLocation) { oldValue, newValue in
                    if newValue {
                        locationManager.startUpdatingLocation()
                    } else {
                        locationManager.stopUpdatingLocation()
                    }
                }
                .padding()

            if let location = locationManager.currentLocation {
                Text("Latitude: \(location.coordinate.latitude), Longitude: \(location.coordinate.longitude)")
            } else {
                Text("Fetching location...")
            }
        }
        .padding()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
