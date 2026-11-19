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
    private static weak var microphoneOwner: LiveRecorder?
    @Published var liveCompletions = 0
    @Published var deferredCompletions = 0
    @Published var backgroundChunks = 0
    @Published private(set) var ready = false
    private var starting = false
    @Published var localCount = 0
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
            let staged = try FileManager.default.contentsOfDirectory(at: directory!, includingPropertiesForKeys: nil)
            for url in staged where url.lastPathComponent.hasPrefix("writing-") && url.pathExtension == "wav" {
                guard let sequence = Int(url.deletingPathExtension().lastPathComponent.dropFirst(8)) else { continue }
                let file = try AVAudioFile(forReading: url)
                guard file.length > 0 else { throw APIError(message: "중단된 구간의 파일을 확인해 주세요.") }
                try FileManager.default.moveItem(at: url, to: directory!.appendingPathComponent("\(sequence).wav"))
            }
            localCount = localFiles().count
            await sync()
            next = max(localFiles().map { $0.0 + 1 }.max() ?? 0, status?.chunks.map { $0.seq + 1 }.max() ?? 0)
            elapsed = status?.chunks.reduce(0) { $0 + $1.duration } ?? 0
            let present = Set(status?.chunks.map(\.seq) ?? [])
            for (seq, url) in localFiles() where !present.contains(seq) {
                let file = try AVAudioFile(forReading: url)
                elapsed += Double(file.length) / file.fileFormat.sampleRate
            }
            observer = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
                guard (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue else { return }
                Task { @MainActor in guard self?.recording == true else { return }; self?.pause(); self?.message = "오디오 중단으로 일시정지했습니다. 저장된 구간을 확인하고 재개하세요." } }
            ready = true
            timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in Task { @MainActor in await self?.sync() } }
        } catch { message = "기기 저장소를 열 수 없습니다: \(error.localizedDescription)" }
    }
    func localFiles() -> [(Int, URL)] {
        guard let directory = directory, let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
        return files.compactMap { url in guard url.pathExtension == "wav", let n = Int(url.deletingPathExtension().lastPathComponent) else { return nil }; return (n, url) }.sorted { $0.0 < $1.0 }
    }
    func start(consent: Bool) async {
        guard ready, !starting, !recording, Self.microphoneOwner == nil else { message = "다른 녹음이 진행 중입니다."; return }
        guard consent, let client = client, directory != nil else { return }
        guard status?.ended != 1, !FileManager.default.fileExists(atPath: endMarker?.path ?? "") else { message = "이미 종료된 녹음입니다."; return }
        starting = true
        Self.microphoneOwner = self
        defer { starting = false; if !recording { Self.microphoneOwner = nil } }
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
        guard elapsed < 7200 else { pause(); message = "120분에 도달했습니다. 녹음 종료를 눌러 주세요."; return }
        let url = directory.appendingPathComponent("\(next).wav")
        guard !FileManager.default.fileExists(atPath: url.path) else { throw APIError(message: "기존 녹음 구간과 순번이 겹칩니다. 동기화 후 다시 시도하세요.") }
        let settings: [String: Any] = [AVFormatIDKey: Int(kAudioFormatLinearPCM), AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
        let staging = directory.appendingPathComponent("writing-\(next).wav")
        guard !FileManager.default.fileExists(atPath: staging.path) else { throw APIError(message: "미확정 녹음 파일을 확인해 주세요.") }
        let audio = try AVAudioRecorder(url: staging, settings: settings); audio.delegate = self
        guard audio.record(forDuration: min(14, 7200 - elapsed)) else { throw APIError(message: "녹음을 시작하지 못했습니다.") }
        recorder = audio
    }
    @discardableResult private func closeChunk() -> Bool {
        guard let audio = recorder else { return true }
        audio.delegate = nil; audio.stop(); recorder = nil
        do { try commit(audio.url); return true } catch { message = error.localizedDescription; ready = false; return false }
    }
    private func commit(_ url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        guard file.length > 0 else { try FileManager.default.removeItem(at: url); return }
        let duration = Double(file.length) / file.fileFormat.sampleRate
        try FileManager.default.moveItem(at: url, to: url.deletingLastPathComponent().appendingPathComponent("\(next).wav"))
        elapsed += duration
        next += 1
        pending += 1
        localCount += 1
        if UIApplication.shared.applicationState == .background { backgroundChunks += 1 }
    }
    func pause() { guard recording else { return }; recording = false; if Self.microphoneOwner === self { Self.microphoneOwner = nil }; closeChunk(); Task { await sync() } }
    func finish() {
        guard ready, !starting, !stopping else { return }; stopping = true; recording = false; if Self.microphoneOwner === self { Self.microphoneOwner = nil }; guard closeChunk() else { stopping = false; return }
        do { guard let marker = endMarker else { throw APIError(message: "저장소가 없습니다.") }; try Data(String(next).utf8).write(to: marker, options: .atomic); message = "종료 요청을 저장했습니다. 구간을 전송합니다."; Task { await sync() } }
        catch { message = "종료 정보를 저장하지 못했습니다: \(error.localizedDescription)"; stopping = false }
    }
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            guard self.recording, self.recorder === recorder else { return }
            self.recorder = nil
            if flag { do { try self.commit(recorder.url); Task { await self.sync() }; try self.beginChunk() } catch { self.pause(); self.message = error.localizedDescription } }
            else { self.pause(); self.message = "녹음 구간 저장에 실패했습니다. 기기의 파일을 확인하세요." }
        }
    }
    func sync() async {
        guard !syncing, let client = client else { return }; syncing = true; defer { syncing = false }
        do {
            // Do not transmit the file currently being written.
            let files = localFiles().filter { $0.1 != recorder?.url }
            let remote: LiveStatus = try await client.request(base)
            if let previous = status {
                let completed = Set(previous.chunks.filter { $0.state == "done" }.map(\.seq))
                let newlyObserved = remote.chunks.filter { $0.state == "done" && !completed.contains($0.seq) }.count
                if recording { liveCompletions += newlyObserved } else { deferredCompletions += newlyObserved }
            }
            status = remote
            let present = Set(remote.chunks.map(\.seq)); pending = files.filter { !present.contains($0.0) }.count
            for (seq, url) in files where !present.contains(seq) {
                let destination = client.baseURL.appendingPathComponent("api/" + base + "/chunks/\(seq)")
                try await RecordingTransfers.shared.enqueue(file: url, destination: destination)
            }
            if let marker = endMarker, let data = try? Data(contentsOf: marker), let count = Int(String(decoding: data, as: UTF8.self)), count >= 0, count <= 10000, present == Set(0..<count) {
                status = try await client.send(base + "/end", method: "POST", body: LiveEnd(count: count))
                try FileManager.default.removeItem(at: marker)
            }
            if remote.complete { timer?.invalidate(); timer = nil }
        } catch { message = "서버 동기화 대기: \(error.localizedDescription). 기기 원본을 보관합니다." }
    }
    func retry() async { do { guard let client = client else { return }; let _: OK = try await client.request(base + "/retry", method: "POST"); await sync() } catch { message = error.localizedDescription } }
    func review() async { do { guard let client = client else { return }; let _: Meeting = try await client.request(base + "/review", method: "POST"); message = "최종 전사문을 저장했습니다. 이전 화면에서 다시 열어 확인하세요." } catch { message = error.localizedDescription } }
    func shutdown() { pause(); timer?.invalidate(); timer = nil; if let observer = observer { NotificationCenter.default.removeObserver(observer) }; observer = nil }
}
struct LiveRecordingView: View {
    @EnvironmentObject var state: AppState
    let mid: String
    var body: some View { LiveRecordingControls(recorder: state.liveRecorder(for: mid), mid: mid) }
}
struct LiveRecordingControls: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var recorder: LiveRecorder
    let mid: String
    @State private var consent = false
    @State private var confirmEnd = false
    var body: some View {
        List {
            Section("녹음 동의") { Toggle("모든 참석자가 녹음과 Groq 전송에 동의했습니다", isOn: $consent).disabled(recorder.recording) }
            Section("녹음") {
                Text(recorder.recording ? "녹음 중" : "일시정지 또는 대기")
                Text("기록된 시간: \(Int(recorder.elapsed / 60))분 \(Int(recorder.elapsed) % 60)초")
                Text("백그라운드에서 저장한 구간 \(recorder.backgroundChunks)개")
                Text(recorder.message).font(.footnote).foregroundColor(.secondary)
                if recorder.status?.ended != 1 {
                    if recorder.recording { Button("일시정지") { recorder.pause() } }
                    else { Button("녹음 시작 또는 재개") { Task { await recorder.start(consent: consent) } }.disabled(!consent || !recorder.ready) }
                    Button("녹음 종료") { confirmEnd = true }.disabled(recorder.status == nil && !recorder.recording)
                }
                if recorder.pending > 0 { Text("서버 확인 대기 \(recorder.pending)개 · 연결 복구 후 지연 전사될 수 있습니다.") }
                Button("지금 동기화") { Task { await recorder.sync() } }
                Text("기기 저장 \(recorder.localCount)개 · 서버 확인 \(recorder.status?.chunks.count ?? 0)개 · 전사 완료 \(recorder.status?.chunks.filter { $0.state == "done" }.count ?? 0)개").font(.footnote)
            }
            Section("전사 상태") {
                Text("이번 실행에서 완료 확인 · 녹음 중 \(recorder.liveCompletions)개 · 대기 또는 종료 후 \(recorder.deferredCompletions)개")
                ForEach(recorder.status?.chunks ?? [], id: \.seq) { chunk in Text("구간 \(chunk.seq + 1): \(chunk.state) \(chunk.error)") }
                if recorder.status?.chunks.contains(where: { $0.state == "failed" || $0.state == "budget" }) == true { Button("실패 구간 재시도") { Task { await recorder.retry() } } }
                if recorder.status?.complete == true { Button("최종 전사문 저장") { Task { await recorder.review() } } }
            }
            Section("전사문") { ForEach(Array((recorder.status?.segments ?? []).enumerated()), id: \.offset) { _, segment in Text("\(segment.timestamp) · \(segment.text)") } }
        }.navigationTitle("순모임 녹음")
        .task { if let client = state.client, let user = state.user { await recorder.setup(client: client, mid: mid, userID: user.id) } }

        .confirmationDialog("녹음을 종료하고 전사할까요?", isPresented: $confirmEnd) { Button("녹음 종료") { recorder.finish() } }
    }
}
