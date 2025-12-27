import AppKit
import SwiftUI
import UserNotifications

/// Application delegate managing menu bar, notifications, and audio capture coordination
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    
    // MARK: - Properties
    
    private var statusItem: NSStatusItem?
    private var microphoneMonitor: MicrophoneActivityMonitor?
    
    // Audio capture managers
    private let screenCaptureManager = ScreenCaptureManager()
    private let microphoneManager = MicrophoneManager()
    private let audioMixer = AudioMixer()
    
    // Recording state
    @Published private(set) var isRecording = false
    private var mixedAudioTask: Task<Void, Never>?
    
    // MARK: - App Delegate Methods
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.ui.info("Application launched")
        
        // Setup menu bar
        setupMenuBar()
        
        // Setup notification center delegate first
        UNUserNotificationCenter.current().delegate = self
        
        // Request permissions FIRST, then start monitoring
        // This prevents race condition where permission dialogs briefly activate the mic
        Task {
            await Permissions.requestAllPermissions()
            
            // Small delay to let permission dialogs settle
            try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds
            
            // Now setup microphone monitoring on the main actor
            await MainActor.run {
                self.setupMicrophoneMonitoring()
            }
            
            Log.ui.info("Initialization complete - monitoring active")
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        Log.ui.info("Application terminating")
        
        // Stop monitoring
        microphoneMonitor?.stopMonitoring()
        
        // Stop recording if active
        if isRecording {
            Task {
                await stopRecording()
            }
        }
    }
    
    // MARK: - Menu Bar Setup
    
    private func setupMenuBar() {
        // Create status item in menu bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        guard let statusItem = statusItem else {
            Log.ui.error("Failed to create status item")
            return
        }
        
        // Set icon (using SF Symbol)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "MeetingTranscriber")
        }
        
        // Create menu
        updateMenu()
        
        Log.ui.info("Menu bar setup complete")
    }
    
    private func updateMenu() {
        guard let statusItem = statusItem else { return }
        
        let menu = NSMenu()
        
        // Start/Stop Recording toggle
        let recordingTitle = isRecording ? "Stop Recording" : "Start Recording"
        let recordingItem = NSMenuItem(
            title: recordingTitle,
            action: #selector(toggleRecording),
            keyEquivalent: "r"
        )
        recordingItem.target = self
        menu.addItem(recordingItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    // MARK: - Menu Actions
    
    @objc private func toggleRecording() {
        Task {
            if isRecording {
                await stopRecording()
            } else {
                await startRecording()
            }
        }
    }
    
    @objc private func quitApp() {
        Log.ui.info("Quit requested")
        NSApplication.shared.terminate(nil)
    }
    
    // MARK: - Recording Control
    
    private func startRecording() async {
        guard !isRecording else {
            Log.ui.warning("Start recording called but already recording")
            return
        }
        
        Log.ui.info("Starting recording")
        
        do {
            // Start screen capture
            let systemStream = try await screenCaptureManager.startCapture()
            
            // Start microphone capture
            let micStream = try await microphoneManager.startCapture()
            
            // Start mixing
            let mixedStream = await audioMixer.startMixing(system: systemStream, microphone: micStream)
            
            // Process mixed audio (for now just log it, later will transcribe)
            mixedAudioTask = Task {
                for await chunk in mixedStream {
                    // TODO: Send to transcription in Phase 2
                    // For now, just verify we're receiving audio
                    Log.audio.debug("Received chunk from \(chunk.speakerLabel): \(chunk.buffer.samples.count) samples")
                }
            }
            
            isRecording = true
            updateMenu()
            
            // Update menu bar icon to show recording state
            if let button = statusItem?.button {
                button.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "Recording")
            }
            
            Log.ui.info("Recording started successfully")
            
        } catch {
            Log.ui.error("Failed to start recording: \(error.localizedDescription)")
            
            // Show error alert
            await showErrorAlert(error)
        }
    }
    
    private func stopRecording() async {
        guard isRecording else {
            Log.ui.warning("Stop recording called but not currently recording")
            return
        }
        
        Log.ui.info("Stopping recording")
        
        // Cancel mixed audio processing
        mixedAudioTask?.cancel()
        mixedAudioTask = nil
        
        // Stop mixer
        await audioMixer.stopMixing()
        
        // Stop captures
        await screenCaptureManager.stopCapture()
        await microphoneManager.stopCapture()
        
        isRecording = false
        updateMenu()
        
        // Update menu bar icon to show idle state
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "MeetingTranscriber")
        }
        
        Log.ui.info("Recording stopped")
    }
    
    // MARK: - Microphone Monitoring
    
    private func setupMicrophoneMonitoring() {
        microphoneMonitor = MicrophoneActivityMonitor()
        
        microphoneMonitor?.onMicrophoneActivated = { [weak self] in
            Task { @MainActor in
                await self?.handleMicrophoneActivation()
            }
        }
        
        microphoneMonitor?.startMonitoring()
        
        Log.detection.info("Microphone monitoring setup complete")
    }
    
    private func handleMicrophoneActivation() async {
        // Don't prompt if already recording
        guard !isRecording else {
            Log.detection.debug("Microphone activated but already recording")
            return
        }
        
        Log.detection.info("Microphone activation detected - showing notification")
        
        // Show notification
        await showMeetingDetectedNotification()
    }
    
    // MARK: - Notifications
    
    private func showMeetingDetectedNotification() async {
        let content = UNMutableNotificationContent()
        content.title = "Meeting Detected"
        content.body = "Another app is using your microphone. Start recording?"
        content.sound = .default
        content.categoryIdentifier = "MEETING_DETECTED"
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil  // Show immediately
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            Log.detection.info("Meeting detection notification shown")
        } catch {
            Log.detection.error("Failed to show notification: \(error.localizedDescription)")
        }
    }
    
    private func showErrorAlert(_ error: Error) async {
        let alert = NSAlert()
        alert.messageText = "Recording Error"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        
        alert.runModal()
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {
    
    /// Handle notification when app is in foreground
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is active
        completionHandler([.banner, .sound])
    }
    
    /// Handle notification response (user tapped on notification)
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Log.ui.info("Notification response received: \(response.actionIdentifier)")
        
        if response.notification.request.content.categoryIdentifier == "MEETING_DETECTED" {
            // User tapped the notification - start recording
            Task { @MainActor in
                await self.startRecording()
                completionHandler()
            }
        } else {
            completionHandler()
        }
    }
}

