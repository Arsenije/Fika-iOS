import SwiftUI

/// Mic button that records a memo, transcribes it via the sidecar, and appends
/// the text to the bound string. Off until tapped.
struct VoiceButton: View {
    @Environment(AppState.self) private var app
    @Binding var text: String
    @State private var recorder = AudioRecorder()
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Button {
            Task { await toggle() }
        } label: {
            Image(systemName: busy ? "waveform" : (recorder.isRecording ? "stop.circle.fill" : "mic.circle"))
                .font(.title2)
                .symbolEffect(.pulse, isActive: recorder.isRecording || busy)
                .foregroundStyle(recorder.isRecording ? Color.red : Color.accentColor)
        }
        .disabled(busy)
        .alert("Voice", isPresented: .constant(error != nil), actions: {
            Button("OK") { error = nil }
        }, message: { Text(error ?? "") })
    }

    private func toggle() async {
        if recorder.isRecording {
            guard let audio = recorder.stop() else { return }
            busy = true
            defer { busy = false }
            do {
                let t = try await app.api.transcribe(audio)
                if !t.isEmpty {
                    text += text.isEmpty ? t : " \(t)"
                }
            } catch {
                self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
        } else {
            guard await recorder.requestPermission() else {
                error = "Microphone access is off. Enable it in iOS Settings."
                return
            }
            do { try recorder.start() } catch { self.error = error.localizedDescription }
        }
    }
}
