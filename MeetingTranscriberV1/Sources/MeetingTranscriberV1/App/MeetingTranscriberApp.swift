import SwiftUI

/// Main application entry point
@main
struct MeetingTranscriberApp: App {
    
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // Menu bar only app - no windows needed
        Settings {
            EmptyView()
        }
    }
}

