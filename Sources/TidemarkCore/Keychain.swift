import CryptoKit
import Foundation

/// 기본이 아닌 config 디렉터리의 키체인 항목에는 경로 SHA-256 앞 8자리가 붙는다.
public func keychainService(for configDir: String?) -> String {
    guard let configDir = configDir else { return "Claude Code-credentials" }
    let digest = SHA256.hash(data: Data(configDir.utf8))
    let hex = digest.map { String(format: "%02x", $0) }.joined()
    return "Claude Code-credentials-" + String(hex.prefix(8))
}
