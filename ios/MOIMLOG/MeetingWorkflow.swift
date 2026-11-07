import SwiftUI
import UniformTypeIdentifiers
import QuickLook

struct TranscriptSegment: Codable { var speaker: String?; var text: String; var timestamp: String }
struct Job: Codable { var state: String; var kind: String?; var error: String? }
struct Sharing: Codable, Identifiable {
    var id: String { participantId }
    var participantId: String; var name: String
    var sermonSharing: String; var lifeSharing: String; var prayerRequests: String
    var prayerSource: String; var needsReview: Bool; var warnings: [String]
    var sunday: String; var youth: String; var meeting: String; var qt: String
}
struct Report: Codable {
    var meetingDate: String; var leader: String; var meetingSummary: String
    var participants: [Sharing]; var unassignedStatements: [String]; var warnings: [String]
}
struct TextInput: Encodable { var text: String }
struct MappingInput: Encodable { var mapping: [String: String?] }
struct AnalysisInput: Encodable { var mode: String; var consent: Bool }
struct ReportInput: Encodable { var report: Report; var complete: Bool }
struct JobResponse: Decodable { var state: String }
struct DownloadResponse: Decodable { var url: String }
struct TemplateUploadResponse: Decodable { var exists: Bool }

extension APIClient {
    func download(_ path: String) async throws -> Data {
        guard let url = URL(string: "api/" + path, relativeTo: baseURL)?.absoluteURL else { throw APIError(message: "서버 주소가 올바르지 않습니다.") }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw APIError(message: "파일을 다운로드하지 못했습니다. 서버의 보고서 양식을 확인해 주세요.") }
        return data
    }
    func upload<T: Decodable>(_ path: String, method: String = "POST", file: URL, mime: String) async throws -> T {
        guard let url = URL(string: "api/" + path, relativeTo: baseURL)?.absoluteURL else { throw APIError(message: "서버 주소가 올바르지 않습니다.") }
        let boundary = UUID().uuidString
        var request = URLRequest(url: url); request.httpMethod = method
        request.setValue("1", forHTTPHeaderField: "X-Moimlog")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"upload.\(file.pathExtension)\"\r\nContent-Type: \(mime)\r\n\r\n".utf8)
        body.append(try Data(contentsOf: file)); body.append(Data("\r\n--\(boundary)--\r\n".utf8)); request.httpBody = body
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            throw APIError(message: obj?["detail"] as? String ?? "파일 전송에 실패했습니다.")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

struct MeetingWorkflowView: View {
    @EnvironmentObject var state: AppState
    let id: String
    @State private var meeting: Meeting?
    @State private var transcript = ""
    @State private var mapping: [String: String] = [:]
    @State private var report: Report?
    @State private var consent = false
    @State private var mode = "ai"
    @State private var importing = false
    @State private var shareURL: URL?
    @State private var previewURL: URL?
    @State private var busy = false
    var base: String { "meetings/\(id)" }
    var speakers: [String] { Array(Set((meeting?.segments ?? []).compactMap(\.speaker))).sorted() }
    var body: some View {
        List {
            if let meeting = meeting {
                Section("음성 및 전사") {
                    NavigationLink("순모임 녹음") { LiveRecordingView(mid: id) }
                    Button("서버에서 전사문 다시 불러오기") { Task { await load() } }
                    Text("다시 불러오면 저장하지 않은 수정 내용은 사라집니다.").font(.footnote).foregroundColor(.secondary)
                    Button("TXT 또는 음성 파일 업로드") { importing = true }
                    Text("음성 변환과 AI 분석 시 Groq로 전송됩니다. 참석자 모두의 동의를 받아주세요.").font(.footnote).foregroundColor(.secondary)
                    Toggle("참석자 모두 외부 음성 처리에 동의", isOn: $consent)
                    Button("업로드한 음성 전사") { Task { await transcribe() } }.disabled(!consent || busy)
                    TextEditor(text: $transcript).frame(minHeight: 160)
                    Button("전사문 저장") { Task { await saveText() } }.disabled(busy || transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Section("화자 연결") {
                    if speakers.isEmpty { Text("화자 표기가 없습니다. 전사문에 ‘화자 1: 내용’ 형식으로 입력한 뒤 저장하세요.").foregroundColor(.secondary) }
                    ForEach(speakers, id: \.self) { speaker in
                        Picker(speaker, selection: Binding(get: { mapping[speaker] ?? "" }, set: { mapping[speaker] = $0 })) {
                            Text("미배정").tag("")
                            ForEach(meeting.participants) { Text($0.name).tag($0.id) }
                            Text("기타").tag("OTHER")
                        }
                    }
                    Button("화자 연결 저장") { Task { await saveMapping() } }.disabled(busy || speakers.isEmpty)
                }
                Section("보고서 분석") {
                    Picker("방식", selection: $mode) { Text("Groq AI").tag("ai"); Text("로컬 검토").tag("local") }
                    Toggle("전사문과 참석자 정보의 Groq 전송에 동의", isOn: $consent)
                    Button("보고서 초안 생성") { Task { await analyze() } }.disabled(busy || (mode == "ai" && !consent))
                    if meeting.job?.state == "processing" { ProgressView("서버에서 처리 중") }
                    if let error = meeting.job?.error, meeting.job?.state == "failed" { Text(error).foregroundColor(.red) }
                }
                if report != nil {
                    Section("보고서") {
                        if meeting.mode == "local" { Text("로컬 검토 초안 · AI 분석 아님").foregroundColor(.secondary) }
                        NavigationLink("보고서 검토 및 수정") { ReportEditor(report: Binding(get: { report! }, set: { report = $0 })) }
                        Button("보고서 저장") { Task { await saveReport(false) } }.disabled(busy)
                        Button("작성 완료") { Task { await saveReport(true) } }.disabled(busy)
                        Button("DOCX 준비") { Task { await download() } }.disabled(busy)
                        if let shareURL = shareURL { Button("DOCX 미리보기") { previewURL = shareURL }; ShareLink(item: shareURL) { Label("DOCX 공유 또는 파일에 저장", systemImage: "square.and.arrow.up") } }
                    }
                }
            } else { ProgressView() }
        }.navigationTitle("모임 작성").quickLookPreview($previewURL)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, .audio, .movie], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            Task { await upload(url) }
        }
        .task {
            await load()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if meeting?.job?.state == "processing" { await load() }
            }
        }
    }
    func perform(_ action: () async throws -> Void) async {
        busy = true; defer { busy = false }
        do { try await action() } catch { state.error = error.localizedDescription }
    }
    func load() async {
        do {
            guard let client = state.client else { return }
            let m: Meeting = try await client.request(base); meeting = m; transcript = m.text ?? ""; report = m.report
            mapping = (m.mapping ?? [:]).reduce(into: [:]) { $0[$1.key] = $1.value ?? "" }
        } catch { state.error = error.localizedDescription }
    }
    func saveText() async { await perform { guard let c = state.client else { return }; let m: Meeting = try await c.send(base + "/transcription", method: "PUT", body: TextInput(text: transcript)); meeting = m; report = m.report; mapping = [:] } }
    func saveMapping() async { await perform { guard let c = state.client else { return }; let values: [String: String?] = Dictionary(uniqueKeysWithValues: speakers.map { ($0, (mapping[$0] ?? "").isEmpty ? nil : mapping[$0]) }); let m: Meeting = try await c.send(base + "/speakers", method: "PUT", body: MappingInput(mapping: values)); meeting = m; report = m.report } }
    func analyze() async { await perform { guard let c = state.client else { return }; let _: JobResponse = try await c.send(base + "/analyze", method: "POST", body: AnalysisInput(mode: mode, consent: consent)); await load() } }
    func transcribe() async { await perform { guard let c = state.client else { return }; let _: JobResponse = try await c.send(base + "/transcribe", method: "POST", body: AnalysisInput(mode: "local", consent: consent)); await load() } }
    func saveReport(_ complete: Bool) async { await perform { guard let c = state.client, let report = report else { return }; let m: Meeting = try await c.send(base + "/report", method: "PUT", body: ReportInput(report: report, complete: complete)); meeting = m; await state.refreshMeetings() } }
    func upload(_ url: URL) async { await perform { guard let c = state.client else { return }; let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }; let m: Meeting = try await c.upload(base + "/upload", file: url, mime: url.pathExtension.lowercased() == "txt" ? "text/plain" : "application/octet-stream"); meeting = m; transcript = m.text ?? ""; report = m.report } }
    func download() async { await perform { guard let c = state.client else { return }; let _: DownloadResponse = try await c.request(base + "/generate-docx", method: "POST"); let data = try await c.download(base + "/download"); let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(meeting?.meetingDate ?? "meeting")_moim_report.docx"); try data.write(to: url, options: .atomic); shareURL = url } }
}

struct ReportEditor: View {
    @Binding var report: Report
    var body: some View {
        Form {
            Section("모임 요약") { TextEditor(text: $report.meetingSummary).frame(minHeight: 100) }
            ForEach(report.warnings, id: \.self) { Text($0).foregroundColor(.orange) }
            ForEach($report.participants) { $person in
                Section(person.name) {
                    Toggle("내용 확인 필요", isOn: $person.needsReview)
                    if person.prayerSource == "inferred" { Text("기도제목은 AI 추론입니다. 원문을 확인하세요.").foregroundColor(.orange) }
                    ForEach(person.warnings, id: \.self) { Text($0).foregroundColor(.orange) }
                    Text("설교나눔"); TextEditor(text: $person.sermonSharing).frame(minHeight: 80)
                    Text("삶나눔"); TextEditor(text: $person.lifeSharing).frame(minHeight: 80)
                    Text("기도제목"); TextEditor(text: $person.prayerRequests).frame(minHeight: 80).onChange(of: person.prayerRequests) { person.prayerSource = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "none" : "explicit" }
                    attendance("주일예배", $person.sunday); attendance("대학부예배", $person.youth); attendance("순모임", $person.meeting); attendance("큐티", $person.qt)
                }
            }
            Section("미배정 발언 · 원문 확인 필요") {
                ForEach(report.unassignedStatements.indices, id: \.self) { index in TextEditor(text: $report.unassignedStatements[index]).frame(minHeight: 80) }
            }
        }.navigationTitle("보고서 검토")
    }
    func attendance(_ label: String, _ value: Binding<String>) -> some View {
        Picker(label, selection: value) { Text("미확인").tag("unknown"); Text("예").tag("yes"); Text("아니요").tag("no") }
    }
}
