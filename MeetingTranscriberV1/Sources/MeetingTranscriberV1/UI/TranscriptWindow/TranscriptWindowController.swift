import AppKit
import SwiftUI

/// Manages the transcript window
@MainActor
class TranscriptWindowController {
    
    // MARK: - Properties
    
    private var window: NSWindow?
    private var windowDelegate: WindowDelegate?
    private let transcriptionManager: TranscriptionManager
    
    // MARK: - Initialization
    
    init(transcriptionManager: TranscriptionManager) {
        self.transcriptionManager = transcriptionManager
        Log.ui.debug("TranscriptWindowController initialized")
    }
    
    // MARK: - Window Management
    
    /// Show the transcript window
    func showWindow(isRecording: Bool, toggleAction: @escaping () -> Void) {
        // For menu bar apps, we need to activate the app first
        NSApp.activate(ignoringOtherApps: true)
        
        if let existingWindow = window {
            // Update the view content if window already exists
            let contentView = TranscriptView(
                transcriptionManager: transcriptionManager,
                isRecording: isRecording,
                toggleRecording: toggleAction
            )
            existingWindow.contentView = NSHostingView(rootView: contentView)
            
            // Ensure window is visible and in front
            existingWindow.orderFrontRegardless()
            existingWindow.makeKey()
            Log.ui.debug("Bringing existing transcript window to front")
            return
        }
        
        // Create the SwiftUI view
        let contentView = TranscriptView(
            transcriptionManager: transcriptionManager,
            isRecording: isRecording,
            toggleRecording: toggleAction
        )
        
        // Create the window
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        newWindow.title = "Meeting Transcript"
        newWindow.contentView = NSHostingView(rootView: contentView)
        newWindow.center()
        newWindow.setFrameAutosaveName("TranscriptWindow")
        
        // For menu bar apps, use orderFrontRegardless to ensure visibility
        newWindow.orderFrontRegardless()
        newWindow.makeKey()
        
        // Handle window close
        let delegate = WindowDelegate { [weak self] in
            self?.window = nil
            self?.windowDelegate = nil
            Log.ui.debug("Transcript window closed")
        }
        newWindow.delegate = delegate
        self.windowDelegate = delegate
        
        self.window = newWindow
        Log.ui.info("Transcript window created and shown")
    }
    
    /// Hide the transcript window
    func hideWindow() {
        window?.orderOut(nil)
        Log.ui.debug("Transcript window hidden")
    }
    
    /// Close the transcript window
    func closeWindow() {
        window?.close()
        window = nil
        windowDelegate = nil
        Log.ui.debug("Transcript window closed")
    }
    
    /// Check if window is visible
    var isWindowVisible: Bool {
        window?.isVisible ?? false
    }
}

// MARK: - Window Delegate

private class WindowDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void
    
    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init()
    }
    
    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

