import SwiftUI

struct SettingsView: View {

    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var engine: ConversationEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                apiSection
                rhythmSection
                thresholdSection
                languageSection
                notificationSection
                privacySection
            }
            .navigationTitle("Indstillinger")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Færdig") { dismiss() }
                }
            }
        }
    }

    private var apiSection: some View {
        Section {
            SecureField("sk-ant-…", text: $settings.apiKey)
                .textContentType(.password)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            Picker("Model", selection: $settings.model) {
                Text("Claude Opus 5").tag("claude-opus-5")
                Text("Claude Sonnet 5").tag("claude-sonnet-5")
                Text("Claude Haiku 4.5").tag("claude-haiku-4-5")
            }

            Picker("Grundighed", selection: $settings.effort) {
                Text("Lav – hurtigst").tag("low")
                Text("Mellem").tag("medium")
                Text("Høj – bedst formuleret").tag("high")
            }

            Toggle("Skriv lokalt, hvis kaldet fejler", isOn: $settings.allowLocalFallback)
        } header: {
            Text("Anthropic API-nøgle")
        } footer: {
            Text("Nøglen gemmes i din iPhones nøglering. Uddrag af samtalen sendes til Anthropics API for at blive formuleret om til et svar — slå »Skriv lokalt« til, hvis du vil have et svar alligevel, når der ikke er net.")
        }
    }

    private var rhythmSection: some View {
        Section {
            stepper(
                "Mindst mellem svar",
                value: $settings.minimumReplyInterval,
                range: 30 ... 600,
                step: 15,
                unit: "s"
            )
            stepper(
                "Pause før der svares",
                value: $settings.settleDelay,
                range: 2 ... 30,
                step: 1,
                unit: "s"
            )
            stepper(
                "Pusterum efter emneskift",
                value: $settings.topicSwitchGrace,
                range: 0 ... 120,
                step: 5,
                unit: "s"
            )
        } header: {
            Text("Rytme")
        } footer: {
            Text("Skifter samtalen emne, venter appen et pusterum, så det nye emne når at folde sig ud, før svaret kommer. Der går altid mindst »mindst mellem svar« fra ét svar til det næste.")
        }
    }

    private var thresholdSection: some View {
        Section {
            Stepper(
                "Mindst \(settings.minimumUtterances) ytringer",
                value: $settings.minimumUtterances,
                in: 2 ... 15
            )
            Stepper(
                "Mindst \(settings.minimumWords) ord",
                value: $settings.minimumWords,
                in: 10 ... 200,
                step: 5
            )
            Stepper(
                "Nyt siden sidst: \(settings.newWordsBeforeFollowUp) ord",
                value: $settings.newWordsBeforeFollowUp,
                in: 10 ... 300,
                step: 5
            )
            VStack(alignment: .leading) {
                Text("Krav til rød tråd: \(Int(settings.minimumCoherence * 100)) %")
                Slider(value: $settings.minimumCoherence, in: 0.05 ... 0.45)
            }
        } header: {
            Text("Hvornår er der noget at svare på")
        } footer: {
            Text("Appen svarer først, når nok mennesker har sagt nok om det samme. Hæver du kravet til den røde tråd, svarer appen sjældnere, men kun når emnet er tydeligt.")
        }
    }

    private var languageSection: some View {
        Section {
            Picker("Svarets længde", selection: $settings.replyLength) {
                ForEach(ReplyLength.allCases) { length in
                    Text(length.danishLabel).tag(length)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Om dig")
                TextEditor(text: $settings.persona)
                    .frame(minHeight: 80)
                    .font(.footnote)
            }
        } header: {
            Text("Sprog og stemme")
        } footer: {
            Text("Skriv gerne et par linjer om, hvem du er, og hvordan du plejer at udtrykke dig. Modellen skriver på dansk under alle omstændigheder — det her gør bare svaret til dit.")
        }
    }

    private var notificationSection: some View {
        Section {
            Toggle("Bryd igennem Fokus", isOn: $settings.timeSensitive)
        } header: {
            Text("Notifikationer")
        } footer: {
            Text("Svaret vises altid uden lyd og kun som ét svar ad gangen. Der bliver aldrig sendt en notifikation med, hvad andre har sagt.")
        }
    }

    private var privacySection: some View {
        Section {
            Toggle("Kun lokal talegenkendelse", isOn: $settings.onDeviceOnly)
                .disabled(!engine.supportsOnDeviceDanish)
        } header: {
            Text("Privatliv")
        } footer: {
            if engine.supportsOnDeviceDanish {
                Text("Med lokal genkendelse forlader lyden aldrig din iPhone. Selve svaret formuleres stadig af Anthropics model, medmindre du kun bruger den lokale nødformulering. Husk, at det kun er lovligt at optage samtaler, du selv deltager i.")
            } else {
                Text("Denne iPhone har ikke dansk talegenkendelse liggende lokalt. Hent dansk under Indstillinger > Generelt > Tastatur > Diktering, eller lad genkendelsen køre via Apples servere. Husk, at det kun er lovligt at optage samtaler, du selv deltager i.")
            }
        }
    }

    private func stepper(
        _ title: String,
        value: Binding<TimeInterval>,
        range: ClosedRange<Double>,
        step: Double,
        unit: String
    ) -> some View {
        Stepper(
            "\(title): \(Int(value.wrappedValue)) \(unit)",
            value: value,
            in: range,
            step: step
        )
    }
}
