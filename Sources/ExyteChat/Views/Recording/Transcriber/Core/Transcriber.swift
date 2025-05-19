import Speech
import AVFoundation
import OSLog

// MARK: - Speech Recognition Service
/// An actor that manages speech recognition operations using Apple's Speech framework
public actor Transcriber {
    private let config: TranscriberConfiguration
    private let speechRecognizer: SFSpeechRecognizer
    private let audioEngine: AVAudioEngine
    private let logger: DebugLogger
    
    private var outputAudioFile: AVAudioFile?
    private var audioFileUrl: URL? // To store the URL for potential playback
    
    private lazy var languageModelManager: LanguageModelManager? = {
        guard let modelInfo = config.languageModelInfo else { return nil }
        return LanguageModelManager(modelInfo: modelInfo)
    }()
    
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    // RMS streaming support
    private var rmsStream: AsyncStream<Float>?
    private var rmsContinuation: AsyncStream<Float>.Continuation?
    
    public init?(config: TranscriberConfiguration = TranscriberConfiguration(), debugLogging: Bool = false) {
        guard let recognizer = SFSpeechRecognizer(locale: config.locale) else { return nil }
        self.speechRecognizer = recognizer
        self.audioEngine = AVAudioEngine()
        self.config = config
        self.logger = DebugLogger(.transcriber, isEnabled: debugLogging)
    }
    
    /// Request authorization for speech recognition
    public func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
    
    
    // MARK: - Recognition Setup
    private func setupRecognition() throws -> SFSpeechAudioBufferRecognitionRequest {
        let request = SFSpeechAudioBufferRecognitionRequest()
        
        // Apply all configuration settings
        request.shouldReportPartialResults = config.shouldReportPartialResults
        request.requiresOnDeviceRecognition = config.requiresOnDeviceRecognition
        request.addsPunctuation = config.addsPunctuation
        request.taskHint = config.taskHint
        
        // Only set contextual strings if provided
        if let contextualStrings = config.contextualStrings {
            logger.debug("Setting contextual strings: \(contextualStrings)")
            request.contextualStrings = contextualStrings
        }
        
        // Store in actor state
        recognitionRequest = request
        return request
    }
    
    private func resetRecognitionState() {
        logger.debug("Resetting recognition state")
        recognitionTask?.cancel()
        recognitionTask = nil
    }
    
    // MARK: - RMS Stream Management
    /// Creates a new RMS stream for audio level monitoring
    /// - Returns: An AsyncStream of Float values representing audio RMS levels
    private func createRMSStream() -> AsyncStream<Float> {
        logger.debug("Creating RMS stream")
        
        // Clean up any existing stream
        rmsContinuation?.finish()
        rmsContinuation = nil
        
        // Create a new stream with continuation
        return AsyncStream { continuation in
            self.rmsContinuation = continuation
        }
    }
    
    /// Start a stream of speech recognition results
    /// - Returns: An AsyncThrowingStream of transcribed text and RMS values
    /// - Throws: TranscriberError if setup or recognition fails
    private func startCombinedStream() async throws -> AsyncThrowingStream<String, Error> {
        logger.debug("Starting transcription stream...")
        
        if let languageModelManager = languageModelManager {
            try await languageModelManager.waitForModel()
        }
        
        // Reset state
        resetRecognitionState()
        
        let localRequest = try setupRecognition()
        
        // Configure language model if available
        if let languageModel = languageModelManager {
            try await languageModel.waitForModel()
            if let lmConfig = await languageModel.getConfiguration() {
                localRequest.requiresOnDeviceRecognition = true
                localRequest.customizedLanguageModel = lmConfig
            }
        }
        
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let recordingFormat = inputNode.outputFormat(forBus: 0) // Used for saving audio file

        // Format for speech recognition processing (typically mono, float32)
        let processingFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: inputFormat.sampleRate, // Match input sample rate
            channels: 1,                         // Mono
            interleaved: false                   // Non-interleaved
        )

        var silenceState = SilenceState()
        
        // Create RMS stream and capture continuation locally
        rmsStream = createRMSStream()
        let localRMSContinuation = rmsContinuation

        
        // --- BEGIN AUDIO FILE SETUP (within actor context) ---
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.audioFileUrl = documentsPath.appendingPathComponent(UUID().uuidString + ".caf")
        
        var capturedOutputAudioFile: AVAudioFile? // Variable to capture for the tap
        if let audioFileUrl = self.audioFileUrl {
            self.logger.debug("Attempting to save audio to: \(audioFileUrl.path)")
            do {
                // settings: recordingFormat.settings uses the microphone's native format for saving
                let newAudioFile = try AVAudioFile(forWriting: audioFileUrl,
                                                 settings: recordingFormat.settings,
                                                 commonFormat: recordingFormat.commonFormat,
                                                 interleaved: recordingFormat.isInterleaved)
                self.outputAudioFile = newAudioFile // Assign to actor property
                capturedOutputAudioFile = newAudioFile // Capture the instance for the tap
                self.logger.debug("Output audio file initialized.")
            } catch {
                self.logger.error("Could not create output audio file: \(error.localizedDescription)")
                self.outputAudioFile = nil
                // capturedOutputAudioFile remains nil
                // Decide if this should be a fatal error. For now, logging and continuing.
            }
        }
        // --- END AUDIO FILE SETUP ---
        
        guard let processingFormat = processingFormat else {
            throw TranscriberError.engineFailure(NSError(
                domain: "Transcriber",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Could not create processing format"]))
        }
        
        // Add converter for stereo signals
        let converter = AVAudioConverter(from: inputFormat, to: processingFormat)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            
            let rms = buffer.calculateRMS()
            let currentTime = CFAbsoluteTimeGetCurrent()
            
            self.logger.debug("RMS: \(rms)")
            // Send RMS value to stream using local continuation
            localRMSContinuation?.yield(rms)
            
            // --- BEGIN AUDIO FILE WRITING ---
            if let outputFile = capturedOutputAudioFile { // Use captured AVAudioFile instance
                do {
                    try outputFile.write(from: buffer)
                } catch {
                    self.logger.error("Error writing audio buffer to file: \(error.localizedDescription)")
                }
            }
            // --- END AUDIO FILE WRITING ---
            
            // Send RMS value to stream using local continuation
            if silenceState.update(
                rms: rms,
                currentTime: currentTime,
                threshold: self.config.silenceThreshold,
                duration: self.config.silenceDuration
            ) {
                self.logger.debug("Silence detected, keep a log for now...")
//                localRequest.endAudio()
//                Task { @MainActor in
//                    await self.stopStream()
//                }
//                return
            }
            
            // Convert buffer for stereo signal to mono
            if let converter = converter {
                let frameCount = AVAudioFrameCount(buffer.frameLength)
                guard let convertedBuffer = AVAudioPCMBuffer(
                    pcmFormat: processingFormat,
                    frameCapacity: frameCount)
                else { return }
                
                var error: NSError?
                let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
                    outStatus.pointee = .haveData
                    return buffer
                }
                
                converter.convert(to: convertedBuffer,
                                error: &error,
                                withInputFrom: inputBlock)
                
                if error == nil {
                    localRequest.append(convertedBuffer)
                }
            } else {
                localRequest.append(buffer)
            }
        }
        
        // Start audio engine
        do {
            audioEngine.prepare()
            try audioEngine.start()
            logger.debug("Audio engine started")
        } catch {
            logger.error("Audio engine start failed: \(error.localizedDescription)")
            throw TranscriberError.engineFailure(error)
        }

        // Create and return stream
        return AsyncThrowingStream { continuation in
            createRecognitionTask(request: localRequest, continuation: continuation)
        }
    }
    
    // MARK: - Recognition Task Management
    private func createRecognitionTask(
        request: SFSpeechAudioBufferRecognitionRequest,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) {
        let task = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            if let result {
                let transcription = result.bestTranscription.formattedString
                self?.logger.debug("Transcription update: \(transcription)")
                continuation.yield(transcription)
            }
            if let error {
                self?.logger.error("Recognition error: \(error.localizedDescription)")
                continuation.finish(throwing: TranscriberError.recognitionFailure(error))
            } else if result?.isFinal == true {
                self?.logger.debug("Recognition completed")
                continuation.finish()
            }
        }
        recognitionTask = task
    }
    
    private func stopStreamInternal() {
        logger.debug("Stopping recording internally")
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0) // Remove tap first
            audioEngine.stop()
            logger.debug("Audio engine stopped and tap removed.")
        }

        recognitionRequest?.endAudio() // Signal end of audio to recognition request
        logger.debug("Signaled endAudio to recognition request.")

        // Finalize and close the audio file
        if outputAudioFile != nil { // If it was successfully created
            logger.debug("Finalizing audio file at: \(self.audioFileUrl?.path ?? "Unknown path")")
        }
        outputAudioFile = nil // Deinitializes AVAudioFile, which closes it.

        rmsContinuation?.finish()
        rmsContinuation = nil
        rmsStream = nil // Release the stream
        logger.debug("RMS stream finished and cleaned up.")

        recognitionTask?.cancel() // Cancel before niling out
        recognitionTask = nil
        recognitionRequest = nil // Release request object
        logger.debug("Recognition task cancelled and request cleaned up.")
        logger.debug("stopStreamInternal completed.")
    }
    
    /// Stop the current recording session
    public func stopStream() {
        // This is an actor method, so it's already on the actor's executor.
        // No need for an extra Task here.
        stopStreamInternal()
    }
    
    public func getLAstRecordedAudioUrl() -> URL? {
        return self.audioFileUrl
    }
    
    /// Start a stream that provides both transcription and RMS values in a unified stream
    ///
    /// This method returns a single stream that emits both transcription text and audio level (RMS) values
    /// as they become available. The stream emits values as `TranscriberSignal` enum cases:
    ///
    /// - `.transcription(String)`: Contains the latest transcribed text from speech recognition
    /// - `.rms(Float)`: Contains the latest Root Mean Square audio level (0.0-1.0) for visualizing audio input
    ///
    /// Example usage:
    /// ```swift
    /// let stream = try await transcriber.startStream()
    /// for await signal in stream {
    ///     switch signal {
    ///     case .transcription(let text):
    ///         // Update UI with transcribed text
    ///         updateTranscriptionLabel(text)
    ///     case .rms(let level):
    ///         // Update audio visualization
    ///         updateAudioLevelIndicator(level)
    ///     }
    /// }
    /// ```
    ///
    /// - Returns: An AsyncStream of TranscriberSignal values containing either transcription or RMS data
    /// - Throws: TranscriberError if setup or recognition fails
    public func startStream() async throws -> AsyncStream<TranscriberSignal> {
        // Start the transcription stream
        let transcriptionStream = try await startCombinedStream()
        
        // Create a combined stream
        return AsyncStream<TranscriberSignal> { continuation in
            // Task for handling transcription values
            Task {
                do {
                    for try await transcription in transcriptionStream {
                        continuation.yield(.transcription(transcription))
                    }
                } catch {
                    logger.error("Transcription stream error: \(error.localizedDescription)")
                    // We don't finish the continuation here as RMS might still be active
                }
                // When transcription ends naturally, we don't finish the stream
                // as RMS values might still be coming
            }
            
            // Task for handling RMS values
            if let rmsStream = self.rmsStream {
                Task {
                    for await rms in rmsStream {
                        continuation.yield(.rms(rms))
                    }
                    // When RMS stream ends, we can finish the combined stream
                    continuation.finish()
                }
            }
        }
    }
    
    // Add this new public method inside the Transcriber actor
    public func transcribeAudioFile(url: URL) async throws -> String {
        logger.debug("Starting transcription for audio file: \(url.path) with locale: \(self.config.locale.identifier)")
        
        guard speechRecognizer.isAvailable else {
            logger.error("Speech recognizer is not available for locale: \(self.config.locale.identifier)")
            throw TranscriberError.noRecognizer
        }
        
        let request = SFSpeechURLRecognitionRequest(url: url)
        // Configure the request using the current `self.config`
        request.shouldReportPartialResults = false // Typically false for file-based transcription
        request.requiresOnDeviceRecognition = config.requiresOnDeviceRecognition
        request.addsPunctuation = config.addsPunctuation
        request.taskHint = config.taskHint
        if let contextualStrings = config.contextualStrings {
            request.contextualStrings = contextualStrings
        }
        
        // Apply custom language model if configured
        if let languageModelManager = languageModelManager {
            try await languageModelManager.waitForModel()
            if let lmConfig = await languageModelManager.getConfiguration() {
                request.requiresOnDeviceRecognition = true // Custom LM usually implies on-device
                request.customizedLanguageModel = lmConfig
                logger.debug("Applied custom language model for file transcription.")
            }
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            // Keep a reference to the task if you need to cancel it, though for this flow it might not be necessary.
            _ = speechRecognizer.recognitionTask(with: request) { (result, error) in
                if let error = error {
                    self.logger.error("Audio file recognition error: \(error.localizedDescription)")
                    continuation.resume(throwing: TranscriberError.recognitionFailure(error))
                    return
                }
                
                guard let result = result else {
                    self.logger.error("Audio file recognition: No result and no error.")
                    // Create a more specific error or use a generic one
                    continuation.resume(throwing: TranscriberError.recognitionFailure(
                        NSError(domain: "Transcriber", code: -2, userInfo: [NSLocalizedDescriptionKey: "No recognition result."])
                    ))
                    return
                }
                
                // We expect isFinal to be true since shouldReportPartialResults is false.
                if result.isFinal {
                    let transcription = result.bestTranscription.formattedString
                    self.logger.debug("Audio file recognition final transcription: \(transcription)")
                    continuation.resume(returning: transcription)
                }
                // If not isFinal, and no error, something unexpected happened for a non-partial request.
                // This path should ideally not be hit if shouldReportPartialResults is false.
            }
        }
    }
}

// MARK: - SilenceState
extension Transcriber {
    internal struct SilenceState {
        var isSilent: Bool = false
        var startTime: CFAbsoluteTime = 0
        var hasEnded: Bool = false
        
        mutating func update(rms: Float, currentTime: CFAbsoluteTime, threshold: Float, duration: TimeInterval) -> Bool {
            if rms < threshold {
                if !isSilent {
                    isSilent = true
                    startTime = currentTime
                } else if !hasEnded && (currentTime - startTime) >= duration {
                    hasEnded = true
                    return true
                }
            } else {
                isSilent = false
            }
            return false
        }
    }
}
