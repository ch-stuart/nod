import SwiftUI
import AVFoundation

@main
struct SleepNoiseApp: App {
    init() {
        configureAudioSession()
    }

    var body: some Scene {
        WindowGroup {
            GridView().preferredColorScheme(.light)
        }
    }

    private func configureAudioSession() {
        do {
            // .playback category allows audio to continue when screen locks
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        } catch {
            print("Audio session setup failed: \(error)")
        }
    }
}
