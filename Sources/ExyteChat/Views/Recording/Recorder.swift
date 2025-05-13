// Chat/Sources/ExyteChat/Views/Recording/Recorder.swift
import Foundation
import AVFoundation

final actor Recorder {
    typealias ProgressHandler = @Sendable (Double, [CGFloat]) -> Void

    private let audioSession = AVAudioSession.sharedInstance()
    private var audioRecorder: AVAudioRecorder?
    private var progressUpdateTask: Task<Void, Never>?

    private var currentRecordingURL: URL?
    private var currentWaveformSamples: [CGFloat] = []
    private var currentDuration: TimeInterval = 0
    private let maxWaveformSamples = 100 // Define the maximum number of samples


    private var recorderSettings = RecorderSettings()

    var isAllowedToRecordAudio: Bool {
        audioSession.recordPermission == .granted
    }

    var isRecording: Bool {
        audioRecorder?.isRecording ?? false
    }

    init() {
        Logger.log("Recorder init")
        // Defer session category setup until it's actually needed (in startRecording)
    }

    func setRecorderSettings(_ recorderSettings: RecorderSettings) {
        self.recorderSettings = recorderSettings
        Logger.log("Settings updated: \(recorderSettings)")
    }

    func requestDirectPermission() async -> Bool {
        if isAllowedToRecordAudio { return true }
        Logger.log("Requesting direct audio permission.")
        return await audioSession.requestRecordPermission()
    }

    func startRecording(durationProgressHandler: @escaping ProgressHandler) async -> URL? {
            Logger.log("Attempting to start recording. Current recorder state: \(audioRecorder != nil), isRecording: \(self.isRecording)")
            guard isAllowedToRecordAudio else {
                Logger.log("StartRecording called but permission not granted.")
                return nil
            }

            if audioRecorder != nil {
                Logger.log("Existing audioRecorder instance found. Ensuring it's stopped and cleaned up.")
                _ = stopRecording() // This nils out audioRecorder and cancels task
            }

            currentWaveformSamples = []
            currentDuration = 0
            
            let newRecordingUrl = FileManager.tempDirPath.appendingPathComponent(UUID().uuidString + (fileExtension(for: recorderSettings.audioFormatID) ?? ".m4a"))
            self.currentRecordingURL = newRecordingUrl

            let settings: [String : Any] = [
                    AVFormatIDKey: Int(recorderSettings.audioFormatID),
                    AVSampleRateKey: recorderSettings.sampleRate,
                    AVNumberOfChannelsKey: recorderSettings.numberOfChannels,
                    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
                ]

            do {
                Logger.log("Configuring audio session for recording.")
                // Check if session is active and in a different category/mode.
                // If so, it's often safer to deactivate before changing category.
                if audioSession.category != .playAndRecord || audioSession.mode != .default {
                    Logger.log("Session category/mode is NOT .playAndRecord/default (current: \(audioSession.category.rawValue)/\(audioSession.mode.rawValue)).")
                    // Deactivate if it's active in another category, to allow clean category change.
                    // This check `audioSession.isOtherAudioPlaying` might not be fully reliable for session's own active state.
                    // A direct check of `AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint` or if the app truly believes it should be active.
                    // For now, let's assume if category is wrong, we force reconfiguration.
                    if audioSession.isInputAvailable { // A proxy for "is it potentially active in some form?"
                        // It is generally not recommended to call setActive(false) if other audio (like music) is playing,
                        // unless you intend to interrupt it. But here, we are about to record, which will interrupt.
                        do {
                            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
                            Logger.log("Audio session deactivated to change category.")
                        } catch {
                            Logger.log("Failed to deactivate audio session before category change: \(error). Proceeding with setCategory.")
                            // Potentially problematic, but setCategory might still work or throw its own error.
                        }
                    }
                    try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP, .allowAirPlay])
                    Logger.log("Audio session category set to .playAndRecord/default.")
                }
                
                let activationStartTime = Date()
                try audioSession.setActive(true)
                Logger.log("Audio session setActive(true) called for recording. Time taken: \(Date().timeIntervalSince(activationStartTime) * 1000) ms.")

                // ... (rest of AVAudioRecorder setup and start as in your last version) ...
                // ... (including progressUpdateTask) ...
                audioRecorder = try AVAudioRecorder(url: newRecordingUrl, settings: settings)
                guard let strongAudioRecorder = audioRecorder else {
                     Logger.log("Failed to initialize AVAudioRecorder after session activation.")
                     Task { try? audioSession.setActive(false, options: .notifyOthersOnDeactivation) }
                     return nil
                }
                strongAudioRecorder.isMeteringEnabled = true

                if strongAudioRecorder.prepareToRecord() {
                    if strongAudioRecorder.record() {
                        Logger.log("Recording started successfully at URL: \(newRecordingUrl.path).")
                        durationProgressHandler(0.0, [])

                        progressUpdateTask?.cancel()
                        progressUpdateTask = Task { [weak self] in
                            var lastTickTime = Date()
                            while true {
                                guard let self = await self else {
                                    Logger.log("Progress update task: self is nil, terminating.")
                                    break
                                }
                                if Task.isCancelled {
                                    Logger.log("Progress update task: cancelled, terminating.")
                                    break
                                }
                                // Check both actor's recording flag and the AVAudioRecorder's state
                                guard await self.isRecording, let internalRec = await self.audioRecorder, internalRec.isRecording else {
                                    Logger.log("Progress update task: No longer recording (isRecording: \(await self.isRecording), internalRec exists: \(await self.audioRecorder != nil), internalRec.isRecording: \(await self.audioRecorder?.isRecording ?? false)), terminating.")
                                    break
                                }
                                await self.onTimerTick(durationProgressHandler)
                                do {
                                    let nextFireTime = lastTickTime.addingTimeInterval(0.1) // Target 0.1s interval
                                    try await Task.sleep(until: .now + .nanoseconds(UInt64(max(0, nextFireTime.timeIntervalSinceNow * 1_000_000_000))), clock: .continuous)
                                    lastTickTime = nextFireTime // Can also use Date() for more drift-resistant but potentially less smooth UI
                                } catch {
                                    Logger.log("Progress update task: sleep interrupted (likely cancellation), terminating. Error: \(error)")
                                    break
                                }
                            }
                            Logger.log("Progress update task loop finished.")
                        } // Same as before
                        return newRecordingUrl
                    } else { // record() failed
                        Logger.log("audioRecorder.record() returned false.")
                        Task { try? audioSession.setActive(false, options: .notifyOthersOnDeactivation) }
                        self.audioRecorder = nil; self.currentRecordingURL = nil;
                    }
                } else { // prepareToRecord() failed
                    Logger.log("audioRecorder.prepareToRecord() returned false.")
                    Task { try? audioSession.setActive(false, options: .notifyOthersOnDeactivation) }
                    self.audioRecorder = nil; self.currentRecordingURL = nil;
                }

            } catch {
                Logger.log("Error during recording setup/start: \(error.localizedDescription)")
                Task { try? audioSession.setActive(false, options: .notifyOthersOnDeactivation) }
                audioRecorder = nil; self.currentRecordingURL = nil;
            }
            
            stopRecordingCleanupInternals()
            return nil
        }

    private func onTimerTick(_ durationProgressHandler: @escaping ProgressHandler) {
        guard let recorder = audioRecorder, recorder.isRecording else {
            // Logger.log("onTimerTick: Recorder not valid or not recording.") // Can be too verbose
            return
        }
        recorder.updateMeters()
        currentDuration = recorder.currentTime
        let power = recorder.averagePower(forChannel: 0)
        if power.isFinite && !power.isNaN && power >= -160.0 {
            let normalizedPower = max(0, (power + 60) / 60)
            currentWaveformSamples.append(CGFloat(normalizedPower))
        } else {
            currentWaveformSamples.append(0.02)
        }
        // Cap the number of samples
        if currentWaveformSamples.count > maxWaveformSamples {
            currentWaveformSamples.removeFirst(currentWaveformSamples.count - maxWaveformSamples)
        }
        Logger.log("onTimerTick: Calling durationProgressHandler with duration \(currentDuration), samples count \(currentWaveformSamples.count)")
        durationProgressHandler(currentDuration, currentWaveformSamples)
    }
    
    func stopRecording() -> (duration: Double, samples: [CGFloat], url: URL?) {
        Logger.log("stopRecording called. Current recorder state: \(audioRecorder != nil), isRecording: \(self.isRecording)")
        var finalDuration = self.currentDuration
        var finalSamples = self.currentWaveformSamples
        let urlForThisRecording = self.currentRecordingURL

        if let recorder = audioRecorder {
            if recorder.isRecording {
                recorder.updateMeters()
                finalDuration = recorder.currentTime
                let power = recorder.averagePower(forChannel: 0)
                if power.isFinite && !power.isNaN && power >= -160.0 {
                    let normalizedPower = max(0, (power + 60) / 60)
                    finalSamples.append(CGFloat(normalizedPower))
                } else {
                    finalSamples.append(0.02)
                }
               
                if finalSamples.count > maxWaveformSamples {
                    finalSamples.removeFirst(finalSamples.count - maxWaveformSamples)
                }
                recorder.stop()
                Logger.log("Recording hardware stopped. Duration at stop: \(finalDuration). Samples collected: \(finalSamples.count)")
            } else {
                finalDuration = recorder.currentTime
                Logger.log("stopRecording: recorder was not actively recording. Duration from recorder: \(finalDuration). Using currentDuration if greater: \(self.currentDuration)")
                if finalDuration < 0.01 && self.currentDuration > 0.01 {
                    finalDuration = self.currentDuration
                    finalSamples = self.currentWaveformSamples
                }
            }
        } else {
            Logger.log("stopRecording: audioRecorder was nil. Using current properties.")
        }
        
        stopRecordingCleanupInternals()

        let result = (duration: finalDuration, samples: finalSamples, url: urlForThisRecording)
        
        self.currentDuration = 0
        self.currentWaveformSamples = []
        // self.currentRecordingURL = nil; // URL is part of result
        
        Logger.log("stopRecording returning: Duration=\(result.duration), Samples=\(result.samples.count), URL=\(result.url?.lastPathComponent ?? "nil")")
        return result
    }

    private func stopRecordingCleanupInternals() {
        progressUpdateTask?.cancel()
        progressUpdateTask = nil

        if audioRecorder != nil {
            if audioRecorder!.isRecording {
                Logger.log("Cleanup: audioRecorder was still marked as recording, stopping it now.")
                audioRecorder!.stop()
            }
            audioRecorder = nil
        }
        Logger.log("Internal cleanup: progress task cancelled/nil, recorder instance nilled.")
        
        // Strategy: Leave session active after recording stops to reduce latency for immediate playback or next recording.
        // If explicit deactivation is desired here, it would be:
        // Task {
        //     do {
        //         try self.audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        //         Logger.log("Audio session deactivated in stopRecordingCleanupInternals.")
        //     } catch {
        //         Logger.log("Error deactivating audio session in stopRecordingCleanupInternals: \(error)")
        //     }
        // }
        Logger.log("Audio session intentionally NOT deactivated in Recorder.stopRecordingCleanupInternals.")
    }
    
    private func fileExtension(for formatID: AudioFormatID) -> String? {
        switch formatID {
        case kAudioFormatMPEG4AAC: return ".aac"
        case kAudioFormatLinearPCM: return ".wav"
        default:
            Logger.log("Unknown audio format ID: \(formatID), defaulting to .audio")
            return ".audio"
        }
    }
}

// RecorderSettings and AVAudioSession extension remain the same
// MARK: - Recorder Settings Struct (Keep as is)
public struct RecorderSettings: Codable, Hashable, Sendable {
    var audioFormatID: AudioFormatID
    var sampleRate: CGFloat
    var numberOfChannels: Int
    var encoderBitRateKey: Int
    var linearPCMBitDepth: Int
    var linearPCMIsFloatKey: Bool
    var linearPCMIsBigEndianKey: Bool
    var linearPCMIsNonInterleaved: Bool

    public init(audioFormatID: AudioFormatID = kAudioFormatMPEG4AAC,
                sampleRate: CGFloat = 44100.0,
                numberOfChannels: Int = 1,
                encoderBitRateKey: Int = 128000,
                linearPCMBitDepth: Int = 16,
                linearPCMIsFloatKey: Bool = false,
                linearPCMIsBigEndianKey: Bool = false,
                linearPCMIsNonInterleaved: Bool = false) {
        self.audioFormatID = audioFormatID
        self.sampleRate = sampleRate
        self.numberOfChannels = numberOfChannels
        self.encoderBitRateKey = encoderBitRateKey
        self.linearPCMBitDepth = linearPCMBitDepth
        self.linearPCMIsFloatKey = linearPCMIsFloatKey
        self.linearPCMIsBigEndianKey = linearPCMIsBigEndianKey
        self.linearPCMIsNonInterleaved = linearPCMIsNonInterleaved
    }
}

// MARK: - AVAudioSession Extension (Keep as is)
extension AVAudioSession {
    func requestRecordPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
