import Foundation
import CryptoKit

struct ATLASOfflineToken: Codable {
    let u: String   // userID
    let h: String   // hardwareUUID
    let p: String   // plan ("standard" or "pro")
    let e: Int      // expiry unix timestamp
}

enum OfflineTokenVerifier {

    // 256-bit HMAC key split into 4×8-byte segments to resist naive binary search.
    private static let s0: [UInt8] = [159, 157, 224, 176, 202,  29, 227, 110]
    private static let s1: [UInt8] = [194, 176, 104, 142, 176,  59, 142,  26]
    private static let s2: [UInt8] = [201, 211, 180, 245, 223,  26,  84, 147]
    private static let s3: [UInt8] = [240,  78, 117, 116, 223,  16, 211,  92]

    private static var verifyKey: SymmetricKey {
        SymmetricKey(data: Data(s0 + s1 + s2 + s3))
    }

    // Returns the decoded token claims if the token is valid for this machine, nil otherwise.
    static func verify(token: String) -> ATLASOfflineToken? {
        let parts = token.components(separatedBy: ".")
        guard parts.count == 2 else { return nil }
        guard let sigData     = Data(base64URLEncoded: parts[1]) else { return nil }
        guard let payloadBytes = parts[0].data(using: .utf8)      else { return nil }

        guard HMAC<SHA256>.isValidAuthenticationCode(
            sigData, authenticating: payloadBytes, using: verifyKey
        ) else { return nil }

        guard let jsonData = Data(base64URLEncoded: parts[0]),
              let claims   = try? JSONDecoder().decode(ATLASOfflineToken.self, from: jsonData)
        else { return nil }

        guard Int(Date().timeIntervalSince1970) < claims.e else { return nil }
        guard claims.h == atlasHardwareUUID()              else { return nil }

        return claims
    }
}

private extension Data {
    init?(base64URLEncoded string: String) {
        var b64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = b64.count % 4
        if padding > 0 { b64 += String(repeating: "=", count: 4 - padding) }
        self.init(base64Encoded: b64)
    }
}
