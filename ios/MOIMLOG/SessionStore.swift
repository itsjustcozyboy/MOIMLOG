import Foundation
import Security

struct SavedSession: Codable {
    let token: String
    let expires: Date
}

enum SessionStore {
    private static func query(_ server: URL) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "org.moimlog.session",
            kSecAttrAccount as String: server.absoluteString
        ]
    }

    static func read(_ server: URL) throws -> SavedSession? {
        var query = query(server)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw APIError(message: "저장된 로그인을 읽을 수 없습니다. 기기 잠금을 해제한 뒤 다시 시도해 주세요.")
        }
        return try JSONDecoder().decode(SavedSession.self, from: data)
    }

    static func save(_ value: SavedSession, server: URL) throws {
        let data = try JSONEncoder().encode(value)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(query(server) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let item = query(server).merging(attributes) { _, new in new }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
                throw APIError(message: "로그인 정보를 안전하게 저장하지 못했습니다. 다시 로그인해 주세요.")
            }
        } else if status != errSecSuccess {
            throw APIError(message: "로그인 정보를 안전하게 저장하지 못했습니다.")
        }
    }

    static func delete(_ server: URL) throws {
        let status = SecItemDelete(query(server) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw APIError(message: "저장된 로그인을 삭제하지 못했습니다. 다시 시도해 주세요.")
        }
    }
}

/// API requests must never forward credentials to a redirected server or login portal.
final class APIRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct ServerConfiguration: Decodable {
    let ai: Bool
    let speech: Bool
    let maxAudioMinutes: Int
}
