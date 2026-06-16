import Foundation
import OSLog

#if canImport(CoreNFC)
import CoreNFC

/// Manager for handling Libre 3 NFC operations
class Libre3NFCManager: NSObject {
    
    // MARK: - Properties
    
    private let log = OSLog(subsystem: ConstantsLog.subSystem, category: ConstantsLog.categoryCGMLibre3)
    
    /// Delegate to receive NFC scan results
    weak var delegate: Libre3NFCDelegate?
    
    /// Current NFC session
    private var nfcSession: NFCTagReaderSession?
    
    /// Tracks if the current scan was successful
    private var scanSuccessful = false
    
    /// Extracted sensor information
    private var sensorInfo: Libre3SensorInfo?
    
    // MARK: - Initialization
    
    init(delegate: Libre3NFCDelegate?) {
        self.delegate = delegate
        super.init()
    }
    
    // MARK: - Public Methods
    
    /// Start an NFC scan session to detect Libre 3 sensor
    func startScanning() {
        guard NFCTagReaderSession.readingAvailable else {
            os_log("NFC is not available on this device", log: log, type: .error)
            delegate?.libre3NFCDidFail(with: .nfcNotSupported)
            return
        }
        
        scanSuccessful = false
        sensorInfo = nil
        
        nfcSession = NFCTagReaderSession(pollingOption: .iso15693, delegate: self, queue: .main)
        nfcSession?.alertMessage = TextsLibreNFC.holdTopOfIphoneNearSensor
        nfcSession?.begin()
        
        os_log("Started Libre 3 NFC scan session", log: log, type: .info)
    }
    
    /// Cancel the current NFC session
    func cancelScanning() {
        nfcSession?.invalidate()
        nfcSession = nil
        os_log("Cancelled Libre 3 NFC scan session", log: log, type: .info)
    }
    
    // MARK: - Helper Methods
    
    /// Detect if the scanned sensor is a Libre 3
    /// - Parameter uid: Sensor UID
    /// - Returns: True if Libre 3, false otherwise
    private func isLibre3Sensor(uid: Data) -> Bool {
        // Libre 3 detection: uid.length == 8 && uid[6] != 7
        let isLibre3 = uid.count == 8 && uid[6] != 7
        
        if isLibre3 {
            os_log("Detected Libre 3 sensor (UID length: %d, byte[6]: 0x%02X)", 
                   log: log, type: .info, uid.count, uid[6])
        } else {
            os_log("Not a Libre 3 sensor (UID length: %d, byte[6]: 0x%02X)", 
                   log: log, type: .info, uid.count, uid.count >= 7 ? uid[6] : 0)
        }
        
        return isLibre3
    }
    
    /// Extract serial number from sensor UID
    /// - Parameter uid: Sensor UID (8 bytes)
    /// - Returns: Serial number string
    private func extractSerialNumber(from uid: Data) -> String {
        guard uid.count == 8 else {
            os_log("Invalid UID length for serial extraction: %d", log: log, type: .error, uid.count)
            return "unknown"
        }
        
        // Libre 3 serial number extraction (similar to Libre 2)
        // Reference: Juggluco ScanNfcV.java
        let serialNumber = LibreSensorSerialNumber(withUID: uid, with: .libre3)?.serialNumber ?? "unknown"
        
        os_log("Extracted serial number: %{public}@", log: log, type: .info, serialNumber)
        return serialNumber
    }
    
    /// Parse sensor information from NFC tag
    /// - Parameters:
    ///   - uid: Sensor UID
    ///   - systemInfo: NFC system information
    /// - Returns: Libre3SensorInfo if parsing successful
    private func parseSensorInfo(uid: Data, systemInfo: NFCISO15693SystemInfo) -> Libre3SensorInfo? {
        let serialNumber = extractSerialNumber(from: uid)
        
        // For Libre 3, sensor activation and lifetime info would come from FRAM
        // For now, use default values (actual implementation would read FRAM blocks)
        let warmupDuration = 60 // 60 minutes warmup
        let lifetime = 20160 // 14 days in minutes
        
        let sensorInfo = Libre3SensorInfo(
            uid: uid,
            serialNumber: serialNumber,
            activationTime: nil, // Would be read from FRAM
            warmupDuration: warmupDuration,
            lifetime: lifetime
        )
        
        os_log("Parsed sensor info - Serial: %{public}@, UID: %{public}@", 
               log: log, type: .info, serialNumber, uid.toHexString())
        
        return sensorInfo
    }
}

// MARK: - NFCTagReaderSessionDelegate

extension Libre3NFCManager: NFCTagReaderSessionDelegate {
    
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        os_log("NFC session became active, waiting for sensor detection", log: log, type: .info)
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        if let readerError = error as? NFCReaderError {
            switch readerError.code {
            case .readerSessionInvalidationErrorSessionTimeout:
                os_log("NFC session timeout", log: log, type: .info)
                if !scanSuccessful {
                    delegate?.libre3NFCDidFail(with: .timeout)
                }
                
            case .readerSessionInvalidationErrorUserCanceled:
                os_log("User cancelled NFC scan", log: log, type: .info)
                if !scanSuccessful {
                    delegate?.libre3NFCDidFail(with: .userCancelled)
                }
                
            default:
                os_log("NFC session error: %{public}@", log: log, type: .error, readerError.localizedDescription)
                if !scanSuccessful {
                    delegate?.libre3NFCDidFail(with: .scanFailed(readerError.localizedDescription))
                }
            }
        }
        
        // If scan was successful, notify delegate with sensor info
        if scanSuccessful, let sensorInfo = sensorInfo {
            delegate?.libre3NFCDidComplete(with: sensorInfo)
        }
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        os_log("NFC tags detected", log: log, type: .info)
        
        guard let firstTag = tags.first else {
            session.invalidate(errorMessage: TextsLibreNFC.nfcErrorMessageScanFailed)
            return
        }
        
        guard case .iso15693(let tag) = firstTag else {
            os_log("Detected tag is not ISO15693", log: log, type: .error)
            session.invalidate(errorMessage: TextsLibreNFC.nfcErrorMessageScanFailed)
            return
        }
        
        Task { @MainActor in
            do {
                // Connect to tag
                os_log("Connecting to NFC tag...", log: log, type: .info)
                try await session.connect(to: firstTag)
                
                // Get system info
                os_log("Reading system info...", log: log, type: .info)
                let systemInfo = try await tag.systemInfo(requestFlags: .highDataRate)
                
                // Get UID (reversed for Libre sensors)
                let uid = Data(tag.identifier.reversed())
                os_log("Sensor UID: %{public}@", log: log, type: .info, uid.toHexString())
                
                // Check if this is a Libre 3 sensor
                guard isLibre3Sensor(uid: uid) else {
                    os_log("Scanned sensor is not Libre 3", log: log, type: .error)
                    session.invalidate(errorMessage: "This is not a Libre 3 sensor")
                    delegate?.libre3NFCDidFail(with: .notLibre3Sensor)
                    return
                }
                
                // Parse sensor information
                guard let parsedInfo = parseSensorInfo(uid: uid, systemInfo: systemInfo) else {
                    os_log("Failed to parse sensor information", log: log, type: .error)
                    session.invalidate(errorMessage: TextsLibreNFC.nfcErrorMessageScanFailed)
                    delegate?.libre3NFCDidFail(with: .parsingFailed)
                    return
                }
                
                self.sensorInfo = parsedInfo
                self.scanSuccessful = true
                
                // Play success vibration
                AudioServicesPlaySystemSound(1519)
                
                session.alertMessage = TextsLibreNFC.scanComplete
                session.invalidate()
                
                os_log("Successfully scanned Libre 3 sensor: %{public}@", 
                       log: log, type: .info, parsedInfo.serialNumber)
                
            } catch {
                os_log("NFC scan error: %{public}@", log: log, type: .error, error.localizedDescription)
                session.invalidate(errorMessage: TextsLibreNFC.nfcErrorMessageScanFailed)
                delegate?.libre3NFCDidFail(with: .scanFailed(error.localizedDescription))
            }
        }
    }
}

// MARK: - Libre3NFCDelegate Protocol

/// Delegate protocol for Libre 3 NFC scan results
protocol Libre3NFCDelegate: AnyObject {
    /// Called when NFC scan completed successfully
    func libre3NFCDidComplete(with sensorInfo: Libre3SensorInfo)
    
    /// Called when NFC scan failed
    func libre3NFCDidFail(with error: Libre3NFCError)
}

// MARK: - Libre3NFCError

/// Errors that can occur during Libre 3 NFC scanning
enum Libre3NFCError: Error {
    case nfcNotSupported
    case timeout
    case userCancelled
    case notLibre3Sensor
    case parsingFailed
    case scanFailed(String)
    
    var localizedDescription: String {
        switch self {
        case .nfcNotSupported:
            return "NFC is not supported on this device"
        case .timeout:
            return "NFC scan timed out"
        case .userCancelled:
            return "User cancelled the scan"
        case .notLibre3Sensor:
            return "The scanned sensor is not a Libre 3"
        case .parsingFailed:
            return "Failed to parse sensor information"
        case .scanFailed(let message):
            return "Scan failed: \(message)"
        }
    }
}

#endif
