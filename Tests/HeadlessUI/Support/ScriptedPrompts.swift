import Foundation

@testable import LiveSplitOne

/// The editor's questions answered from arrays, recording what was asked (spec §9).
@MainActor
final class ScriptedPrompts: SplitsEditorPrompts {
    /// The names to answer with, in order; `nil` cancels. An `askName` call pops one and offers
    /// it to `accept`; if that refuses, it pops the next. Running out cancels.
    var names: [String?]
    var confirmations: [Bool]
    var images: [URL?]

    private(set) var titlesAsked: [String] = []
    private(set) var prefillsAsked: [String] = []
    private(set) var confirmationsAsked: [Confirmation] = []
    private(set) var imagesAsked = 0
    private(set) var iconFailures: [(error: FileLoadError, file: String)] = []

    init(names: [String?] = [], confirmations: [Bool] = [], images: [URL?] = []) {
        self.names = names
        self.confirmations = confirmations
        self.images = images
    }

    func askName(title: String, prefill: String, accept: (String) -> Bool) -> Bool {
        titlesAsked.append(title)
        prefillsAsked.append(prefill)
        while !names.isEmpty {
            guard let name = names.removeFirst() else { return false }
            if accept(name) { return true }
        }
        return false
    }

    func confirm(_ question: Confirmation) -> Bool {
        confirmationsAsked.append(question)
        return confirmations.isEmpty ? false : confirmations.removeFirst()
    }

    func chooseImage() -> URL? {
        imagesAsked += 1
        return images.isEmpty ? nil : images.removeFirst()
    }

    func showIconFailed(_ error: FileLoadError, file: String) {
        iconFailures.append((error, file))
    }
}
