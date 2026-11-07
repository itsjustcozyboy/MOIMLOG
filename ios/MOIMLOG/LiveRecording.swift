import SwiftUI
import AVFoundation

struct LiveChunk: Decodable { var seq: Int; var state: String; var duration: Double; var error: String }
struct LiveSegment: Decodable { var timestamp: String; var text: String }
struct LiveStatus: Decodable { var mode: String; var ended: Int; var expected: Int?; var complete: Bool; var chunks: [LiveChunk]; var segments: [LiveSegment] }
struct LiveStart: Encodable { var consent: Bool; var mock = false }
struct LiveEnd: Encodable { var count: Int }
struct ChunkSaved: Decodable { var saved: Int }
struct StartResponse: Decodable { var id: String }

@MainActor final class LiveRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var recording = false
    @Published var status: LiveStatus?
    @Published var message = ""
    @Published var pending = 0
    @Published var elapsed = 0.0
    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var syncing = false
    private var stopping = false
    private var next = 0
    private var client: APIClient?
    private var mid = ""
    private var directory: URL?
    private var observer: NSObjectProtocol?
    private var endMarker: URL? { directory?.appendingPathComponent("end") }
    private var base: String { "meetings/\(mid)/recording" }
    func setup(client: APIClient, mid: String, userID: String) async {
        guard self.client == nil else { return }
        self.client = client; self.mid = mid
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        directory = root.appendingPathComponent("Recordings", isDirectory: true).appendingPathComponent(userID, isDirectory: true).appendingPathComponent(mid, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory!, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            // A finalized file stays on disk even after upload. Re-upload is idempotent.
            await sync()
            next = max(localFiles().map { $0.0 + 1 }.max() ?? 0, status?.chunks.map { $0.seq + 1 }.max() ?? 0)
            elapsed = status?.chunks.reduce(0) { $0 + $1.duration } ?? 0
            observer = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.pause(); self?.message = "오디오 중단으로 일시정지했습니다. 저장된 구간을 확인하고 재개하세요." } }
            timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in Task { @MainActor in await self?.sync() } }
        } catch { message = "기기 저장소를 열 수 없습니다: \(error.localizedDescription)" }
    }
    func localFiles() -> [(Int, URL)] {
        guard let directory = directory, let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
        return files.compactMap { url in guard url.pathExtension == "wav", let n = Int(url.deletingPathExtension().lastPathComponent) else { return nil }; return (n, url) }.sorted { $0.0 < $1.0 }
    }
    func start(consent: Bool) async {
        guard consent, let client = client, directory != nil else { return }
        guard status?.ended != 1, !FileManager.default.fileExists(atPath: endMarker?.path ?? "") else { message = "이미 종료된 녹음입니다."; return }
        let allowed = await withCheckedContinuation { continuation in AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) } }
        guard allowed else { message = "마이크 권한을 허용해 주세요."; return }
        do {
            let _: StartResponse = try await client.send(base, method: "POST", body: LiveStart(consent: true))
            let remote: LiveStatus = try await client.request(base)
            status = remote
            guard remote.ended == 0 else { throw APIError(message: "이미 종료된 녹음입니다.") }
            next = max(localFiles().map { $0.0 + 1 }.max() ?? 0, remote.chunks.map { $0.seq + 1 }.max() ?? 0)
            let audio = AVAudioSession.sharedInstance(); try audio.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth]); try audio.setActive(true)
            recording = true; stopping = false; try beginChunk(); message = "녹음 중 · 약 14초마다 기기에 저장하고 전송합니다."
        } catch { recording = false; message = error.localizedDescription }
    }
    private func beginChunk() throws {
        guard let directory = directory else { throw APIError(message: "저장소가 없습니다.") }
        guard elapsed < 7200 else { finish(); return }
        let url = directory.appendingPathComponent("\(next).wav")
        guard !FileManager.default.fileExists(atPath: url.path) else { throw APIError(message: "기존 녹음 구간과 순번이 겹칩니다. 동기화 후 다시 시도하세요.") }
        let settings: [String: Any] = [AVFormatIDKey: Int(kAudioFormatLinearPCM), AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
        let audio = try AVAudioRecorder(url: url, settings: settings); audio.delegate = self
        guard audio.record(forDuration: min(14, 7200 - elapsed)) else { throw APIError(message: "녹음을 시작하지 못했습니다.") }
        recorder = audio
    }
    private func closeChunk() {
        guard let audio = recorder else { return }
        let duration = audio.currentTime; audio.delegate = nil; audio.stop(); recorder = nil
        if duration > 0 { elapsed += duration; next += 1 } else { try? FileManager.default.removeItem(at: audio.url) }
    }
    func pause() { guard recording else { return }; recording = false; closeChunk(); Task { await sync() } }
    func finish() {
        guard !stopping else { return }; stopping = true; recording = false; closeChunk()
        do { guard let marker = endMarker else { throw APIError(message: "저장소가 없습니다.") }; try Data(String(next).utf8).write(to: marker, options: .atomic); message = "종료 요청을 저장했습니다. 구간을 전송합니다."; Task { await sync() } }
        catch { message = "종료 정보를 저장하지 못했습니다: \(error.localizedDescription)"; stopping = false }
    }
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            guard self.recording, self.recorder === recorder else { return }
            self.recorder = nil
            if flag { self.elapsed += 14; self.next += 1; Task { await self.sync() }; do { try self.beginChunk() } catch { self.recording = false; self.message = error.localizedDescription } }
            else { self.recording = false; self.message = "녹음 구간 저장에 실패했습니다. 기기의 파일을 확인하세요." }
        }
    }
    func sync() async {
        guard !syncing, let client = client else { return }; syncing = true; defer { syncing = false }
        do {
            // Do not transmit the file currently being written.
            let files = localFiles().filter { $0.1 != recorder?.url }
            let remote: LiveStatus = try await client.request(base); status = remote
            let present = Set(remote.chunks.map(\.seq)); pending = files.filter { !present.contains($0.0) }.count
            for (seq, url) in files where !present.contains(seq) {
                let _: ChunkSaved = try await client.upload(base + "/chunks/\(seq)", method: "PUT", file: url, mime: "audio/wav")
                pending -= 1
            }
            if let marker = endMarker, let data = try? Data(contentsOf: marker), let count = Int(String(decoding: data, as: UTF8.self)) {
                let _: LiveStatus = try await client.send(base + "/end", method: "POST", body: LiveEnd(count: count))
                try FileManager.default.removeItem(at: marker)
            }
            status = try await client.request(base)
        } catch { message = "서버 동기화 대기: \(error.localizedDescription). 기기 원본을 보관합니다." }
    }
    func retry() async { do { guard let client = client else { return }; let _: OK = try await client.request(base + "/retry", method: "POST"); await sync() } catch { message = error.localizedDescription } }
    func review() async { do { guard let client = client else { return }; let _: Meeting = try await client.request(base + "/review", method: "POST"); message = "최종 전사문을 저장했습니다. 이전 화면에서 다시 열어 확인하세요." } catch { message = error.localizedDescription } }
    func shutdown() { pause(); timer?.invalidate(); timer = nil; if let observer = observer { NotificationCenter.default.removeObserver(observer) }; observer = nil }
}
struct LiveRecordingView: View {
    @EnvironmentObject var state: AppState
    @StateObject private var recorder = LiveRecorder()
    let mid: String
    @State private var consent = false
    @State private var confirmEnd = false
    var body: some View {
        List {
            Section("녹음 동의") { Toggle("모든 참석자가 녹음과 Groq 전송에 동의했습니다", isOn: $consent).disabled(recorder.recording) }
            Section("녹음") {
                Text(recorder.recording ? "녹음 중" : "일시정지 또는 대기")
                Text("기록된 시간: \(Int(recorder.elapsed / 60))분 \(Int(recorder.elapsed) % 60)초")
                Text(recorder.message).font(.footnote).foregroundColor(.secondary)
                if recorder.status?.ended != 1 {
                    if recorder.recording { Button("일시정지") { recorder.pause() } }
                    else { Button("녹음 시작 또는 재개") { Task { await recorder.start(consent: consent) } }.disabled(!consent) }
                    Button("녹음 종료") { confirmEnd = true }.disabled(recorder.status == nil && !recorder.recording)
                }
                Button("지금 동기화") { Task { await recorder.sync() } }
                Text("업로드 대기 \(recorder.pending)개 · 원본 구간은 기기와 서버에 보관됩니다. 화면을 벗어나면 녹음이 일시정지됩니다.").font(.footnote)
            }
            Section("전사 상태") {
                ForEach(recorder.status?.chunks ?? [], id: \.seq) { chunk in Text("구간 \(chunk.seq + 1): \(chunk.state) \(chunk.error)") }
                if recorder.status?.chunks.contains(where: { $0.state == "failed" || $0.state == "budget" }) == true { Button("실패 구간 재시도") { Task { await recorder.retry() } } }
                if recorder.status?.complete == true { Button("최종 전사문 저장") { Task { await recorder.review() } } }
            }
            Section("전사문") { ForEach(Array((recorder.status?.segments ?? []).enumerated()), id: \.offset) { _, segment in Text("\(segment.timestamp) · \(segment.text)") } }
        }.navigationTitle("순모임 녹음")
        .task { if let client = state.client, let user = state.user { await recorder.setup(client: client, mid: mid, userID: user.id) } }
        .onDisappear { recorder.shutdown() }
        .confirmationDialog("녹음을 종료하고 전사할까요?", isPresented: $confirmEnd) { Button("녹음 종료") { recorder.finish() } }
    }
}
