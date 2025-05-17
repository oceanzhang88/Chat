import Foundation

final class GlobalFocusState: ObservableObject {
    @Published var focus: Focusable?
}
