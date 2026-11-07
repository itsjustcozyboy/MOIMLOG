import SwiftUI
import UniformTypeIdentifiers

struct Profile: Codable {
    let id: String
    let email: String
    var name: String
    var community: String
    var isLeader: Bool
    var members: [String]
    var retentionDays: Int
}
struct Person: Codable, Identifiable, Hashable {
    var id: String
    var name: String
}
struct Meeting: Codable, Identifiable {
    let id: String
    var meetingDate: String
    var leader: String
    var title: String
    var participants: [Person]
    var status: String
    var step: Int
    var sermonTitle: String?
    var question: String?
    var text: String?
    var segments: [TranscriptSegment]?
    var mapping: [String: String?]?
    var report: Report?
    var job: Job?
    var mode: String?
}
struct MeetingInput: Encodable {
    var meetingDate: String
    var leader: String
    var title: String
    var sermonTitle: String
    var question: String
    var participants: [Person]
    var step = 2
}
struct Credentials: Encodable { let email: String; let password: String; let name: String }
struct OK: Decodable { let ok: Bool }
struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

actor APIClient {
    let baseURL: URL
    let session: URLSession
    init(baseURL: URL) {
        self.baseURL = baseURL
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = .shared
        configuration.httpShouldSetCookies = true
        session = URLSession(configuration: configuration)
    }
    func request<T: Decodable>(_ path: String, method: String = "GET", body: Data? = nil) async throws -> T {
        guard let url = URL(string: "api/" + path, relativeTo: baseURL)?.absoluteURL else { throw APIError(message: "서버 주소가 올바르지 않습니다.") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("1", forHTTPHeaderField: "X-Moimlog")
        if let body = body { request.httpBody = body; request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError(message: "서버 응답을 확인할 수 없습니다.") }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 && path != "auth/login" { throw APIError(message: "세션이 만료되었습니다. 다시 로그인해 주세요.") }
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            throw APIError(message: object?["detail"] as? String ?? "서버 요청에 실패했습니다. (\(http.statusCode))")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
    func send<T: Decodable, B: Encodable>(_ path: String, method: String, body: B) async throws -> T {
        try await request(path, method: method, body: JSONEncoder().encode(body))
    }
}

@MainActor final class AppState: ObservableObject {
    @Published var server = UserDefaults.standard.string(forKey: "serverURL") ?? ""
    @Published var user: Profile?
    @Published var meetings: [Meeting] = []
    @Published var error: String?
    @Published var busy = false
    var client: APIClient? {
        let value = server.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var parts = URLComponents(string: value), parts.scheme?.lowercased() == "https", parts.host != nil, parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil else { return nil }
        if !parts.path.hasSuffix("/") { parts.path += "/" }
        guard let url = parts.url else { return nil }
        return APIClient(baseURL: url)
    }
    func run(_ operation: () async throws -> Void) async {
        busy = true; error = nil
        defer { busy = false }
        do { try await operation() } catch { self.error = error.localizedDescription }
    }
    func restore() async {
        guard let client = client else { return }
        do {
            let profile: Profile = try await client.request("me")
            user = profile
            await refreshMeetings()
        } catch { user = nil }
    }
    func refreshMeetings() async {
        guard let client = client else { return }
        do { meetings = try await client.request("meetings") }
        catch { self.error = error.localizedDescription }
    }
    func authenticate(email: String, password: String, name: String, register: Bool) async {
        await run {
            guard let client = client else { throw APIError(message: "HTTPS 서버 주소를 입력해 주세요.") }
            let _: OK = try await client.send("auth/" + (register ? "register" : "login"), method: "POST", body: Credentials(email: email, password: password, name: name))
            UserDefaults.standard.set(server.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "serverURL")
            user = try await client.request("me")
            await refreshMeetings()
        }
    }
    func logout() async {
        await run {
            guard let client = client else { return }
            let _: OK = try await client.request("auth/logout", method: "POST")
            user = nil; meetings = []
        }
    }
}

@main struct MOIMLOGApp: App {
    @StateObject private var state = AppState()
    var body: some Scene { WindowGroup { RootView().environmentObject(state).task { await state.restore() } } }
}
struct RootView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        Group {
            if state.user == nil { AuthView() }
            else {
                TabView {
                    NavigationStack { HomeView() }.tabItem { Label("홈", systemImage: "house") }
                    NavigationStack { HistoryView() }.tabItem { Label("기록", systemImage: "folder") }
                    NavigationStack { SettingsView() }.tabItem { Label("내 정보", systemImage: "person.crop.circle") }
                }
            }
        }
        .alert("안내", isPresented: Binding(get: { state.error != nil }, set: { if !$0 { state.error = nil } })) { Button("확인", role: .cancel) {} } message: { Text(state.error ?? "") }
    }
}
struct AuthView: View {
    @EnvironmentObject var state: AppState
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var register = false
    var body: some View {
        NavigationStack {
            Form {
                Section("서버 연결") {
                    TextField("https://서버 주소", text: $state.server).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    Text("기존 MOIMLOG 서버의 HTTPS 주소를 입력하세요.").font(.footnote).foregroundColor(.secondary)
                }
                Section(register ? "계정 만들기" : "로그인") {
                    if register { TextField("이름", text: $name).textContentType(.name) }
                    TextField("이메일", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("비밀번호 (10자 이상)", text: $password).textContentType(register ? .newPassword : .password)
                    Button(register ? "계정 만들기" : "로그인") { Task { await state.authenticate(email: email, password: password, name: name, register: register) } }
                        .disabled(state.busy || email.isEmpty || password.count < 10 || (register && name.trimmingCharacters(in: .whitespaces).isEmpty))
                    Button(register ? "로그인으로 돌아가기" : "처음이신가요? 계정 만들기") { register.toggle() }
                }
            }.navigationTitle("모임록")
        }
    }
}
struct MeetingRow: View {
    let meeting: Meeting
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(meeting.title.isEmpty ? "순모임" : meeting.title).font(.headline)
            Text("\(meeting.meetingDate) · \(meeting.status == "complete" ? "작성 완료" : meeting.status == "review" ? "검토 필요" : "작성 중")").font(.subheadline).foregroundColor(.secondary)
        }
    }
}
struct HomeView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        List {
            Section {
                Text("\(state.user?.name ?? "순장")님, 반가워요").font(.title2.bold())
                NavigationLink("새 순모임 시작") { CreateMeetingView() }
            }
            Section("최근 순모임") {
                if state.meetings.isEmpty { Text("아직 모임 기록이 없어요.").foregroundColor(.secondary) }
                ForEach(Array(state.meetings.prefix(3))) { meeting in NavigationLink { MeetingDetailView(id: meeting.id) } label: { MeetingRow(meeting: meeting) } }
            }
        }.navigationTitle("홈").refreshable { await state.refreshMeetings() }
    }
}
struct HistoryView: View {
    @EnvironmentObject var state: AppState
    @State private var search = ""
    var filtered: [Meeting] { state.meetings.filter { search.isEmpty || "\($0.title) \($0.meetingDate) \($0.leader) \($0.participants.map(\.name).joined(separator: " "))".localizedCaseInsensitiveContains(search) } }
    var body: some View {
        List {
            if filtered.isEmpty { Text("해당하는 모임 기록이 없어요.").foregroundColor(.secondary) }
            ForEach(filtered) { meeting in NavigationLink { MeetingDetailView(id: meeting.id) } label: { MeetingRow(meeting: meeting) } }
        }.navigationTitle("기록").searchable(text: $search, prompt: "제목, 날짜, 이름 검색").refreshable { await state.refreshMeetings() }
    }
}
struct MeetingDetailView: View {
    @EnvironmentObject var state: AppState
    let id: String
    @State private var meeting: Meeting?
    var body: some View {
        List {
            if let m = meeting {
                Section("모임 정보") {
                    LabeledContent("날짜", value: m.meetingDate)
                    LabeledContent("순장", value: m.leader)
                    LabeledContent("상태", value: m.status == "complete" ? "작성 완료" : m.status == "review" ? "검토 필요" : "작성 중")
                    if let title = m.sermonTitle, !title.isEmpty { LabeledContent("설교 제목", value: title) }
                    if let question = m.question, !question.isEmpty { LabeledContent("나눔 질문", value: question) }
                }
                Section("참석자") { ForEach(m.participants) { Text($0.name) } }
                if let text = m.text, !text.isEmpty { Section("저장된 전사문") { Text(text).textSelection(.enabled) } }
                Section("작성") { NavigationLink("녹음 및 보고서 작성") { MeetingWorkflowView(id: id) } }
            } else { ProgressView() }
        }.navigationTitle(meeting?.title.isEmpty == false ? meeting!.title : "순모임")
        .task { do { guard let client = state.client else { return }; meeting = try await client.request("meetings/\(id)") } catch { state.error = error.localizedDescription } }
    }
}
struct CreateMeetingView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) var dismiss
    @State private var date = Date()
    @State private var leader = ""
    @State private var title = ""
    @State private var sermon = ""
    @State private var question = ""
    @State private var selected: Set<String> = []
    @State private var extra = ""
    @State private var extras: [Person] = []
    var body: some View {
        Form {
            Section("모임 정보") {
                DatePicker("날짜", selection: $date, displayedComponents: .date)
                TextField("순장 이름", text: $leader)
                TextField("모임 제목", text: $title)
                TextField("설교 제목", text: $sermon)
                TextField("나눔 질문", text: $question, axis: .vertical)
            }
            Section("참석자 선택") {
                ForEach(Array((state.user?.members ?? []).enumerated()), id: \.offset) { index, name in
                    let key = "member-\(index)"
                    Toggle(name, isOn: Binding(get: { selected.contains(key) }, set: { if $0 { selected.insert(key) } else { selected.remove(key) } }))
                }
                ForEach(extras) { person in Text(person.name) }
                HStack { TextField("참석자 이름 직접 추가", text: $extra); Button("추가") { let name = extra.trimmingCharacters(in: .whitespacesAndNewlines); if !name.isEmpty { extras.append(Person(id: UUID().uuidString, name: name)); extra = "" } } }
                if !extras.isEmpty { Button("직접 추가한 참석자 지우기") { extras = [] } }
            }
            Section {
                Button("순모임 만들기") { Task { await create() } }.disabled(state.busy || leader.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (selected.isEmpty && extras.isEmpty))
            }
        }.navigationTitle("새 순모임").onAppear { if leader.isEmpty { leader = state.user?.name ?? "" } }
    }
    func create() async {
        await state.run {
            guard let client = state.client else { return }
            let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
            let members = (state.user?.members ?? []).enumerated().compactMap { index, name in selected.contains("member-\(index)") ? Person(id: UUID().uuidString, name: name) : nil }
            let input = MeetingInput(meetingDate: formatter.string(from: date), leader: leader.trimmingCharacters(in: .whitespacesAndNewlines), title: title, sermonTitle: sermon, question: question, participants: members + extras)
            let _: Meeting = try await client.send("meetings", method: "POST", body: input)
            await state.refreshMeetings(); dismiss()
        }
    }
}
struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var name = ""
    @State private var community = ""
    @State private var isLeader = true
    @State private var members = ""
    @State private var retention = 90
    @State private var importingTemplate = false
    var body: some View {
        Form {
            Section("프로필") {
                Text(state.user?.email ?? "").foregroundColor(.secondary)
                TextField("이름", text: $name)
                TextField("소속 공동체", text: $community)
                Toggle("순장", isOn: $isLeader)
            }
            Section("자주 함께하는 순원 · 한 줄에 한 명") { TextEditor(text: $members).frame(minHeight: 120) }
            Section("데이터 보관") {
                Picker("보관 기간", selection: $retention) { ForEach([7, 30, 90, 180, 365], id: \.self) { Text("\($0)일").tag($0) } }
                Text("보관 기간을 줄이면 기존 기록과 파일이 서버에서 삭제될 수 있습니다.").font(.footnote).foregroundColor(.secondary)
            }
            Button("설정 저장") { Task { await save() } }.disabled(state.busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Section("보고서 양식") {
                Text("교회에서 받은 원본 DOCX 양식을 등록하세요. 기존 양식은 새 파일로 교체됩니다.").font(.footnote)
                Button("원본 DOCX 등록") { importingTemplate = true }
            }
            Section { Button("로그아웃") { Task { await state.logout() } }.disabled(state.busy) }
        }.navigationTitle("내 정보").onAppear { load() }
        .fileImporter(isPresented: $importingTemplate, allowedContentTypes: [UTType(filenameExtension: "docx") ?? .data]) { result in
            guard case .success(let url) = result else { return }
            Task { await state.run { guard let client = state.client else { return }; let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }; let _: TemplateUploadResponse = try await client.upload("template", file: url, mime: "application/vnd.openxmlformats-officedocument.wordprocessingml.document") } }
        }
    }
    func load() { guard let u = state.user else { return }; name = u.name; community = u.community; isLeader = u.isLeader; members = u.members.joined(separator: "\n"); retention = u.retentionDays }
    func save() async {
        await state.run {
            guard let client = state.client, var profile = state.user else { return }
            profile.name = name.trimmingCharacters(in: .whitespacesAndNewlines); profile.community = community; profile.isLeader = isLeader
            profile.members = members.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            guard retention >= profile.retentionDays else { throw APIError(message: "기존 데이터 보존을 위해 보관 기간을 줄일 수 없습니다.") }
            profile.retentionDays = retention
            state.user = try await client.send("me", method: "PUT", body: profile)
            await state.refreshMeetings()
        }
    }
}
