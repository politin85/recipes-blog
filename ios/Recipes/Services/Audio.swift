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

/// The Hebrew voices installed on the device. Narration uses only these (no server).
struct NarrationVoice: Identifiable, Hashable {
    let id: String
    let label: String

    /// Best quality first; more voices appear after downloading them in
    /// Settings → Accessibility → Read & Speak → Voices → Hebrew.
    static var installed: [NarrationVoice] {
        hebrewVoices.map { voice in
            let quality: String
            switch voice.quality {
            case .premium: quality = " (פרימיום)"
            case .enhanced: quality = " (משופר)"
            default: quality = ""
            }
            return NarrationVoice(id: voice.identifier, label: voice.name + quality)
        }
    }

    private static var hebrewVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("he") }
            .sorted { $0.quality.rawValue != $1.quality.rawValue ? $0.quality.rawValue > $1.quality.rawValue : $0.name < $1.name }
    }

    /// The chosen voice if it is still installed, otherwise the best Hebrew voice available.
    static func resolve(_ identifier: String) -> AVSpeechSynthesisVoice? {
        hebrewVoices.first { $0.identifier == identifier }
            ?? hebrewVoices.first
            ?? AVSpeechSynthesisVoice(language: "he-IL")
    }
}

/// One piece of narration with the play / pause / resume cycle of the web buttons.
@MainActor
@Observable
final class SpeechClip: NSObject, AVSpeechSynthesizerDelegate {
    enum State { case idle, playing, paused, failed }

    private(set) var state: State = .idle
    private var synthesizer: AVSpeechSynthesizer?

    /// - Parameter failureResetDelay: when set, a failure flips back to idle after the delay
    ///   (the per-step button does this after 2 seconds).
    func toggle(text: String, voice: String, failureResetDelay: Duration? = nil) {
        switch state {
        case .playing:
            synthesizer?.pauseSpeaking(at: .immediate)
            state = .paused
        case .paused:
            synthesizer?.continueSpeaking()
            state = .playing
        case .idle, .failed:
            guard let voice = NarrationVoice.resolve(voice) else {
                state = .failed
                if let failureResetDelay {
                    Task {
                        try? await Task.sleep(for: failureResetDelay)
                        if state == .failed { state = .idle }
                    }
                }
                return
            }
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = voice
            let synthesizer = AVSpeechSynthesizer()
            synthesizer.delegate = self
            self.synthesizer = synthesizer
            try? AVAudioSession.sharedInstance().setActive(true)
            synthesizer.speak(utterance)
            state = .playing
        }
    }

    func stop() {
        synthesizer?.stopSpeaking(at: .immediate)
        synthesizer = nil
        state = .idle
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.synthesizer === synthesizer else { return }
            self.synthesizer = nil
            self.state = .idle
        }
    }
}
