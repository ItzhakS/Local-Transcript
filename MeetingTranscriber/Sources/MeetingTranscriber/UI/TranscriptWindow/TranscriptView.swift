import SwiftUI

/// Displays live transcript entries
struct TranscriptView: View {
    
    @ObservedObject var transcriptionManager: TranscriptionManager
    @State private var autoScroll = true
    
    // Recording control
    var isRecording: Bool = false
    var toggleRecording: () -> Void = {}
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Live Transcript")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    if isRecording {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                            Text("Recording...")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                // Start/Stop Recording button
                Button(action: toggleRecording) {
                    Label(
                        isRecording ? "Stop" : "Start",
                        systemImage: isRecording ? "stop.fill" : "record.circle"
                    )
                    .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(isRecording ? .red : .blue)
                .controlSize(.small)
                
                Divider().frame(height: 20).padding(.horizontal, 4)
                
                // Auto-scroll toggle
                Toggle(isOn: $autoScroll) {
                    Label("Auto-scroll", systemImage: "arrow.down.circle")
                        .font(.caption)
                }
                .toggleStyle(.button)
                .controlSize(.small)
                
                // Copy button
                Button(action: {
                    let fullText = transcriptionManager.getFullTranscript()
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(fullText, forType: .string)
                    Log.ui.info("Transcript copied to clipboard")
                }) {
                    Label("Copy All", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(transcriptionManager.transcriptEntries.isEmpty)
                
                // Clear button
                Button(action: {
                    transcriptionManager.clearTranscript()
                }) {
                    Label("Clear", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(transcriptionManager.transcriptEntries.isEmpty)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Transcript content
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if transcriptionManager.transcriptEntries.isEmpty {
                            // Empty state
                            VStack(spacing: 12) {
                                Image(systemName: "waveform.circle")
                                    .font(.system(size: 48))
                                    .foregroundColor(.secondary)
                                
                                Text("No transcript yet")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                
                                Text("Start recording to see live transcription")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.top, 60)
                        } else {
                            ForEach(transcriptionManager.transcriptEntries) { entry in
                                TranscriptEntryRow(entry: entry)
                                    .id(entry.id)
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: transcriptionManager.transcriptEntries.count) { _ in
                    if autoScroll, let lastEntry = transcriptionManager.transcriptEntries.last {
                        withAnimation {
                            proxy.scrollTo(lastEntry.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

/// Individual transcript entry row
struct TranscriptEntryRow: View {
    let entry: TranscriptEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Speaker and timestamp
            HStack(spacing: 8) {
                // Speaker label with color
                Text(entry.speaker)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(speakerColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(speakerColor.opacity(0.15))
                    .cornerRadius(4)
                
                // Timestamp
                Text(entry.timestampString)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Confidence indicator
                if entry.confidence > 0 {
                    ConfidenceIndicator(confidence: entry.confidence)
                }
            }
            
            // Transcript text
            Text(entry.text)
                .font(.body)
                .foregroundColor(.primary)
                .textSelection(.enabled)
                .lineSpacing(2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
    
    /// Returns a color for the speaker based on their label
    private var speakerColor: Color {
        SpeakerColorManager.color(for: entry.speaker)
    }
}

/// Manages consistent colors for speakers across the UI
enum SpeakerColorManager {
    /// Color palette for speakers
    private static let speakerColors: [Color] = [
        .green,   // Speaker 1
        .orange,  // Speaker 2
        .purple,  // Speaker 3
        .pink,    // Speaker 4
        .teal,    // Speaker 5
        .indigo,  // Speaker 6
        .mint,    // Speaker 7
        .cyan,    // Speaker 8
    ]
    
    /// Returns a color for the given speaker label
    static func color(for speaker: String) -> Color {
        // "Me" always gets blue
        if speaker == "Me" {
            return .blue
        }
        
        // "Others" (fallback when diarization not available) gets green
        if speaker == "Others" {
            return .green
        }
        
        // For "Speaker N" labels, extract the number and assign color from palette
        if speaker.hasPrefix("Speaker ") {
            if let numberStr = speaker.components(separatedBy: " ").last,
               let number = Int(numberStr) {
                // Use modulo to cycle through colors if more than palette size
                let colorIndex = (number - 1) % speakerColors.count
                return speakerColors[colorIndex]
            }
        }
        
        // For custom speaker names, generate a consistent color based on hash
        let hash = abs(speaker.hashValue)
        let colorIndex = hash % speakerColors.count
        return speakerColors[colorIndex]
    }
}

/// Confidence level indicator
struct ConfidenceIndicator: View {
    let confidence: Double
    
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: confidenceIcon)
                .font(.caption2)
                .foregroundColor(confidenceColor)
            
            Text(String(format: "%.0f%%", confidence * 100))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    private var confidenceIcon: String {
        if confidence >= 0.8 {
            return "checkmark.circle.fill"
        } else if confidence >= 0.5 {
            return "checkmark.circle"
        } else {
            return "questionmark.circle"
        }
    }
    
    private var confidenceColor: Color {
        if confidence >= 0.8 {
            return .green
        } else if confidence >= 0.5 {
            return .orange
        } else {
            return .red
        }
    }
}

