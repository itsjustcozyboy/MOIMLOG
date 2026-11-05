import SwiftUI

@main
struct MOIMLOGApp: App {
    var body: some Scene { WindowGroup { RootView() } }
}
struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack {
                List {
                    Section {
                        Text(Date.now, format: .dateTime.month().day().weekday())
                        Text("오늘의 이야기를 남겨요").font(.title2.bold())
                        NavigationLink("새 순모임 시작", destination: RecordingPreparation())
                    }
                    Section("최근 순모임") { Text("서버 연결 후 기록을 확인할 수 있어요") }
                }.navigationTitle("모임록")
            }.tabItem { Label("홈", systemImage: "house") }
            NavigationStack { Text("서버 연결이 필요해요").navigationTitle("기록") }
                .tabItem { Label("기록", systemImage: "folder") }
            NavigationStack { Form { Section("계정") { Text("로그인이 필요해요") }
                Section("녹음 및 개인정보") { Text("녹음 전 모든 참석자의 동의를 받아주세요.") }
            }.navigationTitle("내 정보") }.tabItem { Label("내 정보", systemImage: "person.crop.circle") }
        }.tint(.blue)
    }
}
struct RecordingPreparation: View {
    @State private var date = Date()
    @State private var consent = false
    var body: some View {
        Form {
            DatePicker("모임 날짜", selection: $date, displayedComponents: .date)
            Toggle("녹음 및 외부 음성 처리에 동의합니다", isOn: $consent)
            NavigationLink("녹음 준비하기", destination: NativeRecordingView()).disabled(!consent)
            Text("현재 녹음은 기기에만 저장되며, 보고서 작성과 연결되지 않습니다.")
        }.navigationTitle("새 순모임")
    }
}
actor APIClient {
    let baseURL: URL
    private let session: URLSession
    init(baseURL: URL) {
        self.baseURL = baseURL
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = .shared
        configuration.httpShouldSetCookies = true
        session = URLSession(configuration: configuration)
    }
    func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        let (data, response) = try await session.data(from: baseURL.appendingPathComponent(path))
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(type, from: data)
    }
}
