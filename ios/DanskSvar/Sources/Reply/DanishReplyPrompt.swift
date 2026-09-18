import Foundation

/// Hvor fyldigt svaret skal formuleres.
enum ReplyLength: String, CaseIterable, Codable, Identifiable {
    case kort
    case mellem
    case lang

    var id: String { rawValue }

    var danishLabel: String {
        switch self {
        case .kort: return "Kort"
        case .mellem: return "Mellem"
        case .lang: return "Fyldigt"
        }
    }

    var instruction: String {
        switch self {
        case .kort:
            return "Hold svaret på én til to sætninger, højst 35 ord. Stramt, men stadig fuldt formuleret."
        case .mellem:
            return "Hold svaret på to til fire sætninger, 40-70 ord. Der er plads til et forbehold og en præcisering."
        case .lang:
            return "Skriv tre til fem sætninger, 70-110 ord. Fold tanken ud med sideordning, indskud og et velvalgt forbehold."
        }
    }

    /// Loftet dækker både modellens interne tænkning og selve svarteksten, så det
    /// er sat rundhåndet. Svarets faktiske længde styres af `instruction` ovenfor.
    var maxTokens: Int {
        switch self {
        case .kort: return 2_000
        case .mellem: return 2_500
        case .lang: return 3_000
        }
    }
}

/// Bygger den danske systemprompt og det oplæg, modellen skal svare på.
enum DanishReplyPrompt {

    /// Systemprompten er skrevet på dansk med vilje: den sætter modellen i dansk
    /// sprogtilstand fra første token og holder den væk fra oversættelsesdansk.
    static func system(length: ReplyLength, persona: String) -> String {
        var prompt = """
        Du lytter med på en samtale mellem andre mennesker og skriver ét enkelt, skriftligt \
        svar, som brugeren kan læse på sin låseskærm. Brugeren siger ikke noget selv og \
        trykker ikke på noget — dit svar er hele hans eller hendes replik.

        SPROG
        - Skriv udelukkende på dansk. Moderne, talt rigsdansk, som det faktisk lyder i Danmark.
        - Ram den danske sætningsrytme: inversion efter ledsætning ("Når først regnskabet \
        ligger der, kan vi tage den snak"), sætningsadverbierne på deres rette plads foran \
        hovedverbet i ledsætninger, og de små danske partikler — jo, nu, da, vel, nok, altså, \
        egentlig, netop — dér hvor de gør sætningen dansk frem for korrekt.
        - Ingen oversættelsesdansk. Ingen anglicismer, intet "gøre en forskel"-agtigt \
        importsprog, ingen engelsk ordstilling, ingen kancellisprog eller stive substantiveringer.
        - Brug gerne et fast dansk udtryk, når det falder af sig selv — "der er noget om snakken", \
        "det ligger lige for", "det holder ikke vand", "så er den ged barberet" — men ét ad \
        gangen, og aldrig som pynt.
        - Formuler komplekst, hvor sagen er kompleks: hypotakse, indskud, præcise skel, \
        velplacerede forbehold. Formuler til gengæld enkelt, hvor sagen er enkel. Ordrigdom \
        uden indhold er ikke godt dansk.

        INDHOLD
        - Find den røde tråd i det, der bliver sagt, og svar på den — ikke på den sidste \
        løsrevne sætning.
        - Sig noget, der faktisk bringer samtalen videre: en holdning, en skelnen, et spørgsmål, \
        der rammer det ømme punkt, eller en erfaring, der passer på sagen. Ikke et referat af \
        det, de lige har sagt.
        - Transskriptionen er lavet af en maskine og er stedvis forkert. Læs efter meningen, og \
        gætter du på et ord, så lad være med at bygge hele svaret på det.
        - Er materialet for tyndt eller for rodet til, at der er en tråd at svare på, så svar \
        med ordet INTET og ikke andet.
        - Skriv aldrig om, at du er en model, at du lytter med, eller at teksten kommer fra en \
        transskription.

        \(length.instruction)

        SVARFORMAT
        Svar med præcis to linjer og intet andet:
        EMNE: en overskrift på 2-5 ord, der navngiver emnet
        SVAR: selve svaret i almindelig, ubrudt tekst
        Ingen markdown, ingen anførselstegn om svaret, ingen indledning, ingen forklaring.
        """

        let trimmedPersona = persona.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPersona.isEmpty {
            prompt += "\n\nOM DEN, DU SKRIVER PÅ VEGNE AF\n\(trimmedPersona)"
        }
        return prompt
    }

    /// Selve oplægget: de seneste ytringer med tidsstempler, plus de nøgleord
    /// emnesporingen har fundet.
    static func userMessage(utterances: [Utterance], keywords: [String], isTopicShift: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "da_DK")
        formatter.dateFormat = "HH:mm:ss"

        let lines = utterances
            .map { "[\(formatter.string(from: $0.timestamp))] \($0.text)" }
            .joined(separator: "\n")

        var message = "Uddrag af samtalen, ældste først:\n\n\(lines)"

        if !keywords.isEmpty {
            message += "\n\nOrd der går igen: \(keywords.prefix(8).joined(separator: ", "))."
        }
        if isTopicShift {
            message += "\n\nSamtalen er lige drejet over på noget nyt. Svar på det nye, ikke på det forrige."
        }
        message += "\n\nSkriv nu svaret i det aftalte format."
        return message
    }

    /// Splitter modellens to linjer op. Kommer svaret i et andet format, bruges
    /// hele teksten som svar.
    static func parse(_ raw: String) -> (topic: String?, body: String)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.uppercased() == "INTET" { return nil }

        var topic: String?
        var bodyParts: [String] = []

        for line in trimmed.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = line.trimmingCharacters(in: .whitespaces)
            if let range = text.range(of: "EMNE:", options: [.caseInsensitive, .anchored]) {
                topic = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            } else if let range = text.range(of: "SVAR:", options: [.caseInsensitive, .anchored]) {
                bodyParts.append(String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces))
            } else if !text.isEmpty {
                // Holder modellen sig ikke til formatet, er teksten stadig svaret.
                bodyParts.append(text)
            }
        }

        let body = bodyParts
            .joined(separator: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"«»„“”"))

        guard body.count >= 3, body.uppercased() != "INTET" else { return nil }
        return (topic?.isEmpty == false ? topic : nil, body)
    }
}
