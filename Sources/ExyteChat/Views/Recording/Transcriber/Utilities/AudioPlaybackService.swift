//
//  AudioPlaybackService.swift
//  Transcriber
//
//  Created by Yangming Zhang on 5/15/25.
//


import AVFoundation
import OSLog // For logging if needed

class AudioPlaybackService: NSObject, AVAudioPlayerDelegate {
    private var audioPlayer: AVAudioPlayer?
    private let logger = Logger(subsystem: "com.example.transcriber", category: "AudioPlaybackService") // Adjust subsystem

    func playAudio(url: URL) {
        // It's good practice to manage audio session for playback
        // The DefaultTranscriberPresenter already sets up an audio session for playAndRecord.
        // We might need to ensure it's correctly configured or re-activated if needed.
        // For this demo, we assume the session is suitably active.

        // Stop any existing playback
        if audioPlayer?.isPlaying == true {
            audioPlayer?.stop()
        }

        logger.log("Attempting to play audio from: \(url.path)")

        do {
            // Check if file exists
            guard FileManager.default.fileExists(atPath: url.path) else {
                logger.error("Audio file does not exist at path: \(url.path)")
                return
            }

            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay() // Prepares the audio player for playback by preloading its buffers.

            if audioPlayer?.play() == true {
                logger.log("Audio playback started successfully.")
            } else {
                logger.error("Audio playback failed to start.")
            }
        } catch {
            logger.error("Failed to initialize or play audio: \(error.localizedDescription)")
        }
    }

    func stopPlayback() {
        if audioPlayer?.isPlaying == true {
            audioPlayer?.stop()
            logger.log("Audio playback stopped.")
        }
    }

    // MARK: - AVAudioPlayerDelegate
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if flag {
            logger.log("Audio playback finished successfully.")
        } else {
            logger.warning("Audio playback finished unsuccessfully.")
        }
        // Clean up or notify UI if needed
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        if let error = error {
            logger.error("Audio player decode error: \(error.localizedDescription)")
        }
    }
}