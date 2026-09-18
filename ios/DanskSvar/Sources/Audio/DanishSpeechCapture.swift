import AVFoundation
import Foundation
import Speech

/// Løbende genkendelse af dansk tale. Mikrofonen kører uafbrudt, mens selve
/// genkendelsesopgaven fornys med jævne mellemrum — iOS afbryder en enkelt
/// opgave efter cirka et minut, så den skal skiftes ud undervejs.
@MainActor
final class DanishSpeechCapture {

    enum CaptureError: LocalizedError {
        case microphoneDenied
        case speechDenied
        case recognizerUnavailable
        case onDeviceUnavailable

        var errorDescription: String? {
            switch self {
            case .microphoneDenied:
                return "Mikrofonadgang er ikke givet. Slå den til under Indstillinger > DanskSvar."
            case .speechDenied:
                return "Adgang til talegenkendelse er ikke givet. Slå den til under Indstillinger > DanskSvar."
            case .recognizerUnavailable:
                return "Dansk talegenkendelse er ikke tilgængelig på denne iPhone lige nu."
            case .onDeviceUnavailable:
                return "Dansk kan ikke genkendes lokalt på denne iPhone. Slå »Kun lokal genkendelse« fra, eller hent dansk under Indstillinger > Generelt > Tastatur > Diktering."
            }
        }
    }

    /// Kaldes hver gang en ytring er færdig og klar til emnesporingen.
    var onUtterance: ((Utterance) -> Void)?
    /// Løbende, ufærdig tekst — vises kun i appen, aldrig i en notifikation.
    var onPartialTranscript: ((String) -> Void)?
    var onError: ((Error) -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "da-DK"))
    private let audioEngine = AVAudioEngine()
    private let sessionController = AudioSessionController()

    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var rotationTimer: Timer?
    private var isRunning = false
    private var preferOnDevice = false
    /// Tælleren stiger hver gang en ny genkendelsesopgave startes. Når en gammel
    /// opgave melder tilbage efter at være annulleret, kan svaret kendes som
    /// forældet og ignoreres — ellers ville hver annullering starte en ny
    /// opgave, som straks blev annulleret af den næste.
    private var generation = 0

    /// Den tekst den aktuelle genkendelsesopgave har produceret indtil videre.
    private var pendingText = ""

    // MARK: - Tilladelser

    static func requestAuthorisations() async -> Result<Void, CaptureError> {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechStatus == .authorized else { return .failure(.speechDenied) }

        let micGranted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard micGranted else { return .failure(.microphoneDenied) }

        return .success(())
    }

    var supportsOnDeviceDanish: Bool {
        recognizer?.supportsOnDeviceRecognition ?? false
    }

    // MARK: - Start og stop

    func start(onDeviceOnly: Bool) throws {
        guard !isRunning else { return }
        guard let recognizer, recognizer.isAvailable else { throw CaptureError.recognizerUnavailable }
        if onDeviceOnly && !recognizer.supportsOnDeviceRecognition { throw CaptureError.onDeviceUnavailable }

        preferOnDevice = onDeviceOnly
        try sessionController.activate()
        sessionController.onEvent = { [weak self] event in
            Task { @MainActor in
                guard let self else { return }
                switch event {
                case .interrupted:
                    self.teardownAudio()
                case .resumed, .routeChanged:
                    self.restartAudioIfNeeded()
                }
            }
        }

        try startAudioEngine()
        startRecognitionTask()
        scheduleRotation()
        isRunning = true
    }

    func stop() {
        isRunning = false
        rotationTimer?.invalidate()
        rotationTimer = nil
        finishCurrentTask(emitPending: true)
        teardownAudio()
        sessionController.onEvent = nil
        sessionController.deactivate()
        pendingText = ""
    }

    // MARK: - Lydmotoren

    private func startAudioEngine() throws {
        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()
    }

    private func teardownAudio() {
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
    }

    private func restartAudioIfNeeded() {
        guard isRunning else { return }
        guard !audioEngine.isRunning else { return }
        do {
            try sessionController.activate()
            try startAudioEngine()
            finishCurrentTask(emitPending: true)
            startRecognitionTask()
        } catch {
            onError?(error)
        }
    }

    // MARK: - Genkendelsesopgaven

    private func startRecognitionTask() {
        guard let recognizer else { return }

        generation += 1
        let taskGeneration = generation

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.requiresOnDeviceRecognition = preferOnDevice
        if #available(iOS 16.0, *) { request.addsPunctuation = true }
        self.request = request
        pendingText = ""

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                // Svar fra en opgave, der allerede er skiftet ud, skal falde på gulvet.
                guard taskGeneration == self.generation else { return }

                if let result {
                    let text = result.bestTranscription.formattedString
                    self.pendingText = text
                    self.onPartialTranscript?(text)

                    if result.isFinal {
                        self.emit(text: text, transcription: result.bestTranscription)
                        self.pendingText = ""
                        if self.isRunning { self.rotateTask() }
                    }
                }

                if let error {
                    // Tidsudløb og normale afslutninger er ikke fejl, der skal vises —
                    // opgaven fornys bare. Alt andet meldes videre.
                    let nsError = error as NSError
                    let benign = nsError.domain == "kAFAssistantErrorDomain"
                    if !benign { self.onError?(error) }
                    // Kom der både et endeligt resultat og en fejl, er opgaven allerede
                    // fornyet ovenfor — så må den ikke fornys igen her.
                    if self.isRunning, result?.isFinal != true { self.rotateTask() }
                }
            }
        }
    }

    /// Fornyr genkendelsesopgaven uden at slippe mikrofonen.
    private func rotateTask() {
        finishCurrentTask(emitPending: true)
        guard isRunning else { return }
        startRecognitionTask()
    }

    private func finishCurrentTask(emitPending: Bool) {
        // Gør enhver udestående tilbagemelding fra den nuværende opgave forældet,
        // inden den annulleres.
        generation += 1
        if emitPending, !pendingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            emit(text: pendingText, transcription: nil)
        }
        pendingText = ""
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }

    private func scheduleRotation() {
        rotationTimer?.invalidate()
        // Godt under iOS' egen grænse på cirka et minut per opgave.
        rotationTimer = Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRunning else { return }
                self.rotateTask()
            }
        }
    }

    private func emit(text: String, transcription: SFTranscription?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return }

        var confidence: Float = 0
        if let segments = transcription?.segments, !segments.isEmpty {
            confidence = segments.reduce(0) { $0 + $1.confidence } / Float(segments.count)
        }

        onUtterance?(Utterance(text: trimmed, confidence: confidence))
    }
}
