import CoreBluetooth
import Foundation
import os

#if canImport(CoreNFC)
import CoreNFC

@objcMembers
class CGMLibre3Transmitter: BluetoothTransmitter, CGMTransmitter {
    
    // MARK: - Properties
    
    /// Service to be discovered
    private let CBUUID_Service_Libre3: String = ConstantsLibre.Libre3BLE.serviceUUID
    
    /// Receive characteristic (glucose data)
    private let CBUUID_ReceiveCharacteristic_Libre3: String = ConstantsLibre.Libre3BLE.glucoseDataUUID
    
    /// Write characteristic (patch control)
    private let CBUUID_WriteCharacteristic_Libre3: String = ConstantsLibre.Libre3BLE.patchControlUUID
    
    /// Will be used to pass back bluetooth and cgm related events
    private(set) weak var cgmTransmitterDelegate: CGMTransmitterDelegate?
    
    /// CGMLibre3TransmitterDelegate
    public weak var cGMLibre3TransmitterDelegate: CGMLibre3TransmitterDelegate?
    
    /// For trace
    private let log = OSLog(subsystem: ConstantsLog.subSystem, category: ConstantsLog.categoryCGMLibre3)
    
    /// Used as parameter in call to cgmTransmitterDelegate.cgmTransmitterInfoReceived, when there's no glucosedata to send
    private var emptyArray: [GlucoseData] = []
    
    /// Current sensor serial number, if nil then it's not known yet
    private var sensorSerialNumber: String?
    
    /// Sensor information from NFC scan
    private var sensorInfo: Libre3SensorInfo?
    
    /// Sensor PIN (4 bytes) from NFC scan or user input
    private var sensorPin: Data?
    
    /// NFC manager for Libre 3 sensor scanning
    private var libre3NFC: Libre3NFCManager?
    
    /// GATT manager for BLE communication
    private var gattManager: Libre3GattManager?
    
    /// Is web OOP enabled or not
    private var webOOPEnabled: Bool
    
    /// Is non-fixed slope enabled or not
    private var nonFixedSlopeEnabled: Bool
    
    /// Timestamp of last glucose reading
    private var lastGlucoseReadingTimestamp: Date?
    
    /// Connection state tracking
    private var isFullyAuthenticated = false
    
    // MARK: - Initialization
    
    /// - parameters:
    ///     - address: if already connected before, then give here the address that was received during previous connect, if not give nil
    ///     - name : if already connected before, then give here the name that was received during previous connect, if not give nil
    ///     - bluetoothTransmitterDelegate : a BluetoothTransmitterDelegate
    ///     - cGMLibre3TransmitterDelegate : a CGMLibre3TransmitterDelegate
    ///     - sensorSerialNumber : optional, sensor serial number, should be set if already known from previous session
    ///     - cGMTransmitterDelegate : a CGMTransmitterDelegate
    ///     - webOOPEnabled : enabled or not, if nil then default value from constants
    ///     - nonFixedSlopeEnabled : enabled or not, if nil then default value from constants
    init(address: String?, name: String?, bluetoothTransmitterDelegate: BluetoothTransmitterDelegate, cGMLibre3TransmitterDelegate: CGMLibre3TransmitterDelegate, sensorSerialNumber: String?, cGMTransmitterDelegate: CGMTransmitterDelegate, nonFixedSlopeEnabled: Bool?, webOOPEnabled: Bool?) {
        
        // Assign address and name or expected device name
        var newAddressAndName = BluetoothTransmitter.DeviceAddressAndName.notYetConnected(expectedName: "ABBOTT" + (sensorSerialNumber ?? ""))
        
        if let address = address {
            newAddressAndName = BluetoothTransmitter.DeviceAddressAndName.alreadyConnectedBefore(address: address, name: name ?? "ABBOTT" + (sensorSerialNumber ?? ""))
        }
        
        // Initialize sensorSerialNumber
        self.sensorSerialNumber = sensorSerialNumber
        
        // Assign CGMTransmitterDelegate
        self.cgmTransmitterDelegate = cGMTransmitterDelegate
        
        // Assign cGMLibre3TransmitterDelegate
        self.cGMLibre3TransmitterDelegate = cGMLibre3TransmitterDelegate
        
        // Initialize nonFixedSlopeEnabled
        self.nonFixedSlopeEnabled = nonFixedSlopeEnabled ?? ConstantsLibre.defaultNonFixedSlopeEnabled
        
        // Initialize webOOPEnabled
        self.webOOPEnabled = webOOPEnabled ?? ConstantsLibre.defaultWebOOPEnabled
        
        // Initialize GATT manager
        self.gattManager = Libre3GattManager()
        
        super.init(addressAndName: newAddressAndName, CBUUID_Advertisement: nil, servicesCBUUIDs: [CBUUID(string: CBUUID_Service_Libre3)], CBUUID_ReceiveCharacteristic: CBUUID_ReceiveCharacteristic_Libre3, CBUUID_WriteCharacteristic: CBUUID_WriteCharacteristic_Libre3, bluetoothTransmitterDelegate: bluetoothTransmitterDelegate)
        
        // Set GATT manager delegate
        self.gattManager?.delegate = self
    }
    
    // MARK: - Overridden BluetoothTransmitter Functions
    
    override func startScanning() -> BluetoothTransmitter.startScanningResult {
        // Override startScanning to trigger NFC scan first
        // Libre 3 requires NFC scan to get sensor UID and initialize crypto
        
        os_log("Starting Libre 3 scanning - NFC required", log: log, type: .info)
        
        // Check NFC availability
        guard NFCTagReaderSession.readingAvailable else {
            os_log("NFC not available on this device", log: log, type: .error)
            
            DispatchQueue.main.async { [weak self] in
                self?.bluetoothTransmitterDelegate?.error(message: TextsLibreNFC.deviceMustSupportNFC)
            }
            
            return .nfcScanNeeded
        }
        
        // Create NFC manager if needed
        if libre3NFC == nil {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.libre3NFC = Libre3NFCManager(delegate: self)
                self.libre3NFC?.startScanning()
            }
        }
        
        return .nfcScanNeeded
    }
    
    override func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        super.centralManager(central, didConnect: peripheral)
        
        os_log("Connected to Libre 3 peripheral", log: log, type: .info)
        
        // Inform delegate of connection
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if let sensorSerialNumber = self.sensorSerialNumber {
                self.cGMLibre3TransmitterDelegate?.received(serialNumber: sensorSerialNumber, from: self)
            }
        }
    }
    
    override func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        super.peripheral(peripheral, didDiscoverCharacteristicsFor: service, error: error)
        
        os_log("Discovered characteristics for Libre 3 service", log: log, type: .info)
        
        // Store all Libre 3 characteristics in GATT manager
        if let characteristics = service.characteristics {
            for characteristic in characteristics {
                if let libre3Char = Libre3Characteristic(rawValue: characteristic.uuid.uuidString.uppercased()) {
                    gattManager?.storeCharacteristic(characteristic, type: libre3Char)
                    os_log("Stored characteristic: %{public}@", log: log, type: .debug, libre3Char.rawValue)
                }
            }
            
            // Start notification cascade if all characteristics discovered
            if gattManager?.allCharacteristicsDiscovered == true {
                os_log("All Libre 3 characteristics discovered, starting notification cascade", log: log, type: .info)
                gattManager?.startNotificationCascade(peripheral: peripheral)
            }
        }
    }
    
    override func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        super.peripheral(peripheral, didUpdateNotificationStateFor: characteristic, error: error)
        
        if let error = error {
            os_log("Error updating notification state: %{public}@", log: log, type: .error, error.localizedDescription)
            return
        }
        
        // Pass to GATT manager to handle notification cascade
        gattManager?.handleNotificationStateUpdate(for: characteristic, peripheral: peripheral)
    }
    
    override func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        super.peripheral(peripheral, didUpdateValueFor: characteristic, error: error)
        
        if let error = error {
            os_log("Error receiving characteristic value: %{public}@", log: log, type: .error, error.localizedDescription)
            return
        }
        
        guard let value = characteristic.value else {
            os_log("Received nil value from characteristic", log: log, type: .error)
            return
        }
        
        // Pass received data to GATT manager for processing
        gattManager?.handleReceivedData(value, from: characteristic)
    }
    
    override func prepareForRelease() {
        super.prepareForRelease()
        
        let tearDown = {
            self.gattManager = nil
            self.libre3NFC = nil
            self.sensorInfo = nil
            self.sensorPin = nil
            self.isFullyAuthenticated = false
        }
        
        if Thread.isMainThread {
            tearDown()
        } else {
            DispatchQueue.main.sync(execute: tearDown)
        }
    }
    
    deinit {
        gattManager = nil
        libre3NFC = nil
    }
    
    // MARK: - CGMTransmitter Protocol Functions
    
    func setNonFixedSlopeEnabled(enabled: Bool) {
        if nonFixedSlopeEnabled != enabled {
            nonFixedSlopeEnabled = enabled
            os_log("Non-fixed slope enabled changed to: %{public}@", log: log, type: .info, enabled.description)
        }
    }
    
    func setWebOOPEnabled(enabled: Bool) {
        if webOOPEnabled != enabled {
            webOOPEnabled = enabled
            os_log("Web OOP enabled changed to: %{public}@", log: log, type: .info, enabled.description)
        }
    }
    
    func cgmTransmitterType() -> CGMTransmitterType {
        return .Libre3
    }
    
    func isWebOOPEnabled() -> Bool {
        return webOOPEnabled
    }
    
    func isNonFixedSlopeEnabled() -> Bool {
        return nonFixedSlopeEnabled
    }
    
    func maxSensorAgeInDays() -> Double? {
        return 14.0 // Libre 3 sensors last 14 days
    }
    
    func getCBUUID_Service() -> String {
        return CBUUID_Service_Libre3
    }
    
    func getCBUUID_Receive() -> String {
        return CBUUID_ReceiveCharacteristic_Libre3
    }
}

// MARK: - Libre3NFCDelegate

extension CGMLibre3Transmitter: Libre3NFCDelegate {
    
    func libre3NFCDidComplete(with sensorInfo: Libre3SensorInfo) {
        os_log("NFC scan completed successfully for sensor: %{public}@", log: log, type: .info, sensorInfo.serialNumber)
        
        self.sensorInfo = sensorInfo
        self.sensorSerialNumber = sensorInfo.serialNumber
        
        // Update expected device name for BLE scanning
        updateExpectedDeviceName(name: "ABBOTT" + sensorInfo.serialNumber)
        
        // TODO: Get sensor PIN - either from NFC data, user input, or stored value
        // For now, using placeholder
        self.sensorPin = Data([0x00, 0x00, 0x00, 0x00])
        
        // Prepare GATT manager with sensor info
        if let sensorPin = self.sensorPin {
            gattManager?.prepareForConnection(with: sensorInfo, sensorPin: sensorPin)
        }
        
        // Inform delegate
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.cGMLibre3TransmitterDelegate?.received(serialNumber: sensorInfo.serialNumber, from: self)
            self.cGMLibre3TransmitterDelegate?.nfcScanComplete(for: self)
        }
        
        // Start BLE scanning
        os_log("Starting BLE scanning for Libre 3", log: log, type: .info)
        _ = super.startScanning()
    }
    
    func libre3NFCDidFail(with error: Libre3NFCError) {
        os_log("NFC scan failed: %{public}@", log: log, type: .error, error.localizedDescription)
        
        DispatchQueue.main.async { [weak self] in
            self?.bluetoothTransmitterDelegate?.error(message: error.localizedDescription)
        }
    }
}

// MARK: - Libre3GattManagerDelegate

extension CGMLibre3Transmitter: Libre3GattManagerDelegate {
    
    func libre3GattManagerDidAuthenticate(_ manager: Libre3GattManager) {
        os_log("Libre 3 authentication completed successfully", log: log, type: .info)
        
        isFullyAuthenticated = true
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.cGMLibre3TransmitterDelegate?.authenticationComplete(for: self)
        }
    }
    
    func libre3GattManager(_ manager: Libre3GattManager, didReceiveGlucoseReading reading: Libre3GlucoseReading) {
        os_log("Received glucose reading: %.1f mg/dL at %{public}@", 
               log: log, type: .info, reading.glucose, reading.timestamp.description)
        
        lastGlucoseReadingTimestamp = reading.timestamp
        
        // Convert to GlucoseData format
        let glucoseData = GlucoseData(
            timeStamp: reading.timestamp,
            glucoseLevelRaw: reading.glucose
        )
        
        // Deliver to delegate on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            var glucoseArray = [glucoseData]
            
            self.cgmTransmitterDelegate?.cgmTransmitterInfoReceived(
                glucoseData: &glucoseArray,
                transmitterBatteryInfo: nil,
                sensorAge: self.calculateSensorAge()
            )
            
            self.cGMLibre3TransmitterDelegate?.received(glucoseReading: reading, from: self)
        }
    }
    
    func libre3GattManager(_ manager: Libre3GattManager, didReceivePatchStatus status: Libre3PatchStatus) {
        os_log("Received patch status - Age: %d min, Battery: %d%%", 
               log: log, type: .info, status.sensorAge, status.batteryPercentage)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.cGMLibre3TransmitterDelegate?.received(patchStatus: status, from: self)
        }
    }
    
    func libre3GattManager(_ manager: Libre3GattManager, didEncounterError error: Error) {
        os_log("GATT manager error: %{public}@", log: log, type: .error, error.localizedDescription)
        
        DispatchQueue.main.async { [weak self] in
            self?.bluetoothTransmitterDelegate?.error(message: error.localizedDescription)
        }
    }
    
    // MARK: - Helper Methods
    
    private func calculateSensorAge() -> TimeInterval? {
        guard let sensorInfo = sensorInfo,
              let activationTime = sensorInfo.activationTime else {
            return nil
        }
        
        return Date().timeIntervalSince(activationTime)
    }
}

// MARK: - CGMLibre3TransmitterDelegate Protocol

/// Delegate protocol for Libre 3 specific events
protocol CGMLibre3TransmitterDelegate: AnyObject {
    
    /// Called when sensor serial number is received
    func received(serialNumber: String, from transmitter: CGMLibre3Transmitter)
    
    /// Called when NFC scan completes successfully
    func nfcScanComplete(for transmitter: CGMLibre3Transmitter)
    
    /// Called when authentication completes
    func authenticationComplete(for transmitter: CGMLibre3Transmitter)
    
    /// Called when a glucose reading is received
    func received(glucoseReading: Libre3GlucoseReading, from transmitter: CGMLibre3Transmitter)
    
    /// Called when patch status is received
    func received(patchStatus: Libre3PatchStatus, from transmitter: CGMLibre3Transmitter)
}

#else

// Fallback for platforms without NFC support
@objcMembers
class CGMLibre3Transmitter: BluetoothTransmitter, CGMTransmitter {
    
    func setNonFixedSlopeEnabled(enabled: Bool) {}
    func setWebOOPEnabled(enabled: Bool) {}
    func cgmTransmitterType() -> CGMTransmitterType { return .Libre3 }
    func isWebOOPEnabled() -> Bool { return false }
    func isNonFixedSlopeEnabled() -> Bool { return false }
    func maxSensorAgeInDays() -> Double? { return 14.0 }
    func getCBUUID_Service() -> String { return "" }
    func getCBUUID_Receive() -> String { return "" }
}

protocol CGMLibre3TransmitterDelegate: AnyObject {}

#endif
