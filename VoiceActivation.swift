//
//  VoiceActivation.swift
//  Vibro
//
//  Created by lyubcsenko on 21/10/2025.
//

import AVFoundation
import Speech


enum VoiceAuth {
    static func isAuthorized() -> Bool {
        let micGranted = AVAudioSession.sharedInstance().recordPermission == .granted
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        return micGranted && speechStatus == .authorized
    }
}

final class BackgroundSpeechListener: ObservableObject {
    private let recognizer: SFSpeechRecognizer
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let matcher: VoiceCommandMatcher

    // Track how many transcription segments we've already handled
    private var lastProcessedSegmentCount = 0

    /// Called with 1 or 2 when detected.
    var onCommand: ((Int) -> Void)?

    /// Called when we hit max failures and lock out.
    /// Use this to set `useMicrophone = false` and show an alert.
    var onLockout: ((String) -> Void)?

    // --- NEW: restart guard ---
    private var consecutiveErrorRestarts = 0
    private let maxErrorRestarts = 3
    private var isLockedOut = false
    private var pendingRestart: DispatchWorkItem?

    init(appLocale: Locale) {
        self.recognizer = SFSpeechRecognizer(locale: appLocale)!
        self.matcher = VoiceCommandMatcher(appLocale: appLocale)
    }

    /// Call with resetFailures: true when user taps mic to try again.
    func start(resetFailures: Bool = false) throws {
        if resetFailures {
            consecutiveErrorRestarts = 0
            isLockedOut = false
        }

        guard !isLockedOut else {
            throw NSError(domain: "Speech", code: -999, userInfo: [
                NSLocalizedDescriptionKey: "Speech locked out after repeated failures."
            ])
        }

        guard task == nil else { return }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, options: [.mixWithOthers, .allowBluetooth, .defaultToSpeaker])
        try session.setMode(.measurement)
        try? session.setAllowHapticsAndSystemSoundsDuringRecording(true)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if #available(iOS 13.0, *) { req.taskHint = .confirmation }
        request = req

        let input = audioEngine.inputNode
        let format = input.inputFormat(forBus: 0)

        // Remove any existing taps (safe)
        input.removeTap(onBus: 0)

        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        // Reset segment counter at start of a fresh task
        lastProcessedSegmentCount = 0

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }

            if let result {
                // ✅ Any successful result means we’re alive again → reset error counter
                self.consecutiveErrorRestarts = 0

                print("[Speech] \(result.bestTranscription.formattedString)")

                let segments = result.bestTranscription.segments
                if segments.count > self.lastProcessedSegmentCount {
                    for i in self.lastProcessedSegmentCount..<segments.count {
                        let token = segments[i].substring.trimmingCharacters(in: .whitespacesAndNewlines)
                        print("[Speech][token] \(token)")
                        if let n = self.matcher.match(token) {
                            self.onCommand?(n)
                        }
                    }
                    self.lastProcessedSegmentCount = segments.count
                }

                if result.isFinal {
                    self.lastProcessedSegmentCount = 0
                    // Final is normal — restart does NOT count as a failure
                    self.scheduleRestart(isError: false, message: nil)
                }
            }

            if let error {
                // Ignore cancellation errors
                let ns = error as NSError
                if ns.code == NSUserCancelledError { return }

                print("[Speech] Task error: \(error.localizedDescription)")
                self.scheduleRestart(isError: true, message: error.localizedDescription)
            }
        }
    }

    func stop() {
        pendingRestart?.cancel()
        pendingRestart = nil

        task?.cancel()
        task = nil

        request?.endAudio()
        request = nil

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func scheduleRestart(isError: Bool, message: String?) {
        // If user turned it off elsewhere, don’t fight them
        if isLockedOut { return }

        pendingRestart?.cancel()
        pendingRestart = nil

        if isError {
            consecutiveErrorRestarts += 1

            if consecutiveErrorRestarts >= maxErrorRestarts {
                isLockedOut = true
                stop()

                DispatchQueue.main.async {
                    self.onLockout?(
                        message ?? "Speech recognition failed repeatedly. Please tap the mic to try again."
                    )
                }
                return
            }
        }

        // Small backoff for error restarts; immediate-ish for normal finals
        let delay: TimeInterval = isError ? (0.4 * Double(consecutiveErrorRestarts)) : 0.05
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard !self.isLockedOut else { return }

            do {
                self.stop()
                try self.start(resetFailures: false)
            } catch {
                // If start throws, treat it like an error restart
                self.scheduleRestart(isError: true, message: error.localizedDescription)
            }
        }

        pendingRestart = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}



enum VoicePermOutcome {
    case allGranted
    case micDenied
    case speechDenied
    case error(String)
}

struct VoicePermissionRequester {
    static func requestAll() async -> VoicePermOutcome {
        let mic = await requestMic()
        guard mic else { return .micDenied }

        let speech = await requestSpeech()
        guard speech else { return .speechDenied }

        return .allGranted
    }

    private static func requestMic() async -> Bool {
        await withCheckedContinuation { cont in
            // Use AVAudioSession for widest iOS support
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
    }

    private static func requestSpeech() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                switch status {
                case .authorized: cont.resume(returning: true)
                case .denied, .restricted, .notDetermined: cont.resume(returning: false)
                @unknown default: cont.resume(returning: false)
                }
            }
        }
    }
}

struct VoiceCommandMatcher {
    /// token(lowercased, folded) -> value
    private let tokenToValue: [String: Int]

    init(appLocale: Locale) {
        var map: [String: Int] = [:]

        let nf = NumberFormatter()
        nf.locale = appLocale
        nf.numberStyle = .spellOut

        func fold(_ s: String) -> String {
            s.folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive],
                      locale: appLocale)
        }

        // Build tokens for 1...10
        for n in 1...10 {
            // Digit form ("1", "2", ... "10")
            map[fold("\(n)")] = n

            // Spelled-out form in the locale ("one", "zwei", "diez", etc.)
            if let word = nf.string(from: NSNumber(value: n))?.lowercased() {
                map[fold(word)] = n

                // Be tolerant to recognizer variations around hyphens/spaces.
                // (Less relevant for <=10, but harmless.)
                let noHyphen = word.replacingOccurrences(of: "-", with: " ")
                map[fold(noHyphen)] = n
            }
        }

        // Optional: add a few pragmatic aliases that ASR often outputs in English.
        // Comment out if false positives are a concern or for non-English locales.
        if appLocale.identifier.hasPrefix("en") {
            map[fold("to")]   = 2   // sometimes "two" becomes "to"
            map[fold("too")]  = 2
            map[fold("for")]  = 4   // "four" → "for"
            map[fold("ate")]  = 8   // "eight" → "ate"
        }

        self.tokenToValue = map
    }

    /// Returns 1...10 if found as a standalone token in `text`.
    func match(_ text: String) -> Int? {
        // crude but effective tokenization
        let tokens = text.split { !$0.isLetter && !$0.isNumber }
        for raw in tokens {
            let token = String(raw)
            let folded = token.folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive],
                                       locale: nil)
            if let v = tokenToValue[folded] {
                return v
            }
        }
        return nil
    }
}

