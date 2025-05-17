//
//  Recorder.swift
//  


import Foundation
import AVFoundation

final actor Recorder {

    // duration and waveform samples
    typealias ProgressHandler = @Sendable (Double, [CGFloat]) -> Void

    private let audioSession = AVAudioSession.sharedInstance()
    private var audioRecorder: AVAudioRecorder?
    private var audioTimer: Task<Void, Never>?
    
    private var currentRecordingURL: URL?
    private var currentDuration: TimeInterval = 0
    private var soundSamples: [CGFloat] = []
    private var recorderSettings = RecorderSettings()

    var isAllowedToRecordAudio: Bool {
        AVAudioApplication.shared.recordPermission == .granted
    }

    var isRecording: Bool {
        audioRecorder?.isRecording ?? false
    }

    func setRecorderSettings(_ recorderSettings: RecorderSettings) {
        self.recorderSettings = recorderSettings
    }
    
    func requestDirectPermission() async -> Bool {
        if isAllowedToRecordAudio { return true }
        DebugLogger.log("Requesting direct audio permission.")
        return await audioSession.requestRecordPermission()
    }

    func startRecording(durationProgressHandler: @escaping ProgressHandler) async -> URL? {
        if !isAllowedToRecordAudio {
            let granted = await audioSession.requestRecordPermission()
            if granted {
                return startRecordingInternal(durationProgressHandler)
            }
            return nil
        } else {
            return startRecordingInternal(durationProgressHandler)
        }
    }
    
    private func startRecordingInternal(_ durationProgressHandler: @escaping ProgressHandler) -> URL? {
        let settings: [String : Any] = [
            AVFormatIDKey: Int(recorderSettings.audioFormatID),
            AVSampleRateKey: recorderSettings.sampleRate,
            AVNumberOfChannelsKey: recorderSettings.numberOfChannels,
            AVEncoderBitRateKey: recorderSettings.encoderBitRateKey,
            AVLinearPCMBitDepthKey: recorderSettings.linearPCMBitDepth,
            AVLinearPCMIsFloatKey: recorderSettings.linearPCMIsFloatKey,
            AVLinearPCMIsBigEndianKey: recorderSettings.linearPCMIsBigEndianKey,
            AVLinearPCMIsNonInterleaved: recorderSettings.linearPCMIsNonInterleaved,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        soundSamples = []
        guard let fileExt = fileExtension(for: recorderSettings.audioFormatID) else{
            return nil
        }
        let recordingUrl = FileManager.tempDirPath.appendingPathComponent(UUID().uuidString + fileExt)
        self.currentRecordingURL = recordingUrl
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP, .allowAirPlay])
            try audioSession.setActive(true)
            let localAudioRecorder = try AVAudioRecorder(url: recordingUrl, settings: settings)
            localAudioRecorder.isMeteringEnabled = true
            localAudioRecorder.prepareToRecord()
            localAudioRecorder.record()

            self.audioRecorder = localAudioRecorder;
            durationProgressHandler(0.0, [])
            
            audioTimer?.cancel()
            audioTimer = Task { [weak self] in
                var lastTickTime = Date()
                while true {
                    guard let mine = await self else {
                        DebugLogger.log("Progress update task: self is nil, terminating.")
                        break
                    }
                    if Task.isCancelled {
                        DebugLogger.log("Progress update task: cancelled, terminating.")
                        break
                    }
                    // Check both actor's recording flag and the AVAudioRecorder's state
                    guard await mine.isRecording, let internalRec = await mine.audioRecorder, internalRec.isRecording else {
                        DebugLogger.log("Progress update task: No longer recording (isRecording: \(await mine.isRecording), internalRec exists: \(await mine.audioRecorder != nil), internalRec.isRecording: \(await mine.audioRecorder?.isRecording ?? false)), terminating.")
                        continue
                    }
                    await mine.onTimer(durationProgressHandler)
                    do {
                        let nextFireTime = lastTickTime.addingTimeInterval(0.1) // Target 0.1s interval
                        try await Task.sleep(until: .now + .nanoseconds(UInt64(max(0, nextFireTime.timeIntervalSinceNow * 1_000_000_000))), clock: .continuous)
                        lastTickTime = nextFireTime // Can also use Date() for more drift-resistant but potentially less smooth UI
                    } catch {
                        DebugLogger.log("Progress update task: sleep interrupted (likely cancellation), terminating. Error: \(error)")
                        break
                    }
                }
                DebugLogger.log("Progress update task loop finished.")
            } // Same as before
            
            return recordingUrl
        } catch {
            stopRecording()
            return nil
        }
    }

    func onTimer(_ durationProgressHandler: @escaping ProgressHandler) {
        audioRecorder?.updateMeters()
        currentDuration = audioRecorder!.currentTime
        DebugLogger.log("onTimer: Duration=\(currentDuration), Samples=\(soundSamples.count)")
        if let power = audioRecorder?.averagePower(forChannel: 0) {
            // power from 0 db (max) to -60 db (roughly min)
            let adjustedPower = 1 - (max(power, -60) / 60 * -1)
            soundSamples.append(CGFloat(adjustedPower))
        }
        if let time = audioRecorder?.currentTime {
            durationProgressHandler(time, soundSamples)
        }
    }

    func stopRecording() -> (duration: Double, samples: [CGFloat], url: URL?) {
        DebugLogger.log("stopRecording called. Current recorder state: \(audioRecorder != nil), isRecording: \(self.isRecording)")
        var finalDuration = self.currentDuration
        var finalSamples = self.soundSamples
        let urlForThisRecording = self.currentRecordingURL
        
        audioRecorder?.stop()
        audioRecorder = nil
        audioTimer?.cancel()
        audioTimer = nil
        
        let result = (duration: finalDuration, samples: finalSamples, url: urlForThisRecording)
                
        self.currentDuration = 0
        self.soundSamples = []
        // self.currentRecordingURL = nil; // URL is part of result
        
        DebugLogger.log("stopRecording returning: Duration=\(result.duration), Samples=\(result.samples.count), URL=\(result.url?.lastPathComponent ?? "nil")")
        return result
    }

    private func fileExtension(for formatID: AudioFormatID) -> String? {
        switch formatID {
        case kAudioFormatMPEG4AAC:
            return ".aac"
        case kAudioFormatLinearPCM:
            return ".wav"
        case kAudioFormatMPEGLayer3:
            return ".mp3"
        case kAudioFormatAppleLossless:
            return ".m4a"
        case kAudioFormatOpus:
            return ".opus"
        case kAudioFormatAC3:
            return ".ac3"
        case kAudioFormatFLAC:
            return ".flac"
        case kAudioFormatAMR:
            return ".amr"
        case kAudioFormatMIDIStream:
            return ".midi"
        case kAudioFormatULaw:
            return ".ulaw"
        case kAudioFormatALaw:
            return ".alaw"
        case kAudioFormatAMR_WB:
            return ".awb"
        case kAudioFormatEnhancedAC3:
            return ".eac3"
        case kAudioFormatiLBC:
            return ".ilbc"
        default:
            return nil
        }
    }
}

public struct RecorderSettings : Codable,Hashable {
    var audioFormatID: AudioFormatID
    var sampleRate: CGFloat
    var numberOfChannels: Int
    var encoderBitRateKey: Int
    // pcm
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

extension AVAudioSession {
    func requestRecordPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
