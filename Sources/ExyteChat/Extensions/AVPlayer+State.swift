import Foundation
import AVKit

extension AVPlayer {
    nonisolated var isPlaying: Bool {
        rate != 0 && error == nil
    }
}
