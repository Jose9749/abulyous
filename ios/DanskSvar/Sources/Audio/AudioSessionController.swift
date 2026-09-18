import AVFoundation
import Foundation

/// Holder lydsessionen i live, også når skærmen er slukket, og melder tilbage når
/// den bliver afbrudt af et opkald, et andet program eller et skift af lydvej.
final class AudioSessionController {

    enum Event {
        case interrupted
        case resumed
        case routeChanged
    }

    var onEvent: ((Event) -> Void)?

    private let session = AVAudioSession.sharedInstance()
    private var observers: [NSObjectProtocol] = []

    func activate() throws {
        // .record + .mixWithOthers lader musik og opkaldslyd fortsætte ved siden af,
        // og .measurement slår automatisk forstærkning fra, så transskriptionen
        // bliver mere stabil i et rum med flere talende.
        try session.setCategory(
            .record,
            mode: .measurement,
            options: [.mixWithOthers, .allowBluetooth]
        )
        try session.setActive(true, options: [])
        installObservers()
    }

    func deactivate() {
        removeObservers()
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func installObservers() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default

        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] note in
            guard
                let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                let type = AVAudioSession.InterruptionType(rawValue: raw)
            else { return }

            switch type {
            case .began:
                self?.onEvent?(.interrupted)
            case .ended:
                self?.onEvent?(.resumed)
            @unknown default:
                break
            }
        })

        observers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            self?.onEvent?(.routeChanged)
        })

        observers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            self?.onEvent?(.interrupted)
        })
    }

    private func removeObservers() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }

    deinit {
        removeObservers()
    }
}
