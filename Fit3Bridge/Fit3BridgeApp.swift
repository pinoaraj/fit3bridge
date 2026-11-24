import SwiftUI

@main
struct Fit3BridgeApp: App {
    @StateObject private var fit3 = Fit3Manager.shared
    @StateObject private var healthKit = HealthKitManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(fit3)
                .environmentObject(healthKit)
                .onAppear {
                    healthKit.requestAuthorization()
                }
        }
    }
}