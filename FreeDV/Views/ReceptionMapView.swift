import SwiftUI
import MapKit
import SwiftData

/// Map view showing reception locations from logged sessions.
/// Green markers = callsign decoded, yellow = session start (no callsign at that point).
struct ReceptionMapView: View {
    @Query(sort: \ReceptionSession.startTime, order: .reverse) private var sessions: [ReceptionSession]
    
    var body: some View {
        Map {
            // Session start locations
            ForEach(sessionsWithLocation, id: \.id) { session in
                if let lat = session.startLatitude, let lon = session.startLongitude {
                    Annotation(
                        sessionLabel(session),
                        coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    ) {
                        SessionMapPin(session: session)
                    }
                }
            }
            
            // Callsign decode locations
            ForEach(callsignAnnotations, id: \.id) { annotation in
                Annotation(
                    annotation.callsign,
                    coordinate: annotation.coordinate
                ) {
                    CallsignMapPin(callsign: annotation.callsign, snr: annotation.snr)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .overlay(alignment: .bottom) {
            if sessionsWithLocation.isEmpty && callsignAnnotations.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "location.slash")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No location data yet")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Enable GPS tracking in Settings\nand start receiving to record locations")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding()
            }
        }
        .navigationTitle("Reception Map")
    }
    
    // MARK: - Data
    
    private var sessionsWithLocation: [ReceptionSession] {
        sessions.filter { $0.startLatitude != nil && $0.startLongitude != nil }
    }
    
    private struct CallsignAnnotation: Identifiable {
        let id: UUID
        let callsign: String
        let snr: Float
        let coordinate: CLLocationCoordinate2D
    }
    
    private var callsignAnnotations: [CallsignAnnotation] {
        sessions.flatMap { session in
            session.callsignEvents.compactMap { event in
                guard let lat = event.latitude, let lon = event.longitude else { return nil }
                return CallsignAnnotation(
                    id: event.id,
                    callsign: event.callsign,
                    snr: event.snrAtDecode,
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)
                )
            }
        }
    }
    
    private func sessionLabel(_ session: ReceptionSession) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d HH:mm"
        return formatter.string(from: session.startTime)
    }
}

// MARK: - Map Pins

struct SessionMapPin: View {
    let session: ReceptionSession
    
    private var callsigns: [String] {
        guard session.modelContext != nil else { return [] }
        return session.callsignsDecoded
    }

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .padding(6)
                .background(callsigns.isEmpty ? Color.yellow : Color.green)
                .clipShape(Circle())

            if !callsigns.isEmpty {
                Text(callsigns.first ?? "")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.green)
            }
        }
    }
}

struct CallsignMapPin: View {
    let callsign: String
    let snr: Float
    
    var body: some View {
        VStack(spacing: 2) {
            Text(callsign)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(snrColor)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            
            Text(String(format: "%.0f dB", snr))
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
    
    private var snrColor: Color {
        if snr > 10 { return .green }
        if snr > 4 { return .yellow }
        return .orange
    }
}
