import Foundation
import CryptoKit
import OSLog

// MARK: - Libre 3 Cryptography Helper

/// Handles all cryptographic operations for Libre 3 communication
class Libre3CryptoHelper {
    
    // MARK: - Properties
    
    private let log = OSLog(subsystem: ConstantsLog.subSystem, category: ConstantsLog.categoryCGMLibre3)
    
    // MARK: - Initialization
    
    init() {}
    
    /// Convenience initializer that accepts a sensor UID (reserved for future use)
    init(sensorUID: Data) {
        // sensorUID reserved for future sensor-specific operations
    }
    
    // MARK: - ECDH Key Exchange
    
    /// Generate a new ECDH key pair for P-256 curve
    /// - Returns: A new P-256 private key
    func generateECDHKeyPair() -> P256.KeyAgreement.PrivateKey {
        os_log("Generating new ECDH P-256 key pair", log: log, type: .info)
        return P256.KeyAgreement.PrivateKey()
    }
    
    /// Perform ECDH key agreement and derive session keys
    /// - Parameters:
    ///   - privateKey: Our ECDH private key
    ///   - sensorPublicKeyData: Sensor's public key as raw data (65 bytes, uncompressed format)
    ///   - sensorPin: Sensor PIN (4 bytes)
    /// - Returns: Tuple of (kEnc, ivEnc) or nil if derivation fails
    func deriveSessionKeys(privateKey: P256.KeyAgreement.PrivateKey, 
                          sensorPublicKeyData: Data, 
                          sensorPin: Data) -> (kEnc: Data, ivEnc: Data)? {
        
        guard sensorPublicKeyData.count == 65 else {
            os_log("Invalid sensor public key length: %d (expected 65)", log: log, type: .error, sensorPublicKeyData.count)
            return nil
        }
        
        guard sensorPin.count == 4 else {
            os_log("Invalid sensor PIN length: %d (expected 4)", log: log, type: .error, sensorPin.count)
            return nil
        }
        
        // Parse sensor's public key (uncompressed format: 0x04 || X || Y)
        guard let sensorPublicKey = try? P256.KeyAgreement.PublicKey(x963Representation: sensorPublicKeyData) else {
            os_log("Failed to parse sensor public key", log: log, type: .error)
            return nil
        }
        
        // Perform ECDH
        guard let sharedSecret = try? privateKey.sharedSecretFromKeyAgreement(with: sensorPublicKey) else {
            os_log("ECDH key agreement failed", log: log, type: .error)
            return nil
        }
        
        // Derive keys using HKDF with sensor PIN as salt
        let salt = sensorPin
        let info = Data("libre3".utf8)
        
        let derivedKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: salt,
            sharedInfo: info,
            outputByteCount: 32 // 16 bytes for kEnc + 12 bytes for ivEnc + 4 extra
        )
        
        // Extract kEnc (first 16 bytes) and ivEnc (next 12 bytes)
        let derivedData = derivedKey.withUnsafeBytes { Data($0) }
        let kEnc = derivedData.prefix(16)
        let ivEnc = derivedData.dropFirst(16).prefix(12)
        
        os_log("Session keys derived successfully", log: log, type: .info)
        
        return (kEnc: Data(kEnc), ivEnc: Data(ivEnc))
    }
    
    // MARK: - AES-GCM Encryption/Decryption
    
    /// Encrypt data using AES-GCM
    /// - Parameters:
    ///   - plaintext: Data to encrypt
    ///   - key: Encryption key (16 bytes)
    ///   - nonce: Initialization vector (12 bytes)
    /// - Returns: Encrypted data with tag appended, or nil on failure
    func encryptAESGCM(plaintext: Data, key: Data, nonce: Data) -> Data? {
        guard key.count == ConstantsLibre.Libre3Crypto.aesKeySize else {
            os_log("Invalid key size: %d (expected %d)", log: log, type: .error, 
                   key.count, ConstantsLibre.Libre3Crypto.aesKeySize)
            return nil
        }
        
        guard nonce.count == ConstantsLibre.Libre3Crypto.aesIVSize else {
            os_log("Invalid nonce size: %d (expected %d)", log: log, type: .error, 
                   nonce.count, ConstantsLibre.Libre3Crypto.aesIVSize)
            return nil
        }
        
        do {
            let symmetricKey = SymmetricKey(data: key)
            let gcmNonce = try AES.GCM.Nonce(data: nonce)
            
            let sealedBox = try AES.GCM.seal(plaintext, using: symmetricKey, nonce: gcmNonce)
            
            // Combine ciphertext and tag
            guard let combined = sealedBox.combined else {
                os_log("Failed to get combined ciphertext and tag", log: log, type: .error)
                return nil
            }
            
            os_log("AES-GCM encryption successful, output size: %d bytes", log: log, type: .debug, combined.count)
            return combined
            
        } catch {
            os_log("AES-GCM encryption failed: %{public}@", log: log, type: .error, error.localizedDescription)
            return nil
        }
    }
    
    /// Decrypt data using AES-GCM
    /// - Parameters:
    ///   - ciphertext: Encrypted data with tag appended
    ///   - key: Decryption key (16 bytes)
    ///   - nonce: Initialization vector (12 bytes)
    /// - Returns: Decrypted plaintext, or nil on failure
    func decryptAESGCM(ciphertext: Data, key: Data, nonce: Data) -> Data? {
        guard key.count == ConstantsLibre.Libre3Crypto.aesKeySize else {
            os_log("Invalid key size: %d (expected %d)", log: log, type: .error, 
                   key.count, ConstantsLibre.Libre3Crypto.aesKeySize)
            return nil
        }
        
        guard nonce.count == ConstantsLibre.Libre3Crypto.aesIVSize else {
            os_log("Invalid nonce size: %d (expected %d)", log: log, type: .error, 
                   nonce.count, ConstantsLibre.Libre3Crypto.aesIVSize)
            return nil
        }
        
        do {
            let symmetricKey = SymmetricKey(data: key)
            let gcmNonce = try AES.GCM.Nonce(data: nonce)
            
            let sealedBox = try AES.GCM.SealedBox(combined: ciphertext)
            let decryptedData = try AES.GCM.open(sealedBox, using: symmetricKey)
            
            os_log("AES-GCM decryption successful, plaintext size: %d bytes", log: log, type: .debug, decryptedData.count)
            return decryptedData
            
        } catch {
            os_log("AES-GCM decryption failed: %{public}@", log: log, type: .error, error.localizedDescription)
            return nil
        }
    }
    
    // MARK: - Challenge-Response Processing
    
    /// Process challenge from sensor and generate response
    /// - Parameters:
    ///   - r1: Challenge from sensor (16 bytes)
    ///   - nonce1: Nonce from sensor (7 bytes)
    ///   - sensorPin: Sensor PIN (4 bytes)
    ///   - key: Encryption key
    ///   - iv: Initialization vector
    /// - Returns: Encrypted challenge response data, or nil on failure
    func processChallengeResponse(r1: Data, nonce1: Data, sensorPin: Data, key: Data, iv: Data) -> Data? {
        guard r1.count == ConstantsLibre.Libre3Crypto.challengeSize else {
            os_log("Invalid r1 size: %d (expected %d)", log: log, type: .error, 
                   r1.count, ConstantsLibre.Libre3Crypto.challengeSize)
            return nil
        }
        
        guard nonce1.count == ConstantsLibre.Libre3Crypto.nonceSize else {
            os_log("Invalid nonce1 size: %d (expected %d)", log: log, type: .error, 
                   nonce1.count, ConstantsLibre.Libre3Crypto.nonceSize)
            return nil
        }
        
        // Generate r2 (random 16 bytes)
        var r2 = Data(count: ConstantsLibre.Libre3Crypto.challengeSize)
        let result = r2.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, ConstantsLibre.Libre3Crypto.challengeSize, bytes.baseAddress!)
        }
        
        guard result == errSecSuccess else {
            os_log("Failed to generate random r2", log: log, type: .error)
            return nil
        }
        
        // Build challenge response: r1 || r2 || sensorPin
        var responseData = Data()
        responseData.append(r1)
        responseData.append(r2)
        responseData.append(sensorPin)
        
        os_log("Challenge response constructed, size: %d bytes", log: log, type: .debug, responseData.count)
        
        // Encrypt with AES-GCM
        // Use nonce1 extended to 12 bytes (pad with zeros)
        var extendedNonce = nonce1
        extendedNonce.append(Data(count: 5)) // 7 + 5 = 12
        
        return encryptAESGCM(plaintext: responseData, key: key, nonce: extendedNonce)
    }
    
    // MARK: - Keychain Storage for kAuth
    
    /// Save kAuth to Keychain
    /// - Parameters:
    ///   - kAuth: Authentication key to store
    ///   - sensorSerial: Sensor serial number as identifier
    /// - Returns: True if successful
    func saveKAuthToKeychain(kAuth: Data, sensorSerial: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: sensorSerial,
            kSecAttrService as String: ConstantsLibre.Libre3Crypto.kAuthKeychainIdentifier,
            kSecValueData as String: kAuth
        ]
        
        // Delete any existing item
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecSuccess {
            os_log("kAuth saved to Keychain for sensor: %{public}@", log: log, type: .info, sensorSerial)
            return true
        } else {
            os_log("Failed to save kAuth to Keychain, status: %d", log: log, type: .error, status)
            return false
        }
    }
    
    /// Load kAuth from Keychain
    /// - Parameter sensorSerial: Sensor serial number as identifier
    /// - Returns: kAuth data if found, nil otherwise
    func loadKAuthFromKeychain(sensorSerial: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: sensorSerial,
            kSecAttrService as String: ConstantsLibre.Libre3Crypto.kAuthKeychainIdentifier,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess, let data = result as? Data {
            os_log("kAuth loaded from Keychain for sensor: %{public}@", log: log, type: .info, sensorSerial)
            return data
        } else if status == errSecItemNotFound {
            os_log("No kAuth found in Keychain for sensor: %{public}@", log: log, type: .info, sensorSerial)
            return nil
        } else {
            os_log("Failed to load kAuth from Keychain, status: %d", log: log, type: .error, status)
            return nil
        }
    }
    
    /// Delete kAuth from Keychain
    /// - Parameter sensorSerial: Sensor serial number as identifier
    /// - Returns: True if successful
    func deleteKAuthFromKeychain(sensorSerial: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: sensorSerial,
            kSecAttrService as String: ConstantsLibre.Libre3Crypto.kAuthKeychainIdentifier
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        if status == errSecSuccess || status == errSecItemNotFound {
            os_log("kAuth deleted from Keychain for sensor: %{public}@", log: log, type: .info, sensorSerial)
            return true
        } else {
            os_log("Failed to delete kAuth from Keychain, status: %d", log: log, type: .error, status)
            return false
        }
    }
}
