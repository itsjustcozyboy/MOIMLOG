import UIKit

final class RecordingTransfers: NSObject, URLSessionTaskDelegate {
    static let shared = RecordingTransfers()
    static let identifier = "org.moimlog.recording.uploads"
    var completion: (() -> Void)?
    lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.identifier)
        config.isDiscretionary = false
        config.httpCookieStorage = .shared
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }()

    @MainActor func enqueue(file: URL, destination: URL) async throws {
        let tasks = await session.allTasks
        guard !tasks.contains(where: { $0.originalRequest?.url == destination }) else { return }
        let boundary = UUID().uuidString
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"chunk.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8)
        body.append(try Data(contentsOf: file))
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        let spool = file.deletingLastPathComponent().appendingPathComponent(boundary + ".multipart")
        try body.write(to: spool, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var request = URLRequest(url: destination)
        request.httpMethod = "PUT"
        request.setValue("1", forHTTPHeaderField: "X-Moimlog")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let cookies = HTTPCookieStorage.shared.cookies(for: destination) ?? []
        for (key, value) in HTTPCookie.requestHeaderFields(with: cookies) { request.setValue(value, forHTTPHeaderField: key) }
        let task = session.uploadTask(with: request, fromFile: spool)
        task.taskDescription = spool.path
        task.resume()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let path = task.taskDescription, path.hasSuffix(".multipart") { try? FileManager.default.removeItem(atPath: path) }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        completion?()
        completion = nil
    }
}

final class RecordingAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        guard identifier == RecordingTransfers.identifier else { completionHandler(); return }
        RecordingTransfers.shared.completion = completionHandler
        _ = RecordingTransfers.shared.session
    }
}
