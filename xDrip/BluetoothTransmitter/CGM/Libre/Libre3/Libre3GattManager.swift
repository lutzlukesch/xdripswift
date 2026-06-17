import Foundation
import CoreBluetooth
import OSLog

/// Manages GATT operations for Libre 3 BLE communication
class Libre3GattManager {
    
    // MARK: - Properties
    
    private let log = OSLog(subsystem: ConstantsLog.subSystem, category: ConstantsLog.categoryCGMLibre3)
    
    /// Delegate for GATT events
    weak var delegate: Libre3GattManagerDelegate?
    
    /// Cryptography helper
    private let cryptoHelper: Libre3CryptoHelper
    
    /// Current cryptographic context
    private var cryptoContext: Libre3CryptoContext?
    
    /// Notification state tracker
    private var notificationState = Libre3NotificationState()
    
    /// References to discovered characteristics
    private var characteristics: [Libre3Characteristic: CBCharacteristic] = [:]
    
    /// Current security handshake phase (1-5)
    private var securityPhase: Int = 0
    
    /// Sensor information from NFC
    private var sensorInfo: Libre3SensorInfo?
    
    /// Buffer for accumulating glucose data packets
    private var glucoseDataBuffer = Data()
    
    /// Buffer for accumulating historic data packets
    private var historicDataBuffer = Data()
    
    /// Whether we're authenticated and ready to receive data
    private(set) var isAuthenticated = false
    
    // Callback-based integration (used when initialised from CGMLibre3Transmitter)
    
    /// Connected peripheral reference
    private weak var peripheral: CBPeripheral?
    
    /// Sensor UID from NFC
    private var sensorUID: Data?
    
    /// Callback to write data to peripheral characteristic
    private var writeCharacteristicAction: ((Data, CBCharacteristicWriteType) -> Void)?
    
    /// Callback invoked with current glucose readings and sensor age
    private var glucoseDataHandler: (([GlucoseData], TimeInterval) -> Void)?
    
    /// Callback invoked with historic glucose readings
    private var historicDataHandler: (([GlucoseData]) -> Void)?
    
    /// Callback invoked when authentication status changes
    private var authenticationStatusHandler: ((Bool) -> Void)?
    
    /// Callback invoked with sensor lifecycle count for expiry detection
    private var sensorStatusHandler: ((Int) -> Void)?
    
    // MARK: - Initialization
    
    init(cryptoHelper: Libre3CryptoHelper = Libre3CryptoHelper()) {
        self.cryptoHelper = cryptoHelper
    }
    
    /// Designated initializer for integration with CGMLibre3Transmitter
    init(peripheral: CBPeripheral,
         cryptoHelper: Libre3CryptoHelper,
         sensorUID: Data,
         writeCharacteristicAction: @escaping (Data, CBCharacteristicWriteType) -> Void,
         glucoseDataHandler: @escaping ([GlucoseData], TimeInterval) -> Void,
         historicDataHandler: @escaping ([GlucoseData]) -> Void,
         authenticationStatusHandler: @escaping (Bool) -> Void,
         sensorStatusHandler: @escaping (Int) -> Void) {
        self.cryptoHelper = cryptoHelper
        self.peripheral = peripheral
        self.sensorUID = sensorUID
        self.writeCharacteristicAction = writeCharacteristicAction
        self.glucoseDataHandler = glucoseDataHandler
        self.historicDataHandler = historicDataHandler
        self.authenticationStatusHandler = authenticationStatusHandler
        self.sensorStatusHandler = sensorStatusHandler
    }
    
    // MARK: - CBPeripheralDelegate Pass-through Methods
    
    /// Called when services are discovered on the peripheral
    func didDiscoverServices(error: Error?) {
        guard error == nil else {
            os_log("Error discovering services: %{public}@", log: log, type: .error,
                   error!.localizedDescription)
            return
        }
        os_log("Services discovered", log: log, type: .info)
    }
    
    /// Called when characteristics are discovered for a service
    func didDiscoverCharacteristics(for service: CBService, error: Error?) {
        guard error == nil else {
            os_log("Error discovering characteristics: %{public}@", log: log, type: .error,
                   error!.localizedDescription)
            return
        }
        
        if let discoveredCharacteristics = service.characteristics {
            for characteristic in discoveredCharacteristics {
                if let libre3Char = Libre3Characteristic(rawValue: characteristic.uuid.uuidString.uppercased()) {
                    storeCharacteristic(characteristic, type: libre3Char)
                }
            }
        }
        
        if allCharacteristicsDiscovered, let connectedPeripheral = peripheral {
            startNotificationCascade(peripheral: connectedPeripheral)
        }
    }
    
    /// Called when a characteristic's notification state changes
    func didUpdateNotificationState(for characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else {
            os_log("Error updating notification state for %{public}@: %{public}@",
                   log: log, type: .error, characteristic.uuid.uuidString,
                   error!.localizedDescription)
            return
        }
        guard let connectedPeripheral = peripheral else { return }
        handleNotificationStateUpdate(for: characteristic, peripheral: connectedPeripheral)
    }
    
    /// Called when a characteristic's value is updated (notification or read)
    func didUpdateValue(for characteristic: CBCharacteristic, value: Data) {
        handleReceivedData(value, from: characteristic)
    }
    
    /// Called when a write to a characteristic completes
    func didWriteValue(for characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            os_log("Write error for characteristic %{public}@: %{public}@",
                   log: log, type: .error, characteristic.uuid.uuidString,
                   error.localizedDescription)
        }
    }
    
    // MARK: - Public Methods
    
    /// Prepare for connection with sensor information
    /// - Parameter sensorInfo: Sensor information from NFC scan
    func prepareForConnection(with sensorInfo: Libre3SensorInfo, sensorPin: Data) {
        self.sensorInfo = sensorInfo
        
        // Load or create crypto context
        let kAuth = cryptoHelper.loadKAuthFromKeychain(sensorSerial: sensorInfo.serialNumber)
        
        if let kAuth = kAuth {
            os_log("Found existing kAuth for sensor %{public}@", log: log, type: .info, sensorInfo.serialNumber)
            cryptoContext = Libre3CryptoContext(sensorPin: sensorPin, kAuth: kAuth)
        } else {
            os_log("No existing kAuth, creating new crypto context for sensor %{public}@", 
                   log: log, type: .info, sensorInfo.serialNumber)
            cryptoContext = Libre3CryptoContext(sensorPin: sensorPin, kAuth: nil)
        }
        
        // Generate ECDH keypair
        if var context = cryptoContext {
            context.privateKey = cryptoHelper.generateECDHKeyPair()
            cryptoContext = context
        }
        
        // Reset state
        notificationState = Libre3NotificationState()
        characteristics.removeAll()
        securityPhase = 0
        isAuthenticated = false
        glucoseDataBuffer = Data()
        historicDataBuffer = Data()
    }
    
    /// Store discovered characteristic
    /// - Parameters:
    ///   - characteristic: The CBCharacteristic
    ///   - type: The Libre3Characteristic type
    func storeCharacteristic(_ characteristic: CBCharacteristic, type: Libre3Characteristic) {
        characteristics[type] = characteristic
        os_log("Stored characteristic: %{public}@", log: log, type: .info, type.rawValue)
    }
    
    /// Check if all required characteristics are discovered
    var allCharacteristicsDiscovered: Bool {
        return Libre3Characteristic.allCases.allSatisfy { characteristics[$0] != nil }
    }
    
    /// Start the notification cascade sequence
    /// - Parameter peripheral: The connected peripheral
    func startNotificationCascade(peripheral: CBPeripheral) {
        guard allCharacteristicsDiscovered else {
            os_log("Cannot start notification cascade - not all characteristics discovered", 
                   log: log, type: .error)
            return
        }
        
        os_log("Starting notification cascade", log: log, type: .info)
        enableNextNotification(peripheral: peripheral)
    }
    
    /// Handle notification state update
    /// - Parameters:
    ///   - characteristic: The characteristic that was updated
    ///   - peripheral: The connected peripheral
    func handleNotificationStateUpdate(for characteristic: CBCharacteristic, peripheral: CBPeripheral) {
        guard let libre3Char = Libre3Characteristic(rawValue: characteristic.uuid.uuidString.uppercased()) else {
            return
        }
        
        // Update notification state
        updateNotificationState(for: libre3Char, enabled: characteristic.isNotifying)
        
        os_log("Notification enabled for %{public}@", log: log, type: .info, libre3Char.rawValue)
        
        // Continue cascade or start handshake
        if notificationState.allEnabled {
            os_log("All notifications enabled, starting security handshake", log: log, type: .info)
            startSecurityHandshake(peripheral: peripheral)
        } else {
            enableNextNotification(peripheral: peripheral)
        }
    }
    
    /// Handle received data
    /// - Parameters:
    ///   - data: Received data
    ///   - characteristic: The characteristic that sent the data
    func handleReceivedData(_ data: Data, from characteristic: CBCharacteristic) {
        guard let libre3Char = Libre3Characteristic(rawValue: characteristic.uuid.uuidString.uppercased()) else {
            return
        }
        
        os_log("Received %d bytes from %{public}@", log: log, type: .debug, data.count, libre3Char.rawValue)
        
        switch libre3Char {
        case .challengeData:
            handleChallengeData(data)
            
        case .commandResponse:
            handleCommandResponse(data)
            
        case .certData:
            handleCertificateData(data)
            
        case .glucoseData:
            handleGlucoseData(data)
            
        case .historicData:
            handleHistoricData(data)
            
        case .patchStatus:
            handlePatchStatus(data)
            
        case .eventLog:
            handleEventLog(data)
            
        default:
            os_log("Received data from %{public}@ - not yet implemented", 
                   log: log, type: .info, libre3Char.rawValue)
        }
    }
    
    // MARK: - Private Methods - Notification Cascade
    
    private func enableNextNotification(peripheral: CBPeripheral) {
        // Find next characteristic to enable based on the defined order
        for charType in Libre3Characteristic.notificationOrder {
            if !isNotificationEnabled(for: charType) {
                if let characteristic = characteristics[charType] {
                    os_log("Enabling notification for %{public}@", log: log, type: .info, charType.rawValue)
                    peripheral.setNotifyValue(true, for: characteristic)
                    return
                }
            }
        }
    }
    
    private func updateNotificationState(for characteristic: Libre3Characteristic, enabled: Bool) {
        switch characteristic {
        case .patchControl: notificationState.patchControlEnabled = enabled
        case .eventLog: notificationState.eventLogEnabled = enabled
        case .historicData: notificationState.historicDataEnabled = enabled
        case .clinicalData: notificationState.clinicalDataEnabled = enabled
        case .factoryData: notificationState.factoryDataEnabled = enabled
        case .glucoseData: notificationState.glucoseDataEnabled = enabled
        case .patchStatus: notificationState.patchStatusEnabled = enabled
        case .commandResponse: notificationState.commandResponseEnabled = enabled
        case .certData: notificationState.certDataEnabled = enabled
        case .challengeData: notificationState.challengeDataEnabled = enabled
        }
    }
    
    private func isNotificationEnabled(for characteristic: Libre3Characteristic) -> Bool {
        switch characteristic {
        case .patchControl: return notificationState.patchControlEnabled
        case .eventLog: return notificationState.eventLogEnabled
        case .historicData: return notificationState.historicDataEnabled
        case .clinicalData: return notificationState.clinicalDataEnabled
        case .factoryData: return notificationState.factoryDataEnabled
        case .glucoseData: return notificationState.glucoseDataEnabled
        case .patchStatus: return notificationState.patchStatusEnabled
        case .commandResponse: return notificationState.commandResponseEnabled
        case .certData: return notificationState.certDataEnabled
        case .challengeData: return notificationState.challengeDataEnabled
        }
    }
    
    // MARK: - Private Methods - Security Handshake
    
    private func startSecurityHandshake(peripheral: CBPeripheral) {
        guard let context = cryptoContext else {
            os_log("Cannot start security handshake - no crypto context", log: log, type: .error)
            return
        }
        
        // If we have kAuth, we're a returning user - send command 17 (phase 5)
        if context.kAuth != nil {
            os_log("Returning user - sending command 17", log: log, type: .info)
            securityPhase = 5
            sendSecurityCommand(17, data: Data(), peripheral: peripheral)
        } else {
            // New user - start from phase 1
            os_log("New user - starting full handshake", log: log, type: .info)
            securityPhase = 1
            sendSecurityCommand(1, data: Data(), peripheral: peripheral)
        }
    }
    
    private func sendSecurityCommand(_ command: UInt8, data: Data, peripheral: CBPeripheral) {
        guard let commandChar = characteristics[.commandResponse] else {
            os_log("Command characteristic not found", log: log, type: .error)
            return
        }
        
        var payload = Data([command])
        payload.append(data)
        
        os_log("Sending security command %d with %d bytes data", log: log, type: .info, command, data.count)
        peripheral.writeValue(payload, for: commandChar, type: .withResponse)
    }
    
    // MARK: - Private Methods - Data Handlers
    
    private func handleChallengeData(_ data: Data) {
        os_log("Processing challenge data (%d bytes)", log: log, type: .info, data.count)
        
        // Challenge should be r1 (16 bytes) + nonce1 (7 bytes) = 23 bytes minimum
        guard data.count >= 23 else {
            os_log("Challenge data too short: %d bytes", log: log, type: .error, data.count)
            return
        }
        
        let r1 = data.prefix(16)
        let nonce1 = data.subdata(in: 16..<23)
        
        guard var context = cryptoContext,
              let kEnc = context.kEnc,
              let ivEnc = context.ivEnc else {
            os_log("Crypto context not ready for challenge processing", log: log, type: .error)
            return
        }
        
        // Process challenge-response
        if let response = cryptoHelper.processChallengeResponse(
            r1: Data(r1),
            nonce1: Data(nonce1),
            sensorPin: context.sensorPin,
            key: kEnc,
            iv: ivEnc
        ) {
            os_log("Challenge response generated successfully", log: log, type: .info)
            // Response would be sent back via command characteristic
            // TODO: Send response
        } else {
            os_log("Failed to generate challenge response", log: log, type: .error)
        }
    }
    
    private func handleCommandResponse(_ data: Data) {
        os_log("Processing command response (%d bytes) for phase %d", 
               log: log, type: .info, data.count, securityPhase)
        
        // Handle based on current phase
        // TODO: Implement phase-specific handling
    }
    
    private func handleCertificateData(_ data: Data) {
        os_log("Processing certificate data (%d bytes)", log: log, type: .info, data.count)
        
        // Certificate can be 65 bytes (ephemeral key) or 140 bytes (full certificate)
        if data.count == 65 {
            os_log("Received ephemeral public key", log: log, type: .info)
            
            // This is the sensor's ECDH public key
            guard var context = cryptoContext else { return }
            
            if let sessionKeys = cryptoHelper.deriveSessionKeys(
                privateKey: context.privateKey!,
                sensorPublicKeyData: data,
                sensorPin: context.sensorPin
            ) {
                context.kEnc = sessionKeys.kEnc
                context.ivEnc = sessionKeys.ivEnc
                cryptoContext = context
                
                os_log("Session keys derived successfully", log: log, type: .info)
            } else {
                os_log("Failed to derive session keys", log: log, type: .error)
            }
        } else if data.count == 140 {
            os_log("Received full certificate", log: log, type: .info)
            // TODO: Process full certificate
        }
    }
    
    private func handleGlucoseData(_ data: Data) {
        os_log("Processing glucose data (%d bytes)", log: log, type: .debug, data.count)
        
        // Accumulate glucose packets (typically 35 bytes)
        glucoseDataBuffer.append(data)
        
        // Check if we have a complete packet
        if glucoseDataBuffer.count >= 35 {
            decryptAndParseGlucoseData()
            glucoseDataBuffer = Data() // Reset buffer
        }
    }
    
    private func handleHistoricData(_ data: Data) {
        os_log("Processing historic data (%d bytes)", log: log, type: .debug, data.count)
        
        // Accumulate historic data
        historicDataBuffer.append(data)
        
        // Parse when we have enough data
        // TODO: Determine exact packet size for historic data
    }
    
    private func handlePatchStatus(_ data: Data) {
        os_log("Processing patch status (%d bytes)", log: log, type: .info, data.count)
        
        guard let kEnc = cryptoContext?.kEnc,
              let ivEnc = cryptoContext?.ivEnc else {
            os_log("Cannot decrypt patch status - keys not available", log: log, type: .error)
            return
        }
        
        // Decrypt patch status (type 2)
        if let decrypted = cryptoHelper.decryptAESGCM(ciphertext: data, key: kEnc, nonce: ivEnc) {
            os_log("Patch status decrypted: %d bytes", log: log, type: .info, decrypted.count)
            // TODO: Parse patch status fields
            delegate?.libre3GattManager(self, didReceivePatchStatus: parsePatchStatus(from: decrypted))
        } else {
            os_log("Failed to decrypt patch status", log: log, type: .error)
        }
    }
    
    private func handleEventLog(_ data: Data) {
        os_log("Received event log data (%d bytes)", log: log, type: .debug, data.count)
        // Event log processing - typically informational
    }
    
    // MARK: - Private Methods - Data Parsing
    
    private func decryptAndParseGlucoseData() {
        guard let kEnc = cryptoContext?.kEnc,
              let ivEnc = cryptoContext?.ivEnc else {
            os_log("Cannot decrypt glucose data - keys not available", log: log, type: .error)
            return
        }
        
        // Decrypt glucose data (type 3)
        if let decrypted = cryptoHelper.decryptAESGCM(
            ciphertext: glucoseDataBuffer,
            key: kEnc,
            nonce: ivEnc
        ) {
            os_log("Glucose data decrypted: %d bytes", log: log, type: .info, decrypted.count)
            
            // Parse glucose reading
            if let reading = parseGlucoseReading(from: decrypted) {
                delegate?.libre3GattManager(self, didReceiveGlucoseReading: reading)
            }
        } else {
            os_log("Failed to decrypt glucose data", log: log, type: .error)
        }
    }
    
    private func parseGlucoseReading(from data: Data) -> Libre3GlucoseReading? {
        // TODO: Implement actual parsing based on Juggluco data format
        // This is a placeholder implementation
        guard data.count >= 6 else { return nil }
        
        // Extract glucose value (placeholder - actual format from Juggluco)
        let rawValue = UInt16(data[0]) | (UInt16(data[1]) << 8)
        let glucose = Double(rawValue) / 10.0 // Convert to mg/dL
        
        let timestamp = Date()
        let quality: UInt8 = data[2]
        let index: UInt16 = UInt16(data[4]) | (UInt16(data[5]) << 8)
        
        return Libre3GlucoseReading(
            glucose: glucose,
            timestamp: timestamp,
            quality: quality,
            index: index
        )
    }
    
    private func parsePatchStatus(from data: Data) -> Libre3PatchStatus {
        // TODO: Implement actual parsing based on Juggluco data format
        // This is a placeholder implementation
        let sensorAge = 0 // Parse from data
        let batteryPercentage = 100 // Parse from data
        let temperature = 37.0 // Parse from data
        let statusFlags: UInt16 = 0 // Parse from data
        
        return Libre3PatchStatus(
            sensorAge: sensorAge,
            batteryPercentage: batteryPercentage,
            temperature: temperature,
            statusFlags: statusFlags
        )
    }
}

// MARK: - Libre3GattManagerDelegate Protocol

protocol Libre3GattManagerDelegate: AnyObject {
    /// Called when authentication is complete
    func libre3GattManagerDidAuthenticate(_ manager: Libre3GattManager)
    
    /// Called when a glucose reading is received
    func libre3GattManager(_ manager: Libre3GattManager, didReceiveGlucoseReading reading: Libre3GlucoseReading)
    
    /// Called when patch status is received
    func libre3GattManager(_ manager: Libre3GattManager, didReceivePatchStatus status: Libre3PatchStatus)
    
    /// Called when an error occurs
    func libre3GattManager(_ manager: Libre3GattManager, didEncounterError error: Error)
}
