import SwiftUI
import AVFoundation

@MainActor final class NativeRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var recording = false
    @Published var paused = false
    @Published var elapsed: TimeInterval = 0
    @Published var level: Float = 0
    @Published var error: String?
    @Published var fileURL: URL?
    private var recorder: AVAudioRecorder?
    private var timer: Timer?

    func start() async {
        let allowed = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard allowed else { error = "마이크 사용 권한을 설정에서 허용해 주세요."; return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
            let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let url = directory.appendingPathComponent("meeting-\(UUID().uuidString).m4a")
            let settings: [String: Any] = [AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue]
            let audio = try AVAudioRecorder(url: url, settings: settings)
            audio.delegate = self; audio.isMeteringEnabled = true
            guard audio.record(forDuration: 7200) else { throw CocoaError(.fileWriteUnknown) }
            recorder = audio; fileURL = url; recording = true; paused = false
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let audio = self.recorder else { return }
                    audio.updateMeters(); self.elapsed = audio.currentTime
                    self.level = max(0, (audio.averagePower(forChannel: 0) + 60) / 60)
                }
            }
        } catch { self.error = "녹음을 시작하지 못했어요: \(error.localizedDescription)" }
    }
    func togglePause() { guard let recorder else { return }; if paused { if recorder.record() { paused = false } else { error = "녹음을 재개하지 못했어요." } } else { recorder.pause(); paused = true } }
    func stop() { recorder?.stop(); timer?.invalidate(); timer = nil; recording = false; paused = false; try? AVAudioSession.sharedInstance().setActive(false) }
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in self.timer?.invalidate(); self.recording = false; if !flag { self.error = "녹음이 중단됐어요. 저장된 파일을 확인해 주세요." } }
    }
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in self.timer?.invalidate(); self.recording = false; self.error = "녹음 파일을 저장하는 중 문제가 생겼어요." }
    }
}

struct NativeRecordingView: View {
    @StateObject private var recorder = NativeRecorder()
    @State private var confirmStop = false
    var body: some View {
        VStack(spacing: 24) {
            Text(recorder.recording ? (recorder.paused ? "일시정지" : "녹음 중") : "녹음 준비")
            Text(Duration.seconds(recorder.elapsed).formatted(.time(pattern: .minuteSecond)))
                .font(.system(size: 56, weight: .medium, design: .rounded)).monospacedDigit()
                .accessibilityLabel("녹음 시간 \(Int(recorder.elapsed))초")
            ProgressView(value: recorder.level).accessibilityLabel("마이크 입력 크기")
            if let error = recorder.error { Text(error).foregroundStyle(.red) }
            if recorder.recording {
                Button(recorder.paused ? "재개" : "일시정지") { recorder.togglePause() }.buttonStyle(.bordered)
                Button("녹음 종료") { confirmStop = true }.buttonStyle(.borderedProminent)
            } else if let file = recorder.fileURL {
                Text("기기에 녹음 파일을 저장했어요. 서버 전송은 아직 지원하지 않아요.")
                ShareLink(item: file) { Label("녹음 파일 공유", systemImage: "square.and.arrow.up") }
            } else {
                Button("녹음 시작") { Task { await recorder.start() } }.buttonStyle(.borderedProminent)
            }
        }.padding().navigationTitle("순모임 녹음")
        .confirmationDialog("녹음을 종료할까요?", isPresented: $confirmStop) {
            Button("녹음 종료", role: .destructive) { recorder.stop() }
            Button("계속 녹음", role: .cancel) { }
        }
    }
}
