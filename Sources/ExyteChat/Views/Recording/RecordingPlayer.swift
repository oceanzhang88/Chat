// Chat/Sources/ExyteChat/Views/Recording/RecordingPlayer.swift
@preconcurrency import Combine
@preconcurrency import AVFoundation

final actor RecordingPlayer: ObservableObject {

    @MainActor @Published var playing = false
    @MainActor @Published var duration: Double = 0.0
    @MainActor @Published var secondsLeft: Double = 0.0
    @MainActor @Published var progress: Double = 0.0
    @MainActor let didPlayTillEnd = PassthroughSubject<Void, Never>()

    private var recording: Recording? {
        didSet {
            if oldValue?.url != recording?.url {
                Task { await self.updatePlayerStateForNewRecording() }
            }
        }
    }

    private func updatePlayerStateForNewRecording() {
        internalPlaying = false
        Task { @MainActor in
            self.progress = 0
            if let r = await self.recording {
                self.duration = r.duration
                self.secondsLeft = r.duration
            } else {
                self.duration = 0
                self.secondsLeft = 0
            }
        }
    }

    private var internalPlaying = false {
       didSet {
           // Capture the new value of the actor-isolated 'internalPlaying'
           let newValue = self.internalPlaying
           // Dispatch the update to the @MainActor property 'playing'
           Task {
               await MainActor.run { // Explicitly run on the main actor
                   self.playing = newValue
               }
           }
       }
   }

    private let audioSession = AVAudioSession.sharedInstance()
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var itemStatusObserver: NSKeyValueObservation?
    private var playWhenReady = false

    init() {
        DebugLogger.log("RecordingPlayer init")
        // Defer session category setup until actual play attempt
    }

    func togglePlay(_ recording: Recording) async {
        DebugLogger.log("togglePlay called for URL: \(recording.url?.lastPathComponent ?? "nil"). Current player recording URL: \(self.recording?.url?.lastPathComponent ?? "nil")")
        if self.recording?.url != recording.url || self.player == nil || self.player?.currentItem == nil { // Added check for currentItem
            DebugLogger.log("togglePlay: New recording, player nil, or no current item. Setting up.")
            await self.setupPlayer(for: recording)
            self.playWhenReady = true
        } else {
            if self.internalPlaying {
                DebugLogger.log("togglePlay: Pausing existing.")
                await self.pause() // pause is now async due to potential session deactivation
            } else {
                DebugLogger.log("togglePlay: Playing existing.")
                self.playWhenReady = true
                await self.play()
            }
        }
    }
    
    func play(_ recording: Recording) async {
        DebugLogger.log("Explicit play called for URL: \(recording.url?.lastPathComponent ?? "nil")")
        if self.recording?.url != recording.url || self.player == nil || self.player?.currentItem == nil {
            await self.setupPlayer(for: recording)
        }
        self.playWhenReady = true
        await self.play()
    }

    func pause() async { // Make async to match potential session changes
        DebugLogger.log("Pause called.")
        player?.pause()
        internalPlaying = false
        playWhenReady = false
        // Strategy: Leave session active after pausing.
        // If deactivation is desired:
        // Task {
        //     do {
        //         try self.audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        //         DebugLogger.log("Audio session deactivated on pause.")
        //     } catch { DebugLogger.log("Error deactivating session on pause: \(error)") }
        // }
        DebugLogger.log("Audio session intentionally NOT deactivated on RecordingPlayer.pause.")
    }

    private func play() async {
        guard let currentItem = player?.currentItem else {
            DebugLogger.log("play() called but no current item or player.")
            playWhenReady = false
            return
        }
        DebugLogger.log("play() called. Item status: \(currentItem.status.rawValue). playWhenReady: \(playWhenReady)")

        if currentItem.status == .readyToPlay {
            DebugLogger.log("play(): Item is ready. Attempting to configure/activate session and play.")
            do {
                // Explicitly set category to .playback and activate
                if audioSession.category != .playback {
                    DebugLogger.log("play(): Current session category is \(audioSession.category.rawValue), attempting to set to .playback.")
                    // Deactivate if active in a different category before changing.
                    // This is crucial for clean transitions.
                    if audioSession.isInputAvailable { // Or another check if it might be active
                        do {
                            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
                            DebugLogger.log("Audio session deactivated to change category for playback.")
                        } catch {
                             DebugLogger.log("Failed to deactivate session before category change for playback: \(error). Proceeding.")
                        }
                    }
                    try audioSession.setCategory(.playback, mode: .default, options: [.defaultToSpeaker]) // Add relevant options
                    DebugLogger.log("Audio session category set to .playback.")
                }
                
                let activationStartTime = Date()
                try audioSession.setActive(true)
                DebugLogger.log("play(): Audio session setActive(true) for playback. Time taken: \(Date().timeIntervalSince(activationStartTime) * 1000) ms.")
                
                player?.play()
                internalPlaying = true
                playWhenReady = false
                
                NotificationCenter.default.post(name: .chatAudioIsPlaying, object: self)
            } catch {
                DebugLogger.log("play(): Failed to set category or activate audio session for playback: \(error)")
                internalPlaying = false
                playWhenReady = false
            }
        } else if currentItem.status == .failed {
            // ... (same as before) ...
        } else { // .unknown
            // ... (same as before) ...
        }
    }
    
    private func setupPlayer(for recording: Recording) async {
        guard let url = recording.url else {
            DebugLogger.log("setupPlayer: Recording URL is nil.")
            return
        }
        DebugLogger.log("setupPlayer: Setting up for URL: \(url.lastPathComponent)")

        // If it's the same recording, don't reset everything, just ensure player is ready
        if self.recording?.url == url && player != nil && player?.currentItem?.asset is AVURLAsset && (player?.currentItem?.asset as! AVURLAsset).url == url {
            DebugLogger.log("setupPlayer: Same recording URL and player exists. Ensuring it's ready if playWhenReady is set.")
            if playWhenReady { // If an explicit play was intended for this already setup item
                await self.play() // play() will check .readyToPlay status
            }
            return // Avoid full re-setup
        }
        
        self.recording = recording

        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: player?.currentItem)
        NotificationCenter.default.removeObserver(self, name: .chatAudioIsPlaying, object: nil)
        
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        itemStatusObserver?.invalidate()
        itemStatusObserver = nil

        let playerItem = AVPlayerItem(url: url)
        DebugLogger.log("setupPlayer: New AVPlayerItem created for \(url.lastPathComponent)")

        itemStatusObserver = playerItem.observe(\.status, options: [.new, .initial]) { [weak self] item, change in
            Task {
                guard let strongSelf = await self else { return }
                DebugLogger.log("KVO: PlayerItem status changed to \(item.status.rawValue) for \(item.asset is AVURLAsset ? (item.asset as! AVURLAsset).url.lastPathComponent : "unknown asset"). playWhenReady: \(await await strongSelf.playWhenReady)")
                
                switch item.status {
                case .readyToPlay:
                    DebugLogger.log("KVO: Item is readyToPlay.")
                    let itemDurationSeconds = item.duration.seconds
                    await MainActor.run {
                        strongSelf.duration = itemDurationSeconds
                        if !strongSelf.playing {
                           strongSelf.secondsLeft = itemDurationSeconds
                        }
                    }
                    if await strongSelf.playWhenReady {
                        DebugLogger.log("KVO: playWhenReady is true, calling play().")
                        await strongSelf.play()
                    }
                case .failed:
                    let errorDescription = item.error?.localizedDescription ?? "Unknown error"
                    DebugLogger.log("KVO: PlayerItem status changed to .failed. Error: \(errorDescription)")
                    strongSelf.internalPlaying = false
                    strongSelf.playWhenReady = false
                default: // .unknown
                    DebugLogger.log("KVO: PlayerItem status is .unknown.")
                    break
                }
            }
        }

        if player == nil {
            player = AVPlayer() // Create player only if it doesn't exist
            DebugLogger.log("New AVPlayer instance created globally.")
        }
        player?.replaceCurrentItem(with: playerItem)
        DebugLogger.log("Player item replaced with new URL: \(url.lastPathComponent)")

        // Add other observers
        let actorInstance = self
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main) { [weak actorInstance] notification in
            Task { await actorInstance?.handlePlayerDidFinishPlaying(note: notification as NSNotification) }
        }
        NotificationCenter.default.addObserver(forName: .chatAudioIsPlaying, object: nil, queue: .main) { [weak actorInstance] notification in
            Task { await actorInstance?.handleOtherAudioPlaying(notification: notification as NSNotification) }
        }

        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: nil
        ) { [weak self] time in
            Task {
                guard let strongSelf = await self, let currentItem = await strongSelf.player?.currentItem else { return }
                let itemDuration = currentItem.duration
                if !itemDuration.seconds.isNaN && itemDuration.seconds > 0 {
                    await strongSelf.updateProgressProperties(itemDuration: itemDuration, currentTime: time)
                }
            }
        }
    }
    
    private func updateProgressProperties(itemDuration: CMTime, currentTime: CMTime) async {
        let itemDurationSeconds = itemDuration.seconds
        let currentTimeSeconds = currentTime.seconds
        
        await MainActor.run {
            if self.duration <= 0 || abs(self.duration - itemDurationSeconds) > 0.01 {
                self.duration = itemDurationSeconds
            }
            if itemDurationSeconds > 0 {
                self.progress = currentTimeSeconds / itemDurationSeconds
            } else {
                self.progress = 0
            }
            self.secondsLeft = max(0, itemDurationSeconds - currentTimeSeconds)
        }
    }

    private func handlePlayerDidFinishPlaying(note: NSNotification) {
        DebugLogger.log("playerDidFinishPlaying.")
        self.internalPlaying = false
        self.player?.seek(to: .zero)
        Task { @MainActor in self.didPlayTillEnd.send() }
        DebugLogger.log("Audio session intentionally NOT deactivated after playback finished.")
    }

    private func handleOtherAudioPlaying(notification: NSNotification) {
        if let sender = notification.object as? RecordingPlayer, sender !== self {
             DebugLogger.log("Another player started. Pausing self.")
             Task { await self.pause() } // Call async version
        }
    }

    func seek(with recording: Recording, to progress: Double) async {
        guard let player = self.player else {
            DebugLogger.log("Seek attempted but player is nil.")
            return
        }
        let goalTimeSeconds = recording.duration * progress
        let goalTime = CMTime(seconds: goalTimeSeconds, preferredTimescale: 600)
        DebugLogger.log("seek(with:to: \(progress)), goalTime: \(goalTimeSeconds)")

        if self.recording?.url != recording.url || player.currentItem?.asset !== (player.currentItem?.asset as? AVURLAsset) {
            DebugLogger.log("Seek: Recording item changed or player item mismatch. Setting up player.")
            await self.setupPlayer(for: recording)
        }
        
        if player.currentItem?.status == .readyToPlay {
            await player.seek(to: goalTime, toleranceBefore: .zero, toleranceAfter: .zero)
            DebugLogger.log("Seek completed.")
            if internalPlaying {
                player.play() // AVPlayer's play is synchronous
                DebugLogger.log("Resumed playback after seek.")
            }
            await self.updateProgressProperties(itemDuration: player.currentItem!.duration, currentTime: goalTime)
        } else {
            DebugLogger.log("Seek: Player item not ready. playWhenReady: \(playWhenReady). Current status: \(player.currentItem?.status.rawValue ?? -99)")
            // If we want to play after seek, set the flag. KVO will pick it up.
            // If it was already playing, we intend to keep it playing.
            if internalPlaying { self.playWhenReady = true }
        }
    }

    func seek(to progress: Double) async {
        if let currentRec = self.recording {
            await seek(with: currentRec, to: progress)
        }
    }
    
    func reset() async { // Make async due to pause
        DebugLogger.log("Resetting player.")
        await pause() // pause is now async

        player?.replaceCurrentItem(with: nil)
        
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        itemStatusObserver?.invalidate()
        itemStatusObserver = nil
        NotificationCenter.default.removeObserver(self)

        self.recording = nil
        DebugLogger.log("Audio session intentionally NOT deactivated on player reset.")
    }
}
