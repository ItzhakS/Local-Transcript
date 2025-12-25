import Foundation
import CoreAudio
import Combine

/// Monitors when other applications start using the microphone to detect meeting start
@MainActor
class MicrophoneActivityMonitor: ObservableObject {
    
    @Published private(set) var isMicrophoneInUseByOtherApp = false
    
    /// Callback invoked when microphone activity is detected (from another app)
    var onMicrophoneActivated: (() -> Void)?
    
    private var isMonitoring = false
    private var propertyListenerAdded = false
    private var defaultInputDeviceID: AudioDeviceID = 0
    
    // MARK: - Public API
    
    /// Start monitoring microphone usage
    func startMonitoring() {
        guard !isMonitoring else {
            Log.detection.debug("Already monitoring microphone activity")
            return
        }
        
        Log.detection.info("Starting microphone activity monitoring")
        
        // Get default input device
        guard let deviceID = getDefaultInputDevice() else {
            Log.detection.error("Failed to get default input device")
            return
        }
        
        defaultInputDeviceID = deviceID
        
        // Add property listener for device usage
        addPropertyListener()
        
        isMonitoring = true
        Log.detection.info("Microphone activity monitoring started")
    }
    
    /// Stop monitoring microphone usage
    func stopMonitoring() {
        guard isMonitoring else {
            Log.detection.debug("Stop monitoring called but not currently monitoring")
            return
        }
        
        Log.detection.info("Stopping microphone activity monitoring")
        
        removePropertyListener()
        
        isMonitoring = false
        isMicrophoneInUseByOtherApp = false
        Log.detection.info("Microphone activity monitoring stopped")
    }
    
    // MARK: - Private Methods
    
    private func getDefaultInputDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var deviceIDSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &deviceIDSize,
            &deviceID
        )
        
        guard status == noErr else {
            Log.detection.error("Failed to get default input device: \(status)")
            return nil
        }
        
        return deviceID
    }
    
    private func addPropertyListener() {
        guard !propertyListenerAdded else { return }
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectAddPropertyListenerBlock(
            defaultInputDeviceID,
            &propertyAddress,
            DispatchQueue.main
        ) { [weak self] _, _ in
            self?.checkMicrophoneUsage()
        }
        
        if status == noErr {
            propertyListenerAdded = true
            Log.detection.debug("Property listener added successfully")
        } else {
            Log.detection.error("Failed to add property listener: \(status)")
        }
    }
    
    private func removePropertyListener() {
        guard propertyListenerAdded else { return }
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectRemovePropertyListenerBlock(
            defaultInputDeviceID,
            &propertyAddress,
            DispatchQueue.main
        ) { _, _ in }
        
        if status == noErr {
            propertyListenerAdded = false
            Log.detection.debug("Property listener removed successfully")
        } else {
            Log.detection.error("Failed to remove property listener: \(status)")
        }
    }
    
    private func checkMicrophoneUsage() {
        guard isMonitoring else { return }
        
        var isRunning: UInt32 = 0
        var isRunningSize = UInt32(MemoryLayout<UInt32>.size)
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectGetPropertyData(
            defaultInputDeviceID,
            &propertyAddress,
            0,
            nil,
            &isRunningSize,
            &isRunning
        )
        
        guard status == noErr else {
            Log.detection.error("Failed to check microphone usage: \(status)")
            return
        }
        
        let micIsInUse = isRunning != 0
        
        // Check if this is a state change from not-in-use to in-use
        if micIsInUse && !isMicrophoneInUseByOtherApp {
            Log.detection.info("Microphone activated by another application")
            isMicrophoneInUseByOtherApp = true
            
            // Trigger callback
            onMicrophoneActivated?()
        } else if !micIsInUse && isMicrophoneInUseByOtherApp {
            Log.detection.info("Microphone no longer in use")
            isMicrophoneInUseByOtherApp = false
        }
    }
}

