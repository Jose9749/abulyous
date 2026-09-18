import Foundation
import SwiftUI

/// Alle indstillinger ét sted. Tallene er valgt, så appen hverken snakker i
/// munden på folk eller bliver tavs i en halv time.
@MainActor
final class AppSettings: ObservableObject {

    private enum Key {
        static let minimumInterval = "minimumReplyInterval"
        static let settleDelay = "settleDelay"
        static let topicSwitchGrace = "topicSwitchGrace"
        static let minimumUtterances = "minimumUtterances"
        static let minimumWords = "minimumWords"
        static let minimumCoherence = "minimumCoherence"
        static let newWordsBeforeFollowUp = "newWordsBeforeFollowUp"
        static let replyLength = "replyLength"
        static let persona = "persona"
        static let onDeviceOnly = "onDeviceOnly"
        static let timeSensitive = "timeSensitive"
        static let allowLocalFallback = "allowLocalFallback"
        static let effort = "effort"
        static let model = "model"
        static let keepTranscriptInHistory = "keepTranscriptInHistory"
    }

    private let defaults = UserDefaults.standard

    /// Mindste tid mellem to svar på skærmen.
    @Published var minimumReplyInterval: TimeInterval { didSet { defaults.set(minimumReplyInterval, forKey: Key.minimumInterval) } }
    /// Hvor længe der skal være stille, før appen svarer — så den ikke afbryder.
    @Published var settleDelay: TimeInterval { didSet { defaults.set(settleDelay, forKey: Key.settleDelay) } }
    /// Ekstra pusterum efter et emneskift, så det nye emne når at folde sig ud.
    @Published var topicSwitchGrace: TimeInterval { didSet { defaults.set(topicSwitchGrace, forKey: Key.topicSwitchGrace) } }
    /// Mindste antal ytringer i et emne, før det kan besvares.
    @Published var minimumUtterances: Int { didSet { defaults.set(minimumUtterances, forKey: Key.minimumUtterances) } }
    /// Mindste antal ord i et emne, før det kan besvares.
    @Published var minimumWords: Int { didSet { defaults.set(minimumWords, forKey: Key.minimumWords) } }
    /// Hvor stram den røde tråd skal være (0...1), før appen svarer.
    @Published var minimumCoherence: Double { didSet { defaults.set(minimumCoherence, forKey: Key.minimumCoherence) } }
    /// Hvor meget nyt der skal siges om samme emne, før appen svarer igen.
    @Published var newWordsBeforeFollowUp: Int { didSet { defaults.set(newWordsBeforeFollowUp, forKey: Key.newWordsBeforeFollowUp) } }

    @Published var replyLength: ReplyLength { didSet { defaults.set(replyLength.rawValue, forKey: Key.replyLength) } }
    @Published var persona: String { didSet { defaults.set(persona, forKey: Key.persona) } }
    @Published var onDeviceOnly: Bool { didSet { defaults.set(onDeviceOnly, forKey: Key.onDeviceOnly) } }
    @Published var timeSensitive: Bool { didSet { defaults.set(timeSensitive, forKey: Key.timeSensitive) } }
    @Published var allowLocalFallback: Bool { didSet { defaults.set(allowLocalFallback, forKey: Key.allowLocalFallback) } }
    @Published var effort: String { didSet { defaults.set(effort, forKey: Key.effort) } }
    @Published var model: String { didSet { defaults.set(model, forKey: Key.model) } }
    /// Slået fra som udgangspunkt: kun svarene gemmes, ikke hvad andre har sagt.
    @Published var keepTranscriptInHistory: Bool { didSet { defaults.set(keepTranscriptInHistory, forKey: Key.keepTranscriptInHistory) } }

    @Published var apiKey: String { didSet { Keychain.set(apiKey, for: "anthropic-api-key") } }

    init() {
        defaults.register(defaults: [
            Key.minimumInterval: 90.0,
            Key.settleDelay: 6.0,
            Key.topicSwitchGrace: 20.0,
            Key.minimumUtterances: 3,
            Key.minimumWords: 25,
            Key.minimumCoherence: 0.16,
            Key.newWordsBeforeFollowUp: 45,
            Key.replyLength: ReplyLength.mellem.rawValue,
            Key.persona: "",
            Key.onDeviceOnly: false,
            Key.timeSensitive: true,
            Key.allowLocalFallback: true,
            Key.effort: "low",
            Key.model: ClaudeClient.defaultModel,
            Key.keepTranscriptInHistory: false
        ])

        minimumReplyInterval = defaults.double(forKey: Key.minimumInterval)
        settleDelay = defaults.double(forKey: Key.settleDelay)
        topicSwitchGrace = defaults.double(forKey: Key.topicSwitchGrace)
        minimumUtterances = defaults.integer(forKey: Key.minimumUtterances)
        minimumWords = defaults.integer(forKey: Key.minimumWords)
        minimumCoherence = defaults.double(forKey: Key.minimumCoherence)
        newWordsBeforeFollowUp = defaults.integer(forKey: Key.newWordsBeforeFollowUp)
        replyLength = ReplyLength(rawValue: defaults.string(forKey: Key.replyLength) ?? "") ?? .mellem
        persona = defaults.string(forKey: Key.persona) ?? ""
        onDeviceOnly = defaults.bool(forKey: Key.onDeviceOnly)
        timeSensitive = defaults.bool(forKey: Key.timeSensitive)
        allowLocalFallback = defaults.bool(forKey: Key.allowLocalFallback)
        effort = defaults.string(forKey: Key.effort) ?? "low"
        model = defaults.string(forKey: Key.model) ?? ClaudeClient.defaultModel
        keepTranscriptInHistory = defaults.bool(forKey: Key.keepTranscriptInHistory)
        apiKey = Keychain.get("anthropic-api-key")
    }

    var topicConfiguration: TopicTracker.Configuration {
        var configuration = TopicTracker.Configuration()
        configuration.switchGrace = topicSwitchGrace
        return configuration
    }
}
