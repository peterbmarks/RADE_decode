import SwiftUI

/// In-app diagnostic log viewer with copy/share functionality.
struct LogView: View {
    @ObservedObject private var logManager = LogManager.shared
    @State private var autoScroll = true
    @State private var showPreviousSession = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Previous session crash log banner
            if !logManager.previousSessionLog.isEmpty && !showPreviousSession {
                Button {
                    showPreviousSession = true
                } label: {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text("Previous session log available")
                            .font(.system(size: 11))
                        Spacer()
                        Text("View")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.yellow.opacity(0.15))
                }
            }
            
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(logManager.lines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(lineColor(line))
                                .id(index)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .background(Color.black)
                .onChange(of: logManager.lines.count) {
                    if autoScroll, let last = logManager.lines.indices.last {
                        withAnimation(.none) {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
            }
            
            // Toolbar
            HStack(spacing: 16) {
                Toggle("Auto-scroll", isOn: $autoScroll)
                    .font(.system(size: 11))
                    .toggleStyle(.switch)
                    .tint(.blue)
                
                Spacer()
                
                Text("\(logManager.lines.count) lines")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                
                Button("Clear") {
                    logManager.clear()
                }
                .font(.system(size: 12))
                
                ShareLink(item: logManager.exportText()) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.system(size: 12))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(white: 0.12))
        }
        .navigationTitle("Diagnostic Log")
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showPreviousSession) {
            NavigationStack {
                ScrollView {
                    Text(logManager.previousSessionLog)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Color(white: 0.7))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color.black)
                .navigationTitle("Previous Session Log")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { showPreviousSession = false }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: logManager.previousSessionLog) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
    }
    
    private func lineColor(_ line: String) -> Color {
        if line.contains("ERROR") || line.contains("error") || line.contains("Fatal") || line.contains("assert") {
            return .red
        } else if line.contains("[BG]") {
            return .yellow
        } else if line.contains("FARGAN") {
            return .orange
        } else if line.contains("RADE RX:") {
            return .cyan
        } else if line.contains("sync=") && !line.contains("sync=0") {
            return .green
        }
        return Color(white: 0.7)
    }
}

#Preview {
    NavigationStack {
        LogView()
    }
}
