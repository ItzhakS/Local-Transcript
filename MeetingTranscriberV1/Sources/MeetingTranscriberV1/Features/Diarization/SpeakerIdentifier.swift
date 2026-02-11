import Foundation

/// Manages speaker identification and labeling across diarization segments
actor SpeakerIdentifier {
    
    // MARK: - Properties
    
    /// Map of numeric speaker IDs to user-friendly labels
    private var speakerLabels: [Int: String] = [:]
    
    /// Custom names assigned by users
    private var customNames: [Int: String] = [:]
    
    /// Next speaker number to assign
    private var nextSpeakerNumber: Int = 1
    
    /// Track when each speaker was last active
    private var lastActiveTime: [Int: Date] = [:]
    
    // MARK: - Initialization
    
    init() {
        Log.diarization.info("SpeakerIdentifier initialized")
    }
    
    // MARK: - Label Management
    
    /// Get or assign a label for a speaker ID
    /// - Parameter speakerId: The numeric speaker ID from diarization
    /// - Returns: A user-friendly label (e.g., "Speaker 1" or custom name)
    func getLabel(for speakerId: Int) -> String {
        // Check for custom name first
        if let customName = customNames[speakerId] {
            return customName
        }
        
        // Check for existing label
        if let existingLabel = speakerLabels[speakerId] {
            return existingLabel
        }
        
        // Assign new label
        let newLabel = "Speaker \(nextSpeakerNumber)"
        speakerLabels[speakerId] = newLabel
        nextSpeakerNumber += 1
        
        Log.diarization.info("Assigned label '\(newLabel, privacy: .public)' to speaker ID \(speakerId)")
        
        return newLabel
    }
    
    /// Update speaker activity timestamps from diarization segments
    /// - Parameter segments: Speaker segments from diarization
    func updateFromSegments(_ segments: [SpeakerSegment]) {
        let now = Date()
        for segment in segments {
            // Use numeric speaker ID
            let numericId = segment.numericSpeakerId
            // Ensure each speaker has a label
            _ = getLabel(for: numericId)
            lastActiveTime[numericId] = now
        }
    }
    
    /// Rename a speaker with a custom name
    /// - Parameters:
    ///   - speakerId: The speaker ID to rename
    ///   - name: The new name
    func renameSpeaker(_ speakerId: Int, to name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            // Clear custom name and revert to default
            customNames.removeValue(forKey: speakerId)
            Log.diarization.info("Cleared custom name for speaker ID \(speakerId)")
            return
        }
        
        customNames[speakerId] = trimmedName
        Log.diarization.info("Renamed speaker ID \(speakerId) to '\(trimmedName, privacy: .public)'")
    }
    
    /// Get all active speakers with their labels
    /// - Returns: Dictionary mapping speaker IDs to their labels
    func getActiveSpeakers() -> [Int: String] {
        var result: [Int: String] = [:]
        for speakerId in speakerLabels.keys {
            result[speakerId] = getLabel(for: speakerId)
        }
        return result
    }
    
    /// Get the number of identified speakers
    var speakerCount: Int {
        speakerLabels.count
    }
    
    /// Check if a speaker ID has been seen before
    func hasSpeaker(_ speakerId: Int) -> Bool {
        speakerLabels[speakerId] != nil
    }
    
    /// Reset all speaker tracking (call when starting a new recording)
    func reset() {
        speakerLabels = [:]
        customNames = [:]
        lastActiveTime = [:]
        nextSpeakerNumber = 1
        Log.diarization.info("SpeakerIdentifier reset")
    }
    
    /// Get speakers active within the last N seconds
    /// - Parameter seconds: Time window in seconds
    /// - Returns: Dictionary of recently active speaker IDs to labels
    func getRecentlyActiveSpeakers(within seconds: TimeInterval) -> [Int: String] {
        let cutoff = Date().addingTimeInterval(-seconds)
        var result: [Int: String] = [:]
        
        for (speakerId, lastActive) in lastActiveTime {
            if lastActive > cutoff {
                result[speakerId] = getLabel(for: speakerId)
            }
        }
        
        return result
    }
}
