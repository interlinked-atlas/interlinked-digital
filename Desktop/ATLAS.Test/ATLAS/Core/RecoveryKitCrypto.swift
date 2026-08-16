import Foundation
import CryptoKit

// Symmetric AES-GCM-256 encryption for cloud Recovery Kit payloads.
// Envelope format: JSON { "v": 1, "nonce": base64(12 bytes), "ciphertext": base64(ciphertext + 16-byte tag) }
// The decryption key (DEK) is a 256-bit symmetric key managed by the server and cached in Keychain.

struct RecoveryKitCrypto {

    // Encrypts plaintext data with AES-GCM-256 using a random 96-bit nonce.
    // Returns JSON envelope bytes.
    static func encrypt(data: Data, key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.seal(data, using: key)
        let nonceData = Data(sealedBox.nonce)
        let ciphertextAndTag = sealedBox.ciphertext + sealedBox.tag
        let envelope: [String: Any] = [
            "v": 1,
            "nonce": nonceData.base64EncodedString(),
            "ciphertext": ciphertextAndTag.base64EncodedString()
        ]
        return try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
    }

    // Decrypts an envelope produced by encrypt(data:key:).
    // Throws if the envelope is malformed or the authentication tag fails.
    static func decrypt(envelopeData: Data, key: SymmetricKey) throws -> Data {
        guard let envelope = try? JSONSerialization.jsonObject(with: envelopeData) as? [String: Any],
              let nonceB64 = envelope["nonce"] as? String,
              let ciphertextB64 = envelope["ciphertext"] as? String,
              let nonceData = Data(base64Encoded: nonceB64),
              let ciphertextAndTag = Data(base64Encoded: ciphertextB64),
              ciphertextAndTag.count >= 16
        else { throw RecoveryKitCryptoError.malformedEnvelope }

        let nonce        = try AES.GCM.Nonce(data: nonceData)
        let tag          = ciphertextAndTag.suffix(16)
        let ciphertext   = ciphertextAndTag.dropLast(16)
        let sealedBox    = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        return try AES.GCM.open(sealedBox, using: key)
    }

    // Constructs a SymmetricKey from a base64-encoded 32-byte string (as returned by /api/atlas/recovery-kit/key).
    static func symmetricKey(from base64: String) throws -> SymmetricKey {
        guard let data = Data(base64Encoded: base64), data.count == 32 else {
            throw RecoveryKitCryptoError.invalidKeyData
        }
        return SymmetricKey(data: data)
    }
}

enum RecoveryKitCryptoError: Error, LocalizedError {
    case malformedEnvelope
    case invalidKeyData

    var errorDescription: String? {
        switch self {
        case .malformedEnvelope:
            return "The cloud Recovery Kit could not be decrypted. It may be corrupted."
        case .invalidKeyData:
            return "Invalid encryption key data received from server."
        }
    }
}
