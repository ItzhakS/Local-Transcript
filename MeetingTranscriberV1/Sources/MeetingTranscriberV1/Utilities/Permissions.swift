import AVFoundation
import ScreenCaptureKit
import UserNotifications
import AppKit

/// Manages all system permissions required by the app
enum Permissions {
    
    // MARK: - Screen Recording Permission
    
    /// Check if screen recording permission is currently granted
    static func checkScreenRecordingPermission() -> Bool {
        // CGPreflightScreenCaptureAccess returns true if permission is granted
        return CGPreflightScreenCaptureAccess()
    }
    
    /// Request screen recording permission
    /// This will show a system dialog and open System Settings if permission is not granted
    static func requestScreenRecordingPermission() {
        Log.permissions.info("Requesting screen recording permission")
        
        // CGRequestScreenCaptureAccess prompts the user and opens System Settings
        let granted = CGRequestScreenCaptureAccess()
        
        if granted {
            Log.permissions.info("Screen recording permission granted")
        } else {
            Log.permissions.warning("Screen recording permission denied - opening System Settings")
            openSystemSettingsPrivacy()
        }
    }
    
    // MARK: - Microphone Permission
    
    /// Check current microphone permission status
    static func checkMicrophonePermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        
        switch status {
        case .authorized:
            Log.permissions.info("Microphone permission already granted")
            return true
        case .notDetermined:
            Log.permissions.info("Microphone permission not yet determined")
            return false
        case .denied, .restricted:
            Log.permissions.warning("Microphone permission denied or restricted")
            return false
        @unknown default:
            Log.permissions.warning("Unknown microphone permission status")
            return false
        }
    }
    
    /// Request microphone permission
    /// Returns true if granted, false if denied
    static func requestMicrophonePermission() async -> Bool {
        Log.permissions.info("Requesting microphone permission")
        
        // Check if already authorized
        if await checkMicrophonePermission() {
            return true
        }
        
        // Request permission
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        
        if granted {
            Log.permissions.info("Microphone permission granted")
        } else {
            Log.permissions.warning("Microphone permission denied")
        }
        
        return granted
    }
    
    // MARK: - Notification Permission
    
    /// Check current notification permission status
    static func checkNotificationPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        
        let authorized = settings.authorizationStatus == .authorized
        Log.permissions.info("Notification permission status: \(settings.authorizationStatus.rawValue)")
        
        return authorized
    }
    
    /// Request notification permission
    /// Returns true if granted, false if denied
    static func requestNotificationPermission() async -> Bool {
        Log.permissions.info("Requesting notification permission")
        
        let center = UNUserNotificationCenter.current()
        
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            
            if granted {
                Log.permissions.info("Notification permission granted")
            } else {
                Log.permissions.warning("Notification permission denied")
            }
            
            return granted
        } catch {
            Log.permissions.error("Failed to request notification permission: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Permission Check All
    
    /// Check all required permissions
    /// Returns a dictionary with permission status for each type
    static func checkAllPermissions() async -> [String: Bool] {
        return [
            "screenRecording": checkScreenRecordingPermission(),
            "microphone": await checkMicrophonePermission(),
            "notifications": await checkNotificationPermission()
        ]
    }
    
    /// Request all required permissions sequentially
    /// Note: Notification permission is NOT requested here - it's requested on-demand
    /// when auto-detection triggers and needs to show a notification
    static func requestAllPermissions() async {
        Log.permissions.info("Requesting essential permissions (screen recording, microphone)")
        
        // Request screen recording first
        if !checkScreenRecordingPermission() {
            requestScreenRecordingPermission()
        }
        
        // Request microphone
        if !(await checkMicrophonePermission()) {
            _ = await requestMicrophonePermission()
        }
        
        // Note: Notification permission is intentionally NOT requested at startup
        // It will be requested on-demand when auto-detection triggers
        // This prevents unnecessary permission dialogs during manual recording
    }
    
    // MARK: - Helper Methods
    
    /// Open System Settings to the Privacy & Security pane
    private static func openSystemSettingsPrivacy() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
        }
    }
}

