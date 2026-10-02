import AVFoundation
import SwiftUI

enum AudioSetup {
    /// Play even when the ring/silent switch is on silent — a kitchen timer has to be heard.
    static func configure() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
    }
}

/// Plays the bundled timer sounds (the WAV renders of the website's WebAudio beeps).
@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()
    private var player: AVAudioPlayer?

    func play(_ name: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }
}

/// One piece of server-generated speech with the play / pause / resume cycle of the web buttons.
@MainActor
@Observable
final class SpeechClip: NSObject, AVAudioPlayerDelegate {
    enum State { case idle, loading, playing, paused, failed }

    private(set) var state: State = .idle
    private var player: AVAudioPlayer?

    var duration: TimeInterval { player?.duration ?? 0 }
    var currentTime: TimeInterval { player?.currentTime ?? 0 }
    var isLoaded: Bool { player != nil }

    /// - Parameter failureResetDelay: when set, a failure flips back to idle after the delay
    ///   (the per-step button does this after 2 seconds).
    func toggle(text: String, voice: String, failureResetDelay: Duration? = nil) {
        switch state {
        case .loading:
            return
        case .playing:
            player?.pause()
            state = .paused
        case .paused:
            player?.play()
            state = .playing
        case .idle, .failed:
            state = .loading
            Task {
                do {
                    let data = try await API.shared.tts(text: text, voice: voice)
                    try? AVAudioSession.sharedInstance().setActive(true)
                    let player = try AVAudioPlayer(data: data)
                    player.delegate = self
                    self.player = player
                    player.play()
                    state = .playing
                } catch {
                    player = nil
                    state = .failed
                    if let failureResetDelay {
                        try? await Task.sleep(for: failureResetDelay)
                        if state == .failed { state = .idle }
                    }
                }
            }
        }
    }

    func seek(to time: TimeInterval) {
        player?.currentTime = time
    }

    func stop() {
        player?.stop()
        player = nil
        state = .idle
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.player = nil
            self.state = .idle
        }
    }
}
