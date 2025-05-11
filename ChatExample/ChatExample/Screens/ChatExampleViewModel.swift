//
//  Created by Alex.M on 23.06.2022.
//

import Foundation
import ExyteChat

@MainActor
final class ChatExampleViewModel: ObservableObject, ReactionDelegate {

    @Published var messages: [Message] = []

    @Published var chatTitle: String = ""
    @Published var chatStatus: String = ""
    @Published var chatCover: URL?

    private let interactor: MockChatInteractor
    private var timer: Timer?

    init(interactor: MockChatInteractor = MockChatInteractor()) {
        self.interactor = interactor

        Task {
            let senders = await interactor.otherSenders
            self.chatTitle = senders.count == 1 ? senders.first!.name : "Group chat"
            self.chatStatus = senders.count == 1 ? "online" : "\(senders.count + 1) members"
            self.chatCover = senders.count == 1 ? senders.first!.avatar : nil
        }
    }

    func send(draft: DraftMessage) {
        Task {
            // This now waits until the interactor has finished appending the message
            await interactor.send(draftMessage: draft)
            
            // Fetch the updated messages list from the interactor
            let updatedMessagesFromInteractor = await interactor.messages
            // Update the local @Published messages array
            self.messages = updatedMessagesFromInteractor.compactMap { $0.toChatMessage() }
            
            // Now, log the state of the just-updated self.messages
            print("[ChatExampleViewModel] Messages count after send: \(self.messages.count)")
            if let lastMessage = self.messages.last {
                print("[ChatExampleViewModel] Last message recording: \(String(describing: lastMessage.recording))")
                if let rec = lastMessage.recording {
                    print("[ChatExampleViewModel] Last message recording details - Duration: \(rec.duration), Samples: \(rec.waveformSamples.count), URL: \(String(describing: rec.url))")
                }
            }
        }
    }
    
    func remove(messageID: String) {
        Task {
            await interactor.remove(messageID: messageID)
            self.updateMessages()
        }
    }

    nonisolated func didReact(to message: Message, reaction draftReaction: DraftReaction) {
        Task {
            await interactor.add(draftReaction: draftReaction, to: draftReaction.messageID)
        }
    }

    func onStart() {
        Task {
            self.updateMessages()
            connect()
        }
    }

    func connect() {
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { timer in
            Task {
                await self.interactor.timerTick()
                await self.updateMessages()
            }
        }
    }

    func onStop() {
        timer?.invalidate()
    }

    func loadMoreMessage(before message: Message) {
        Task {
            await interactor.loadNextPage()
            updateMessages()
        }
    }

    func updateMessages() {
        Task {
            self.messages = await interactor.messages.compactMap { $0.toChatMessage() }
        }
    }
}
