//
//  Created by Alex.M on 27.06.2022.
//

import Foundation
import ExyteChat

struct MockMessage: Sendable {
    let uid: String
    let sender: MockUser
    let createdAt: Date
    var status: Message.Status?

    let text: String
    let images: [MockImage]
    let videos: [MockVideo]
    let reactions: [Reaction]
    let recording: Recording?
    let replyMessage: ReplyMessage?
}

extension MockMessage {
    func toChatMessage() -> ExyteChat.Message {
        let newMessage = ExyteChat.Message(
            id: uid,
            user: sender.toChatUser(),
            status: status,
            createdAt: createdAt,
            text: text,
            attachments: images.map { $0.toChatAttachment() } + videos.map { $0.toChatAttachment() },
            reactions: reactions,
            recording: recording,
            replyMessage: replyMessage
        )
        
//        print("[ChatExampleViewModel.send] Constructed ExyteChat.Message. ID: \(newMessage.id), Recording present: \(newMessage.recording != nil)")
//        if let rec = newMessage.recording {
//             print("[ChatExampleViewModel.send] ExyteChat.Message recording details - Duration: \(rec.duration), Samples: \(rec.waveformSamples.count), URL: \(String(describing: rec.url))")
//        }
        return newMessage
    }
}
