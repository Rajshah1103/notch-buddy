import AppKit
import ApplicationServices

enum Permissions {
    static var accessibilityGranted: Bool { AXIsProcessTrusted() }
    static var screenRecordingGranted: Bool { CGPreflightScreenCaptureAccess() }

    static func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
    }
}
