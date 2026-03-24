import WidgetKit
import SwiftUI

/// Timeline entry for FreeDV home screen widget.
struct FreeDVWidgetEntry: TimelineEntry {
    let date: Date
    let isRunning: Bool
    let syncState: Int
    let snr: Float
    let lastCallsign: String
    let decodedCount: Int
    let frequencyMHz: String
    let lastUpdate: String
    let todayCallsigns: [String]
}

/// Timeline provider reads shared state from App Group UserDefaults.
struct FreeDVWidgetProvider: TimelineProvider {
    
    func placeholder(in context: Context) -> FreeDVWidgetEntry {
        FreeDVWidgetEntry(
            date: Date(),
            isRunning: true,
            syncState: 2,
            snr: 14,
            lastCallsign: "VK5DGR",
            decodedCount: 5,
            frequencyMHz: "14.236",
            lastUpdate: "Just now",
            todayCallsigns: ["VK5DGR", "K1ABC", "W5XX"]
        )
    }
    
    func getSnapshot(in context: Context, completion: @escaping (FreeDVWidgetEntry) -> Void) {
        completion(currentEntry())
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<FreeDVWidgetEntry>) -> Void) {
        let entry = currentEntry()
        // Refresh every 5 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
    
    private func currentEntry() -> FreeDVWidgetEntry {
        WidgetSharedState.resetDailyCountIfNeeded()
        return FreeDVWidgetEntry(
            date: Date(),
            isRunning: WidgetSharedState.isRunning,
            syncState: WidgetSharedState.syncState,
            snr: WidgetSharedState.snr,
            lastCallsign: WidgetSharedState.lastCallsign,
            decodedCount: WidgetSharedState.decodedCount,
            frequencyMHz: WidgetSharedState.frequencyMHz,
            lastUpdate: WidgetSharedState.lastUpdateRelative,
            todayCallsigns: WidgetSharedState.todayCallsigns
        )
    }
}

// MARK: - Small Widget

struct FreeDVSmallWidgetView: View {
    let entry: FreeDVWidgetEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 12))
                Text("FreeDV")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(.secondary)
            
            HStack(spacing: 4) {
                Circle()
                    .fill(syncColor(entry.syncState))
                    .frame(width: 10, height: 10)
                Text(syncText(entry.syncState))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
            }
            
            Text(String(format: "SNR: %+.0f dB", entry.snr))
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(snrColor(entry.snr))
            
            if !entry.lastCallsign.isEmpty {
                Text(entry.lastCallsign)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(.green)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.black, for: .widget)
    }
}

// MARK: - Medium Widget

struct FreeDVMediumWidgetView: View {
    let entry: FreeDVWidgetEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 12))
                Text("FreeDV SWL")
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                Text(entry.frequencyMHz + " MHz")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            
            HStack(spacing: 12) {
                // Sync + SNR
                HStack(spacing: 4) {
                    Circle()
                        .fill(syncColor(entry.syncState))
                        .frame(width: 10, height: 10)
                    Text(syncText(entry.syncState))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                }
                
                Text(String(format: "%+.0f dB", entry.snr))
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(snrColor(entry.snr))
                
                Spacer()
            }
            
            HStack {
                if !entry.lastCallsign.isEmpty {
                    HStack(spacing: 4) {
                        Text("Last:")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(entry.lastCallsign)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(.green)
                    }
                }
                Spacer()
                Text(entry.lastUpdate)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            
            Text("Today: \(entry.decodedCount) callsigns")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.black, for: .widget)
    }
}

// MARK: - Large Widget

struct FreeDVLargeWidgetView: View {
    let entry: FreeDVWidgetEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 14))
                Text("FreeDV SWL")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Text(entry.frequencyMHz + " MHz")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            
            // Status row
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(syncColor(entry.syncState))
                        .frame(width: 12, height: 12)
                    Text(syncText(entry.syncState))
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                }
                
                HStack(spacing: 2) {
                    Text("SNR")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(String(format: "%+.0f dB", entry.snr))
                        .font(.system(size: 17, weight: .bold, design: .monospaced))
                        .foregroundStyle(snrColor(entry.snr))
                }
                
                Spacer()
            }
            
            Divider().background(Color.gray.opacity(0.3))
            
            // Today's callsigns
            VStack(alignment: .leading, spacing: 4) {
                Text("Today's Callsigns (\(entry.decodedCount))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                
                if entry.todayCallsigns.isEmpty {
                    Text("No callsigns decoded yet")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                } else {
                    // Show recent callsigns (last 8)
                    let recent = Array(entry.todayCallsigns.suffix(8))
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                        ForEach(recent, id: \.self) { callsign in
                            Text(callsign)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(.green)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            
            Spacer()
            
            // Footer
            HStack {
                Text(entry.isRunning ? "Receiving" : "Idle")
                    .font(.system(size: 10))
                    .foregroundStyle(entry.isRunning ? .green : .secondary)
                Spacer()
                Text("Updated: \(entry.lastUpdate)")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.black, for: .widget)
    }
}

// MARK: - Widget Definition

struct FreeDVWidget: Widget {
    let kind: String = "FreeDVWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FreeDVWidgetProvider()) { entry in
            switch entry.date {  // Hack: just use view size based on family
            default:
                FreeDVMediumWidgetView(entry: entry)
            }
        }
        .configurationDisplayName("FreeDV SWL")
        .description("Monitor your FreeDV RADE receiver status.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Helpers

private func syncColor(_ state: Int) -> Color {
    switch state {
    case 2: return .green
    case 1: return .yellow
    default: return .red
    }
}

private func syncText(_ state: Int) -> String {
    switch state {
    case 2: return "SYNC"
    case 1: return "CAND"
    default: return "SRCH"
    }
}

private func snrColor(_ snr: Float) -> Color {
    if snr > 6 { return .green }
    if snr > 2 { return .yellow }
    return .red
}
