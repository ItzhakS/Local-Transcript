import AppKit
import SwiftUI
import UserNotifications
import Intents

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
    
    // Transcription
    private let transcriptionManager = TranscriptionManager()
    private var transcriptWindowController: TranscriptWindowController?
    
    // Recording state
    @Published private(set) var isRecording = false
    private var isStarting = false
    private var mixedAudioTask: Task<Void, Never>?
    
    // MARK: - App Delegate Methods
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.ui.info("Application launched")
        
        // Setup menu bar
        setupMenuBar()
        
        // Setup notification center delegate and register categories
        setupNotifications()
        
        // Initialize transcript window controller
        transcriptWindowController = TranscriptWindowController(transcriptionManager: transcriptionManager)
        
        // Request permissions FIRST, then start monitoring
        // This prevents race condition where permission dialogs briefly activate the mic
        Task {
            await Permissions.requestAllPermissions()
            
            // Pre-load transcription model in the background so "Start Recording" is instant
            Log.transcription.info("Pre-loading transcription model...")
            try? await self.transcriptionManager.start()
            // Stop immediately so we're not "recording" but the model remains loaded in WhisperEngine
            await self.transcriptionManager.stop()
            Log.transcription.info("Transcription model pre-loaded and ready")
            
            // Small delay to let permission dialogs settle
            try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds
            
            // Now setup microphone monitoring on the main actor
            await MainActor.run {
                self.setupMicrophoneMonitoring()
            }
            
            Log.ui.info("Initialization complete - monitoring active")
        }
    }
    
    private func setupNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        
        // Create actions for the meeting detected notification
        let startRecordingAction = UNNotificationAction(
            identifier: "START_RECORDING",
            title: "Start Recording",
            options: [.foreground]
        )
        
        let dismissAction = UNNotificationAction(
            identifier: "DISMISS",
            title: "Dismiss",
            options: []
        )
        
        // Create the category with actions
        let meetingCategory = UNNotificationCategory(
            identifier: "MEETING_DETECTED",
            actions: [startRecordingAction, dismissAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        // Register the category
        center.setNotificationCategories([meetingCategory])
        
        Log.ui.info("Notification categories registered")
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
        
        // Close transcript window
        transcriptWindowController?.closeWindow()
    }
    
    // MARK: - Menu Bar Setup
    
    private func setupMenuBar() {
        // Use squareLength to ensure the icon space is reserved and never collapses
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        guard let statusItem = statusItem else {
            Log.ui.error("Failed to create status item")
            return
        }
        
        // Set initial icon using original SF Symbols that worked earlier
        setMenuBarIcon(recording: false)
        
        // Create menu
        updateMenu()
        
        Log.ui.info("Menu bar setup complete")
    }
    
    /// Set the menu bar icon based on recording state
    private func setMenuBarIcon(recording: Bool) {
        guard let button = statusItem?.button else { return }
        
        // Use standard symbols that are known to work well in menu bars
        let symbolName = recording ? "record.circle.fill" : "waveform.circle"
        
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: recording ? "Recording" : "MeetingTranscriber") {
            image.isTemplate = true // Ensures it adapts to light/dark mode
            button.image = image
            button.title = "" // Ensure only image is shown
        } else {
            // Text fallback
            button.image = nil
            button.title = recording ? "●" : "○"
        }
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
        guard !isRecording && !isStarting else {
            Log.ui.warning("Start recording called but already recording or starting")
            return
        }
        
        Log.ui.info("Starting recording")
        isStarting = true
        
        do {
            // Start transcription system
            try await transcriptionManager.start()
            
            // Start screen capture
            let systemStream = try await screenCaptureManager.startCapture()
            
            // Start microphone capture
            let micStream = try await microphoneManager.startCapture()
            
            // Start mixing
            let mixedStream = await audioMixer.startMixing(system: systemStream, microphone: micStream)
            
            // Process mixed audio and send to transcription
            mixedAudioTask = Task {
                for await chunk in mixedStream {
                    // Send to transcription (removed debug log to reduce spam)
                    await transcriptionManager.processAudioChunk(chunk)
                }
            }
            
            isRecording = true
            isStarting = false
            
            // Update UI
            setMenuBarIcon(recording: true)
            updateMenu()
            updateTranscriptWindow()
            
            Log.ui.info("Recording started successfully")
            
        } catch {
            Log.ui.error("Failed to start recording: \(error.localizedDescription)")
            isStarting = false
            
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
        
        // Stop transcription
        await transcriptionManager.stop()
        
        // Stop mixer
        await audioMixer.stopMixing()
        
        // Stop captures
        await screenCaptureManager.stopCapture()
        await microphoneManager.stopCapture()
        
        isRecording = false
        
        // Update menu bar icon to show idle state
        setMenuBarIcon(recording: false)
        
        updateMenu()
        updateTranscriptWindow()
        
        Log.ui.info("Recording stopped")
    }
    
    /// Update the transcript window with current state
    private func updateTranscriptWindow() {
        transcriptWindowController?.showWindow(isRecording: isRecording, toggleAction: { [weak self] in
            Task { @MainActor in
                self?.toggleRecording()
            }
        })
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
        // Don't prompt if already recording or in the process of starting
        guard !isRecording && !isStarting else {
            Log.detection.debug("Microphone activated but already recording or starting")
            return
        }
        
        Log.detection.info("Microphone activation detected - showing notification")
        
        // Show notification
        await showMeetingDetectedNotification()
    }
    
    // MARK: - Notifications
    
    /// Check if Focus/Do Not Disturb mode is active using INFocusStatusCenter (macOS 12+)
    private func isFocusModeActive() async -> Bool {
        // Use the official INFocusStatusCenter API (requires Intents framework)
        let focusCenter = INFocusStatusCenter.default
        
        // Check authorization status
        let authStatus = focusCenter.authorizationStatus
        Log.detection.debug("Focus authorization status: \(authStatus.rawValue) (0=notDetermined, 1=restricted, 2=denied, 3=authorized)")
        
        if authStatus == .notDetermined {
            // Request authorization if not yet determined
            Log.detection.info("Requesting Focus status authorization...")
            return await withCheckedContinuation { continuation in
                focusCenter.requestAuthorization { status in
                    Log.detection.info("Focus authorization response: \(status.rawValue)")
                    if status == .authorized {
                        let isFocused = focusCenter.focusStatus.isFocused ?? false
                        Log.detection.info("Focus status authorization granted, isFocused: \(isFocused)")
                        continuation.resume(returning: isFocused)
                    } else {
                        Log.detection.warning("Focus status authorization denied (status: \(status.rawValue)) - falling back to file check")
                        continuation.resume(returning: self.checkFocusModeViaFile())
                    }
                }
            }
        } else if authStatus == .authorized {
            let focusStatus = focusCenter.focusStatus
            let isFocused = focusStatus.isFocused ?? false
            Log.detection.debug("Focus mode check via INFocusStatusCenter: isFocused=\(isFocused)")
            return isFocused
        } else {
            // Authorization denied or restricted - fall back to file-based check
            Log.detection.warning("Focus status authorization: \(authStatus.rawValue) - using fallback")
            return checkFocusModeViaFile()
        }
    }
    
    /// Fallback file-based Focus mode detection for older macOS versions
    private func checkFocusModeViaFile() -> Bool {
        let possiblePaths = [
            (NSHomeDirectory() as NSString).appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json"),
            (NSHomeDirectory() as NSString).appendingPathComponent("Library/DoNotDisturb/DB/ModeConfigurations.json")
        ]
        
        for assertionsPath in possiblePaths {
            if FileManager.default.fileExists(atPath: assertionsPath),
               let data = try? Data(contentsOf: URL(fileURLWithPath: assertionsPath)),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let store = json["data"] as? [[String: Any]],
               !store.isEmpty {
                Log.detection.info("Focus mode detected via file: \(assertionsPath)")
                return true
            }
        }
        
        Log.detection.debug("Focus mode not detected via file check")
        return false
    }
    
    /// Track if user responded to notification (to avoid showing duplicate alert)
    private var notificationResponseReceived = false
    private var pendingNotificationId: String?
    
    private func showMeetingDetectedNotification() async {
        let center = UNUserNotificationCenter.current()
        
        // Check notification authorization first
        let settings = await center.notificationSettings()
        
        if settings.authorizationStatus != .authorized {
            Log.detection.warning("Notifications not authorized (status: \(settings.authorizationStatus.rawValue)). Requesting permission...")
            
            // Try to request permission
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                if !granted {
                    Log.detection.error("Notification permission denied by user - falling back to alert")
                    await showMeetingDetectedAlert()
                    return
                }
                Log.detection.info("Notification permission granted on-demand")
            } catch {
                Log.detection.error("Failed to request notification permission: \(error) - falling back to alert")
                await showMeetingDetectedAlert()
                return
            }
        }
        
        // Reset response tracking
        notificationResponseReceived = false
        let notificationId = UUID().uuidString
        pendingNotificationId = notificationId
        
        let content = UNMutableNotificationContent()
        content.title = "Meeting Detected"
        content.body = "Another app is using your microphone. Start recording?"
        content.sound = .default
        content.categoryIdentifier = "MEETING_DETECTED"
        
        let request = UNNotificationRequest(
            identifier: notificationId,
            content: content,
            trigger: nil  // Show immediately
        )
        
        do {
            try await center.add(request)
            Log.detection.info("Meeting detection notification sent (id: \(notificationId, privacy: .public))")
            
            // Start backup timer - if no response in 5 seconds, show alert dialog
            // This handles the case where DND silences the notification
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)  // 5 seconds
                
                await MainActor.run {
                    // Only show alert if this notification is still pending and no response received
                    if self.pendingNotificationId == notificationId && !self.notificationResponseReceived && !self.isRecording {
                        Log.detection.info("No notification response after 5s - showing backup alert (likely DND active)")
                        // Remove the pending notification since we're showing alert instead
                        center.removeDeliveredNotifications(withIdentifiers: [notificationId])
                        Task {
                            await self.showMeetingDetectedAlert()
                        }
                    }
                }
            }
            
        } catch let error as NSError {
            Log.detection.error("Failed to show notification: \(error.localizedDescription, privacy: .public) (code: \(error.code), domain: \(error.domain, privacy: .public)) - falling back to alert")
            await showMeetingDetectedAlert()
        }
    }
    
    /// Fallback alert dialog when notifications aren't available
    private func showMeetingDetectedAlert() async {
        let alert = NSAlert()
        alert.messageText = "Meeting Detected"
        alert.informativeText = "Another app is using your microphone. Would you like to start recording?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Start Recording")
        alert.addButton(withTitle: "Dismiss")
        
        // Play alert sound
        NSSound.beep()
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            Log.detection.info("User chose to start recording from alert")
            await startRecording()
        } else {
            Log.detection.info("User dismissed meeting detection alert")
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
        
        let categoryId = response.notification.request.content.categoryIdentifier
        let actionId = response.actionIdentifier
        
        if categoryId == "MEETING_DETECTED" {
            // Mark that we received a response - prevents backup alert from showing
            Task { @MainActor in
                self.notificationResponseReceived = true
                self.pendingNotificationId = nil
            }
            
            switch actionId {
            case "START_RECORDING", UNNotificationDefaultActionIdentifier:
                // User tapped "Start Recording" button or the notification itself
                Task { @MainActor in
                    await self.startRecording()
                    completionHandler()
                }
            case "DISMISS", UNNotificationDismissActionIdentifier:
                // User dismissed the notification
                Log.ui.info("User dismissed meeting detection notification")
                completionHandler()
            default:
                completionHandler()
            }
        } else {
            completionHandler()
        }
    }
}

