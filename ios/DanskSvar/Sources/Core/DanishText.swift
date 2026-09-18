import Foundation
import NaturalLanguage

/// Dansksproglig tekstbehandling: opdeling i ord, frasortering af fyldord og en
/// let stammeafkortning, så "aftalerne", "aftalen" og "aftale" tæller som ét ord.
enum DanishText {

    /// Hyppige danske funktionsord. De bærer ingen emneinformation og ville
    /// ellers dominere enhver lighedsberegning.
    static let stopwords: Set<String> = [
        "og", "i", "jeg", "det", "at", "en", "den", "til", "er", "som", "på", "de", "med", "han",
        "af", "for", "ikke", "der", "var", "mig", "sig", "men", "et", "har", "om", "vi", "min",
        "havde", "ham", "hun", "nu", "over", "da", "fra", "du", "ud", "sin", "dem", "os", "op",
        "man", "hans", "hvor", "eller", "hvad", "skal", "selv", "her", "alle", "vil", "blev",
        "kunne", "ind", "når", "være", "dog", "noget", "ville", "jo", "deres", "efter", "ned",
        "skulle", "denne", "end", "dette", "mit", "også", "under", "have", "dig", "anden", "hende",
        "mine", "alt", "meget", "sit", "sine", "vor", "mod", "disse", "hvis", "din", "nogle",
        "hos", "blive", "mange", "ad", "bliver", "hendes", "været", "thi", "jer", "sådan", "lige",
        "kan", "må", "så", "får", "gør", "går", "kom", "kommer", "sagde", "siger", "synes", "tror",
        "ved", "vist", "altså", "bare", "egentlig", "faktisk", "netop", "vel", "nok", "jamen",
        "øh", "øhm", "hmm", "ja", "nej", "okay", "hej", "tja", "næh", "jaja", "hvordan", "hvorfor",
        "hvornår", "hvem", "hvilken", "hvilket", "hvilke", "både", "samt", "fordi", "derfor",
        "altid", "aldrig", "igen", "stadig", "måske", "gerne", "godt", "rigtig", "helt", "meget",
        "lidt", "mere", "mest", "mindre", "andre", "sammen", "hele", "første", "sidste", "næste",
        "tit", "ofte", "vores", "jeres", "dette", "sånoget", "sån", "altsådan"
    ]

    /// Endelser der afkortes for at samle bøjningsformer af samme ord.
    /// Rækkefølgen er vigtig — længste endelse først.
    private static let suffixes = [
        "ernes", "erne", "ende", "ede", "ens", "ers", "ene", "et", "en", "er", "e", "s"
    ]

    /// Splitter en sætning op i normaliserede indholdsord.
    static func contentTokens(in text: String) -> [String] {
        rawTokens(in: text)
            .filter { $0.count >= 3 && !stopwords.contains($0) && Int($0) == nil }
            .map(stem)
            .filter { $0.count >= 3 }
    }

    /// Alle ord i teksten, små bogstaver, uden tegnsætning. Æ, ø og å bevares.
    static func rawTokens(in text: String) -> [String] {
        let lowered = text.lowercased()
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.setLanguage(.danish)
        tokenizer.string = lowered

        var tokens: [String] = []
        tokenizer.enumerateTokens(in: lowered.startIndex ..< lowered.endIndex) { range, _ in
            let token = lowered[range].trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            if !token.isEmpty { tokens.append(token) }
            return true
        }
        return tokens
    }

    /// Meget forsigtig dansk stammeafkortning. Den skærer kun af ord, der er lange
    /// nok til at overleve det, så "hus" ikke bliver til "hu".
    static func stem(_ word: String) -> String {
        var stem = word
        for suffix in suffixes where stem.hasSuffix(suffix) {
            let remaining = stem.count - suffix.count
            if remaining >= 4 {
                stem = String(stem.dropLast(suffix.count))
                break
            }
        }
        // Dobbeltkonsonant til sidst ("hatt" -> "hat") er næsten altid bøjningsstøj.
        if stem.count >= 5, let last = stem.last, let secondLast = stem.dropLast().last,
           last == secondLast, !"aeiouyæøå".contains(last) {
            stem = String(stem.dropLast())
        }
        return stem
    }

    /// Cosinus-lighed mellem to ordvægtninger. 1 = samme emne, 0 = intet fælles.
    static func cosineSimilarity(_ a: [String: Double], _ b: [String: Double]) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        let smaller = a.count <= b.count ? a : b
        let larger = a.count <= b.count ? b : a

        var dot = 0.0
        for (term, weight) in smaller {
            if let other = larger[term] { dot += weight * other }
        }
        guard dot > 0 else { return 0 }

        let normA = sqrt(a.values.reduce(0) { $0 + $1 * $1 })
        let normB = sqrt(b.values.reduce(0) { $0 + $1 * $1 })
        guard normA > 0, normB > 0 else { return 0 }
        return dot / (normA * normB)
    }
}

/// Afgør om en transskription faktisk er dansk. Talegenkenderen kører på da-DK og
/// presser derfor gerne fremmedsproget tale ned i danske ord — porten fanger det.
struct DanishLanguageGate {

    /// Mindste sandsynlighed for dansk, før teksten lukkes igennem.
    var minimumProbability: Double = 0.45
    /// Tekster kortere end dette er for korte til at bedømme sprogligt.
    var minimumWordsToJudge: Int = 4

    func isDanish(_ text: String) -> Bool {
        let words = DanishText.rawTokens(in: text)
        guard words.count >= minimumWordsToJudge else {
            // For kort til en troværdig bedømmelse. Vi lader den passere og lader
            // emnesporingen afgøre, om den overhovedet bidrager med noget.
            return !words.isEmpty
        }

        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.danish, .english, .german, .swedish, .norwegian, .dutch]
        recognizer.processString(text)

        let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
        let danish = hypotheses[.danish] ?? 0
        return danish >= minimumProbability
    }
}
