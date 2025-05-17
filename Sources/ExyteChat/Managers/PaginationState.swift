import Foundation

public typealias ChatPaginationClosure = @Sendable (Message) async -> Void

final actor PaginationHandler: ObservableObject {
    let handleClosure: ChatPaginationClosure
    let pageSize: Int

    init(handleClosure: @escaping ChatPaginationClosure, pageSize: Int) {
        self.handleClosure = handleClosure
        self.pageSize = pageSize
    }
}
