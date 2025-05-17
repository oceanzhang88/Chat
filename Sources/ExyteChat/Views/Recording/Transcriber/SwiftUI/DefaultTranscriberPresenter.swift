import Speech
import AVFoundation
import Combine // Make sure Combine is imported for @Published if not already via @Observable

/// Default implementation of SpeechRecognitionPresenter
/// Provides ready-to-use speech recognition functionality for SwiftUI views
@Observable
@MainActor
public class DefaultTranscriberPresenter: TranscriberPresenter {
    public var isRecording = false
    public var transcribedText = ""
    public var authStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    public var error: Error?
    public var rmsLevel: Float = 0.0 // Initialize with a default
    public var audioDuration: TimeInterval? // To store the duration in seconds
    public let availableLocales: [Locale]
    #if os(iOS)
    public var availableInputs: [AVAudioSessionPortDescription] = []
    public var selectedInput: AVAudioSessionPortDescription?
    #endif
    
    public var lastRecordingURL: URL? {
        didSet {
            // When the URL is set, calculate its duration
            if let url = lastRecordingURL {
                Task {
                    await calculateAudioDuration(for: url)
                }
            } else {
                // Reset duration if URL is nil
                audioDuration = nil
            }
        }
    }

    // --- Language Switching Properties ---
    public var currentLocale: Locale {
        didSet {
            // Persist or react to locale changes if needed beyond re-initialization
            if oldValue != currentLocale {
                // If locale changes, and we need to apply it immediately,
                // reconfigure the transcriber.
                // This is handled by changeLanguage a different way for now.
            }
        }
    }
    // Made internal to be accessible for re-init
    internal var transcriber: Transcriber?
    
    private var baseConfig: TranscriberConfiguration // To store other config settings
    private var recordingTask: Task<Void, Never>?
    private var onCompleteHandler: ((String) -> Void)?
    
    // +++ ADD THIS LINE BACK +++
    private let audioPlaybackService = AudioPlaybackService() // For playing back the recording

    public init(config: TranscriberConfiguration = TranscriberConfiguration()) {
        self.baseConfig = config // Store the initial/base configuration
        self.currentLocale = config.locale // Set current locale from initial config

        // Populate available locales.
        // For simplicity, using a predefined list.
        // You can use SFSpeechRecognizer.supportedLocales() for a dynamic list.
        // Note: SFSpeechRecognizer.supportedLocales() returns a Set<Locale>.
        // Ensure these locales are supported by the device/server.
        let locales = [
            Locale(identifier: "en-US"), // English (US)
            Locale(identifier: "es-ES"), // Spanish (Spain)
            Locale(identifier: "fr-FR"), // French (France)
            Locale(identifier: "de-DE"), // German (Germany)
            Locale(identifier: "ja-JP"), // Japanese (Japan)
            Locale(identifier: "zh-CN")  // Chinese (Simplified, Mainland) - if available
        ]
        // Filter against supported locales on device to be safe
        let supported = SFSpeechRecognizer.supportedLocales()
        self.availableLocales = locales.filter { supported.contains($0) }.sorted {
             ($0.localizedString(forIdentifier: $0.identifier) ?? $0.identifier) <
             ($1.localizedString(forIdentifier: $1.identifier) ?? $1.identifier)
        }
        // Ensure currentLocale is part of availableLocales or set a default
        if !self.availableLocales.contains(self.currentLocale), let firstAvailable = self.availableLocales.first {
            self.currentLocale = firstAvailable
            self.baseConfig = TranscriberConfiguration(
                locale: self.currentLocale, // Update baseConfig's locale as well
                silenceThreshold: config.silenceThreshold,
                silenceDuration: config.silenceDuration,
                languageModelInfo: config.languageModelInfo,
                requiresOnDeviceRecognition: config.requiresOnDeviceRecognition,
                shouldReportPartialResults: config.shouldReportPartialResults,
                contextualStrings: config.contextualStrings,
                taskHint: config.taskHint,
                addsPunctuation: config.addsPunctuation
            )
        }

        self.transcriber = Transcriber(config: self.baseConfig, debugLogging: true)
        
        #if os(iOS)
        setupAudioSession()
        self.fetchAvailableInputs()
        #endif
    }
    
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            // Configure for both playback and recording with all possible options
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [
                .allowAirPlay,
                .allowBluetooth,
                .allowBluetoothA2DP,
                .defaultToSpeaker
            ])
            // Set preferred I/O buffer duration
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
        } catch {
            fatalError("Error: \(error.localizedDescription)")
        }
    }

    // --- Method to Change Language ---
    public func changeLanguage(toLocale newLocale: Locale) async {
        guard currentLocale != newLocale else { return } // No change needed

        let wasRecording = self.isRecording

        if wasRecording {
            await stopRecordingProcess() // Stop current recording cleanly
        }

        currentLocale = newLocale
        // Create new configuration with the new locale, keeping other settings from baseConfig
        let newConfig = TranscriberConfiguration(
            locale: newLocale,
            silenceThreshold: baseConfig.silenceThreshold,
            silenceDuration: baseConfig.silenceDuration,
            languageModelInfo: baseConfig.languageModelInfo,
            // Check if on-device recognition is supported for the new locale
            // This might require querying SFSpeechRecognizer(locale: newLocale)?.supportsOnDeviceRecognition
            requiresOnDeviceRecognition: SFSpeechRecognizer(locale: newLocale)?.supportsOnDeviceRecognition == true ? baseConfig.requiresOnDeviceRecognition : false,
            shouldReportPartialResults: baseConfig.shouldReportPartialResults,
            contextualStrings: baseConfig.contextualStrings,
            taskHint: baseConfig.taskHint,
            addsPunctuation: baseConfig.addsPunctuation
        )
        self.baseConfig = newConfig // Update baseConfig if you want changes to persist across further locale changes

        // Re-initialize the transcriber
        self.transcriber = Transcriber(config: newConfig, debugLogging: true)
        if self.transcriber == nil {
            self.error = TranscriberError.noRecognizer // Or a more specific error
            print("Failed to initialize transcriber for locale: \(newLocale.identifier)")
            // Optionally, revert to the old locale or handle the error appropriately
            return
        }

        // Re-check authorization status for the new recognizer (optional, generally app-wide)
        // await requestAuthorization()
        // If authStatus changed or became .notAuthorized, handle it.

        if wasRecording {
            // Restart recording with the new language
            // Reset transcribedText as it's a new session
            self.transcribedText = ""
            self.audioDuration = nil
            self.lastRecordingURL = nil
            await startRecordingProcess()
        }
    }
    
    // Helper to stop recording process
    private func stopRecordingProcess() async {
        recordingTask?.cancel() // Cancel the task first
        // Wait for task to finish if it involves async operations before proceeding
        // For simplicity, we'll assume cancellation is quick enough or handled by transcriber.stopStream()
        await transcriber?.stopStream()
        self.lastRecordingURL = await transcriber?.getLAstRecordedAudioUrl()
        isRecording = false
        onCompleteHandler?(transcribedText) // Call completion handler for the stopped segment
        recordingTask = nil
    }
        
    // Helper to start recording process
    private func startRecordingProcess(onComplete: ((String) -> Void)? = nil) async {
        guard let transcriber else {
            error = TranscriberError.noRecognizer
            return
        }
        
        if let onComplete = onComplete { // If a new onComplete is provided
            self.onCompleteHandler = onComplete
        }

        // Reset relevant states for a new recording session
        self.transcribedText = ""
        self.error = nil // Clear previous errors

        recordingTask = Task {
            do {
                isRecording = true
                let stream = try await transcriber.startStream()
                
                for try await signal in stream {
                if Task.isCancelled { break }
                    switch signal {
                    case .rms(let float):
                        rmsLevel = float
                    case .transcription(let string):
                        transcribedText = string
                    }
                }
                if Task.isCancelled {
                     print("Recording task cancelled.")
                }
            } catch {
                if !(error is CancellationError) {
                    self.error = error
                    print("Error during transcription stream: \(error)")
                }
            }
            // This block runs after the stream ends or is cancelled
            isRecording = false
            if let currentURL = await self.transcriber?.getLAstRecordedAudioUrl() {
                 self.lastRecordingURL = currentURL
            }
            self.onCompleteHandler?(transcribedText)
        }
    }

    public func toggleRecording(onComplete: ((String) -> Void)? = nil) {
        Task {
            if isRecording {
                await stopRecordingProcess()
            } else {
                // Pass the onComplete handler to the start process
                await startRecordingProcess(onComplete: onComplete)
            }
        }
    }
    
    // Method to calculate audio duration
    private func calculateAudioDuration(for url: URL) async {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            self.audioDuration = CMTimeGetSeconds(duration)
            print("Presenter: Calculated audio duration: \(self.audioDuration ?? 0) seconds")
        } catch {
            print("Presenter: Error loading audio duration: \(error.localizedDescription)")
            self.audioDuration = nil
        }
    }

    public func playLastRecording() {
        guard let url = lastRecordingURL else {
            print("Presenter: No recording URL available to play.")
            // Optionally set an error or provide feedback to the user
            return
        }
        print("Presenter: Attempting to play \(url.path)")
        audioPlaybackService.playAudio(url: url)
    }
    
    public func requestAuthorization() async throws {
        guard let transcriber else {
            throw TranscriberError.noRecognizer
        }
        authStatus = await transcriber.requestAuthorization()
        guard authStatus == .authorized else {
            throw TranscriberError.notAuthorized
        }
    }
    
    #if os(iOS)
    public func fetchAvailableInputs() {
        availableInputs = AudioInputs.getAvailableInputs()
        // Set initial selection to current input
        if let currentInput = AVAudioSession.sharedInstance().currentRoute.inputs.first,
           let matchingInput = availableInputs.first(where: { $0.uid == currentInput.uid }) {
            selectedInput = matchingInput
        }
    }
    
    public func selectInput(_ input: AVAudioSessionPortDescription) {
        do {
            try AudioInputs.selectInput(input)
            selectedInput = input
        } catch {
            self.error = TranscriberError.audioSessionFailure(error)
        }
    }
    #endif
}
