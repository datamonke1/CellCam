import SwiftUI
import UIKit

@main
struct CellCamApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    // The phone must never sleep while a timelapse is planned:
                    // iOS kills the camera as soon as the app leaves the foreground.
                    UIApplication.shared.isIdleTimerDisabled = true
                }
        }
    }
}
