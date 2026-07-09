import AVFoundation

/// Records a short voice memo to m4a (AAC) and hands back the bytes. The
/// sidecar's /transcribe passes the content type straight to OpenAI, which
/// accepts m4a — no server change needed.
@Observable
@MainActor
final class AudioRecorder {
    private(set) var isRecording = false
    private var recorder: AVAudioRecorder?
    private var url: URL?

    func requestPermission() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { granted in cont.resume(returning: granted) }
        }
    }

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default)
        try session.setActive(true)

        let dir = FileManager.default.temporaryDirectory
        let file = dir.appendingPathComponent("fika-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        let rec = try AVAudioRecorder(url: file, settings: settings)
        rec.record()
        recorder = rec
        url = file
        isRecording = true
    }

    /// Stops and returns the recorded audio bytes (nil if nothing captured).
    func stop() -> Data? {
        recorder?.stop()
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false)
        defer { recorder = nil }
        guard let url else { return nil }
        return try? Data(contentsOf: url)
    }
}
