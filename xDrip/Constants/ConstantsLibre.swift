/// constants related to Libre OOP
enum ConstantsLibre {

    /// is nonFixed enabled by default yes or no
    static let defaultNonFixedSlopeEnabled = false
    
    /// is web oop enabled by default yes or no
    static let defaultWebOOPEnabled = true
    
    /// calibration parameters will be stored locally on disk, this is the path
    static let filePathForParameterStorage = "/Documents/LibreSensorParameters"
    
    /// how many times should the app repeat the NFC scan whilst trying to get a tag response and systemInfo/patchInfo
    static let retryAttemptsForLibre2NFCScans = 10
    
    // MARK: - Libre 3 Constants
    
    /// Libre 3 BLE service UUID (same as Libre 2)
    static let libre3ServiceUUID = "FDE3"
    
    /// Libre 3 BLE UUIDs
    enum Libre3BLE {
        /// Service UUID (FDE3)
        static let serviceUUID = "FDE3"
        
        /// Glucose data characteristic (main receive)
        static let glucoseDataUUID = "F005"
        
        /// Patch control characteristic (main write)
        static let patchControlUUID = "F00A"
    }
    
    /// Libre 3 GATT Characteristic UUIDs
    enum Libre3CharacteristicUUID {
        /// Command response characteristic (security)
        static let commandResponse = "F002"
        
        /// Challenge data characteristic
        static let challengeData = "F003"
        
        /// Certificate data characteristic
        static let certData = "F004"
        
        /// Glucose data characteristic
        static let glucoseData = "F005"
        
        /// Historic data characteristic
        static let historicData = "F006"
        
        /// Clinical data characteristic
        static let clinicalData = "F007"
        
        /// Factory data characteristic
        static let factoryData = "F008"
        
        /// Patch status characteristic
        static let patchStatus = "F009"
        
        /// Patch control characteristic
        static let patchControl = "F00A"
        
        /// Event log characteristic
        static let eventLog = "F00B"
    }
    
    /// Libre 3 Cryptography Constants
    enum Libre3Crypto {
        /// ECDH curve type (P-256)
        static let ecdhCurve = "P-256"
        
        /// AES-GCM key size in bytes
        static let aesKeySize = 16
        
        /// AES-GCM IV size in bytes
        static let aesIVSize = 12
        
        /// AES-GCM tag size in bytes
        static let aesTagSize = 16
        
        /// Challenge size in bytes (r1)
        static let challengeSize = 16
        
        /// Nonce size in bytes
        static let nonceSize = 7
        
        /// PIN size in bytes
        static let pinSize = 4
        
        /// Keychain identifier for storing kAuth
        static let kAuthKeychainIdentifier = "com.xdrip.libre3.kAuth"
    }
    
    /// Libre 3 LibreView API
    enum Libre3LibreView {
        /// LibreView upload endpoint
        static let uploadEndpoint = "https://api.libreview.io/llu/connections"
        
        /// LibreView auth endpoint
        static let authEndpoint = "https://api.libreview.io/llu/auth/login"
        
        /// Gateway type identifier for LibreView
        static let gatewayType = "FSLibreLink3.iOS"
        
        /// Domain identifier
        static let domain = "Libreview"
    }
    
}
