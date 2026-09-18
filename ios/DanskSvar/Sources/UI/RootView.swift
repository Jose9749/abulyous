import SwiftUI

struct RootView: View {

    @EnvironmentObject private var engine: ConversationEngine
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var history: HistoryStore

    @State private var showingSettings = false
    @State private var showingHistory = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    statusCard
                    listenButton
                    if let reply = engine.latestReply { replyCard(reply) }
                    if engine.status.isRunning { threadCard }
                    if let message = engine.lastErrorMessage { errorCard(message) }
                    explanationCard
                }
                .padding()
            }
            .navigationTitle("DanskSvar")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingHistory = true
                    } label: {
                        Label("Historik", systemImage: "clock.arrow.circlepath")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Label("Indstillinger", systemImage: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView().environmentObject(settings).environmentObject(engine)
            }
            .sheet(isPresented: $showingHistory) {
                HistoryView().environmentObject(history)
            }
        }
    }

    // MARK: - Dele

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Circle()
                    .fill(statusColour)
                    .frame(width: 12, height: 12)
                Text(engine.status.danishLabel)
                    .font(.headline)
                Spacer()
                if let seconds = engine.secondsUntilNextReply {
                    Text("næste om \(seconds) s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            if engine.status.isRunning {
                HStack(spacing: 16) {
                    counter("Hørt", engine.utterancesHeard)
                    counter("Dansk", engine.danishUtterancesAccepted)
                    counter("Svar", history.replies.count)
                }
            }

            if !engine.liveTranscript.isEmpty {
                Text(engine.liveTranscript)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Vises kun her i appen — aldrig som notifikation.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func counter(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)").font(.title3.monospacedDigit()).bold()
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var listenButton: some View {
        Button {
            Task {
                if engine.status.isRunning {
                    engine.stop()
                } else {
                    await engine.start()
                }
            }
        } label: {
            Label(
                engine.status.isRunning ? "Stop lytning" : "Start lytning",
                systemImage: engine.status.isRunning ? "stop.circle.fill" : "ear.badge.waveform"
            )
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .tint(engine.status.isRunning ? .red : .accentColor)
    }

    private func replyCard(_ reply: ReplyRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("På skærmen nu")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(reply.createdAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(reply.topic)
                .font(.headline)
            Text(reply.body)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                if reply.source == .local {
                    Label(reply.source.danishLabel, systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button("Fjern fra skærmen") {
                    Task { await engine.dismissCurrentReply() }
                }
                .font(.caption)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
    }

    private var threadCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Den røde tråd")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let topic = engine.topic, !topic.keywords.isEmpty {
                Text(topic.provisionalLabel)
                    .font(.subheadline.weight(.medium))
                ProgressView(value: min(topic.coherence / 0.5, 1.0))
                    .tint(topic.coherence >= settings.minimumCoherence ? .green : .orange)
                Text("\(topic.utteranceCount) ytringer · \(topic.wordCount) ord · sammenhæng \(Int(topic.coherence * 100)) %")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Venter på, at nogen siger noget på dansk.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func errorCard(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sådan virker det")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("""
            Appen lytter gennem mikrofonen — det kan ikke gøres uden. iOS viser en orange \
            prik øverst på skærmen, så længe der lyttes, og den kan ikke slås fra.

            Du skal ikke sige noget og ikke trykke på noget. Appen finder selv den røde tråd \
            i det, der bliver talt om, og lægger ét svar på låseskærmen. Når næste svar kommer, \
            forsvinder det forrige fra skærmen og lægger sig i historikken.

            Der kommer aldrig en notifikation med, hvad andre har sagt — kun med svaret.
            """)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var statusColour: Color {
        switch engine.status {
        case .listening: return .green
        case .composing: return .blue
        case .startingUp: return .yellow
        case .paused: return .orange
        case .failed: return .red
        case .stopped: return .gray
        }
    }
}
