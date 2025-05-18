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
    
    private var baseConfig: TranscriberConfiguration
    private var recordingTask: Task<Void, Error>? // Changed to throws Error for better error propagation
    
    // For startRecordingWithProgress
    private var progressHandler: TranscriptionProgressHandler?
    private var recordingCompletionHandler: ((String, URL?) -> Void)?
    var recordingStartTime: Date?
    private var currentWaveformSamples: [CGFloat] = []
    
    private let audioPlaybackService = AudioPlaybackService()
    
    /// Callback type for live transcription progress.
    /// Parameters: current duration (TimeInterval), waveform samples ([CGFloat]), current transcribed text (String).
    public typealias TranscriptionProgressHandler = @Sendable (TimeInterval, [CGFloat], String) -> Void
    
    public init(config: TranscriberConfiguration = TranscriberConfiguration()) {
        self.baseConfig = config // Store the initial/base configuration
        self.currentLocale = config.locale // Set current locale from initial config
        
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
            await stopRecording() // Use the public stop method
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
        
        if wasRecording {
            // Restart recording with the new language
            // Reset transcribedText as it's a new session
            self.transcribedText = ""
            self.audioDuration = nil
            self.lastRecordingURL = nil
            //            await startRecordingWithProgress()
        }
    }
    
    /// Starts a transcription session with live progress updates.
    /// - Parameters:
    ///   - progressHandler: Called periodically with current duration, waveform samples, and transcribed text.
    ///   - completionHandler: Called when transcription stops (naturally or manually), providing final text and audio URL.
    /// - Throws: `TranscriberError` if setup fails or transcriber is unavailable.
    @MainActor
    public func startRecordingWithProgress(
        progressHandler: @escaping TranscriptionProgressHandler,
        completionHandler: @escaping (_ finalText: String, _ finalURL: URL?) -> Void
    ) async throws {
        guard let transcriber = self.transcriber else {
            self.error = TranscriberError.noRecognizer
            throw TranscriberError.noRecognizer
        }
        
        if isRecording {
            DebugLogger.log("startRecordingWithProgress: Already recording. Stopping previous session first.")
            await stopRecording() // Ensure clean state by stopping any existing recording
        }
        
        // Store handlers
        self.progressHandler = progressHandler
        self.recordingCompletionHandler = completionHandler
        
        // Reset states for the new session
        self.transcribedText = ""
        self.error = nil
        self.rmsLevel = 0.0
        self.audioDuration = nil
        self.lastRecordingURL = nil
        self.currentWaveformSamples = []
        self.recordingStartTime = Date()
        
        isRecording = true
        DebugLogger.log("startRecordingWithProgress: Recording started at \(self.recordingStartTime!)")
        
        // The recordingTask will consume the stream and call handlers.
        recordingTask = Task {
            do {
                let stream = try await transcriber.startStream()
                for try await signal in stream {
                    if Task.isCancelled {
                        DebugLogger.log("startRecordingWithProgress: Task cancelled during stream consumption.")
                        await handleRecordingStop(finalText: self.transcribedText, wasCancelled: true)
                        throw CancellationError() // Propagate cancellation
                    }
                    
                    guard let startTime = self.recordingStartTime else {
                        // This should not happen if isRecording is true and startTime was set
                        DebugLogger.log("startRecordingWithProgress: recordingStartTime is nil while processing stream. Stopping.")
                        await handleRecordingStop(finalText: self.transcribedText, error: TranscriberError.invalidRequest)
                        throw TranscriberError.invalidRequest
                    }
                    let currentDuration = Date().timeIntervalSince(startTime)
                    
                    switch signal {
                    case .rms(let float):
                        self.rmsLevel = float
                        self.currentWaveformSamples.append(CGFloat(float))
                        // Optional: Prune samples if they grow too large
                        if self.currentWaveformSamples.count > 40 { // Keep approx 3 seconds of samples at 100 samples/sec
                            self.currentWaveformSamples.removeFirst(self.currentWaveformSamples.count - 40)
                        }
                        self.progressHandler?(currentDuration, self.currentWaveformSamples, self.transcribedText)
                    case .transcription(let string):
                        self.transcribedText = string
                        self.progressHandler?(currentDuration, self.currentWaveformSamples, self.transcribedText)
                    }
                }
                // Stream finished naturally
                DebugLogger.log("startRecordingWithProgress: Stream finished naturally.")
                await handleRecordingStop(finalText: self.transcribedText)
            } catch {
                if !(error is CancellationError) {
                    DebugLogger.log("startRecordingWithProgress: Error during transcription stream: \(error.localizedDescription)")
                    self.error = error
                }
                await handleRecordingStop(finalText: self.transcribedText, error: error, wasCancelled: error is CancellationError)
                throw error // Re-throw to ensure the task completes with an error if one occurred
            }
        }
    }
    
    /// Stops the current transcription session if one is active.
    @MainActor
    public func stopRecording() async {
        DebugLogger.log("stopRecording called. isRecording: \(isRecording)")
        if !isRecording {
            // If not recording, but task might still be cleaning up, ensure it's cancelled.
            if recordingTask?.isCancelled == false {
                recordingTask?.cancel()
            }
            return
        }
        // Cancel the task. The cancellation/completion handler within the task will do the cleanup.
        recordingTask?.cancel()
        // `handleRecordingStop` will be invoked through the task's cancellation path.
        // We wait for the task to ensure cleanup is complete before this method returns.
        _ = await recordingTask?.result // Wait for the task to finish
        recordingTask = nil // Clear the task reference
    }
    
    @MainActor
    private func handleRecordingStop(finalText: String, error: Error? = nil, wasCancelled: Bool = false) async {
        if !isRecording && !wasCancelled { // Avoid redundant calls if already stopped by another path
            DebugLogger.log("handleRecordingStop: Already stopped or not a direct cancellation stop. Current isRecording: \(isRecording)")
            return
        }
        
        DebugLogger.log("handleRecordingStop: Finalizing recording. WasCancelled: \(wasCancelled)")
        isRecording = false // Set immediately
        
        await self.transcriber?.stopStream()
        self.lastRecordingURL = await self.transcriber?.getLAstRecordedAudioUrl()
        if let url = self.lastRecordingURL {
            await self.calculateAudioDuration(for: url) // Sets self.audioDuration
        }
        
        DebugLogger.log("handleRecordingStop: Calling completion handler. FinalText: '\(finalText)', URL: \(self.lastRecordingURL?.path ?? "nil")")
        self.recordingCompletionHandler?(finalText, self.lastRecordingURL)
        
        // Clear handlers and state for the next session
        self.progressHandler = nil
        self.recordingCompletionHandler = nil
        self.recordingStartTime = nil
        self.currentWaveformSamples = []
        
        if let error = error, !(error is CancellationError) {
            self.error = error
        }
        DebugLogger.log("handleRecordingStop: Completed. Final URL: \(self.lastRecordingURL?.path ?? "nil"), Duration: \(self.audioDuration ?? 0)")
    }
    
    // Existing toggleRecording - can be kept for simpler use cases or refactored/removed
    public func toggleRecording(onComplete: ((String) -> Void)? = nil) {
        Task {
            if isRecording {
                await stopRecording() // Uses the new stop method
                // The onComplete for toggleRecording is different from recordingCompletionHandler
                // If startRecordingWithProgress was used, its completionHandler takes precedence.
                // This might need careful thought if both APIs are active.
                // For now, stopRecording will trigger the recordingCompletionHandler if it was set.
                // If toggleRecording needs its own separate completion, it should manage it.
                if let onComplete = onComplete {
                    onComplete(self.transcribedText) // Provide current text
                }
            } else {
                // If toggleRecording is to use the new progress system, it needs to provide handlers.
                // For simplicity, let's assume toggleRecording starts a session that only calls its onComplete.
                // This means it won't provide live progress updates unless we adapt it.
                // For now, let it use a simplified version of startRecordingProcess.
                
                self.transcribedText = ""
                self.error = nil
                self.isRecording = true
                self.recordingStartTime = Date()
                
                recordingTask = Task {
                    do {
                        guard let transcriber = self.transcriber else { throw TranscriberError.noRecognizer }
                        let stream = try await transcriber.startStream()
                        
                        for try await signal in stream {
                            if Task.isCancelled { break }
                            switch signal {
                            case .rms(let float): self.rmsLevel = float
                            case .transcription(let string): self.transcribedText = string
                            }
                        }
                        if !Task.isCancelled { // Stream finished naturally
                            await handleRecordingStop(finalText: self.transcribedText) // Use common stop logic
                            onComplete?(self.transcribedText)
                        } else { // Task was cancelled
                            await handleRecordingStop(finalText: self.transcribedText, wasCancelled: true)
                        }
                    } catch {
                        if !(error is CancellationError) { self.error = error }
                        await handleRecordingStop(finalText: self.transcribedText, error: error, wasCancelled: error is CancellationError)
                    }
                }
            }
        }
    }
    
    @MainActor
    public func calculateAudioDuration(for url: URL) async {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            self.audioDuration = CMTimeGetSeconds(duration)
            DebugLogger.log("Presenter: Calculated audio duration: \(self.audioDuration ?? 0) seconds for URL: \(url.lastPathComponent)")
        } catch {
            DebugLogger.log("Presenter: Error loading audio duration for \(url.lastPathComponent): \(error.localizedDescription)")
            self.audioDuration = nil
        }
    }
    
    public func playLastRecording() {
        guard let url = lastRecordingURL else {
            DebugLogger.log("Presenter: No recording URL available to play.")
            return
        }
        DebugLogger.log("Presenter: Attempting to play \(url.path)")
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
