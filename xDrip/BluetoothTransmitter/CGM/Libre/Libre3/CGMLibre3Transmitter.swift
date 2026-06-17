import CoreBluetooth
import Foundation
import os

#if canImport(CoreNFC)
import CoreNFC

@objcMembers
class CGMLibre3Transmitter: BluetoothTransmitter, CGMTransmitter {
    // MARK: - Properties
    
    /// service to be discovered (same as Libre 2)
    private let CBUUID_Service_Libre3: String = "FDE3"
    
    /// receive characteristic
    private let CBUUID_ReceiveCharacteristic_Libre3: String = "F002"
    
    /// write characteristic
    private let CBUUID_WriteCharacteristic_Libre3: String = "F001"
    
    /// will be used to pass back bluetooth and cgm related events
    private(set) weak var cgmTransmitterDelegate: CGMTransmitterDelegate?
    
    /// CGMLibre3TransmitterDelegate
    public weak var cGMLibre3TransmitterDelegate: CGMLibre3TransmitterDelegate?
    
    /// is nonFixed enabled for the transmitter or not
    private var nonFixedSlopeEnabled: Bool
    
    /// for trace
    private let log = OSLog(subsystem: ConstantsLog.subSystem, category: ConstantsLog.categoryCGMLibre3)
    
    /// used as parameter in call to cgmTransmitterDelegate.cgmTransmitterInfoReceived, when there's no glucosedata to send
    private var emptyArray: [GlucoseData] = []
    
    /// is the transmitter oop web enabled or not
    private var webOOPEnabled: Bool
    
    /// current sensor serial number, if nil then it's not known yet
    private var sensorSerialNumber: String?
    
    /// temp storage of libreSensorSerialNumber, value will be stored after NFC scanning
    private var tempSensorSerialNumber: LibreSensorSerialNumber?
    
    /// NFC manager
    private var libreNFC: NSObject?
    
    /// sensor type
    private var libreSensorType: LibreSensorType?
    
    /// GATT manager for handling BLE communication
    private var gattManager: Libre3GattManager?
    
    /// Crypto helper for encryption/decryption
    private var cryptoHelper: Libre3CryptoHelper?
    
    /// Connection state tracking
    private var isAuthenticated: Bool = false
    
    /// Last glucose reading timestamp for backfill detection
    private var lastGlucoseTimestamp: Date?
    
    // MARK: - Initialization
    
    /// - parameters:
    ///     - address: if already connected before, then give here the address that was received during previous connect, if not give nil
    ///     - name : if already connected before, then give here the name that was received during previous connect, if not give nil
    ///     - bluetoothTransmitterDelegate : a bluetoothTransmitterDelegate
    ///     - cGMLibre3TransmitterDelegate : a CGMLibre3TransmitterDelegate
    ///     - sensorSerialNumber : optional, sensor serial number, should be set if already known from previous session
    ///     - cGMTransmitterDelegate : a CGMTransmitterDelegate
    ///     - webOOPEnabled : enabled or not, if nil then default false
    init(address: String?, name: String?, bluetoothTransmitterDelegate: BluetoothTransmitterDelegate, cGMLibre3TransmitterDelegate: CGMLibre3TransmitterDelegate, sensorSerialNumber: String?, cGMTransmitterDelegate: CGMTransmitterDelegate, nonFixedSlopeEnabled: Bool?, webOOPEnabled: Bool?) {
        // assign addressname and name or expected devicename
        var newAddressAndName = BluetoothTransmitter.DeviceAddressAndName.notYetConnected(expectedName: "ABBOTT" + (sensorSerialNumber ?? ""))
        
        if let address = address {
            newAddressAndName = BluetoothTransmitter.DeviceAddressAndName.alreadyConnectedBefore(address: address, name: "ABBOTT" + (sensorSerialNumber ?? ""))
        }
        
        // initialize sensorSerialNumber
        self.sensorSerialNumber = sensorSerialNumber
        
        // assign CGMTransmitterDelegate
        cgmTransmitterDelegate = cGMTransmitterDelegate
        
        // assign cGMLibre3TransmitterDelegate
        self.cGMLibre3TransmitterDelegate = cGMLibre3TransmitterDelegate
        
        // initialize nonFixedSlopeEnabled
        self.nonFixedSlopeEnabled = nonFixedSlopeEnabled ?? false
        
        // initialize webOOPEnabled
        self.webOOPEnabled = webOOPEnabled ?? false
        
        super.init(addressAndName: newAddressAndName, CBUUID_Advertisement: nil, servicesCBUUIDs: [CBUUID(string: CBUUID_Service_Libre3)], CBUUID_ReceiveCharacteristic: CBUUID_ReceiveCharacteristic_Libre3, CBUUID_WriteCharacteristic: CBUUID_WriteCharacteristic_Libre3, bluetoothTransmitterDelegate: bluetoothTransmitterDelegate)
        
        trace("CGMLibre3Transmitter initialized with serial: %{public}@", log: log, category: ConstantsLog.categoryCGMLibre3, type: .info, sensorSerialNumber ?? "nil")
    }
    
    // MARK: - Overridden BluetoothTransmitter functions
    
    override func startScanning() -> BluetoothTransmitter.startScanningResult {
        // overriding startScanning, because it's the time to trigger NFC Scan
        // when user clicks the scan button, an NFC read is initiated which will enable the bluetooth streaming
        // meanwhile, the real scanning can start
        
        trace("startScanning called", log: log, category: ConstantsLog.categoryCGMLibre3, type: .info)
        
        // create libreNFC instance and start session
        if NFCTagReaderSession.readingAvailable {
            // startScanning is getting called several times, but we must restrict launch of nfc scan to one single time, therefore check if libreNFC == nil
            if libreNFC == nil {
                // NFC session creation must be on main thread
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.libreNFC = LibreNFC(libreNFCDelegate: self)
                    (self.libreNFC as! LibreNFC).startSession()
                }
            }
            
        } else {
            // delegate may touch UI/Core Data → ensure main thread
            DispatchQueue.main.async { [weak self] in
                self?.bluetoothTransmitterDelegate?.error(message: TextsLibreNFC.deviceMustSupportNFC)
            }
        }
        
        // start the NFC scan (not BLE scanning)
        return .nfcScanNeeded
    }
    
    override func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        super.centralManager(central, didConnect: peripheral)
        
        trace("didConnect to peripheral", log: log, category: ConstantsLog.categoryCGMLibre3, type: .info)
        
        // Send sensor serial number to delegate if we have one from NFC scan
        if let sensorSerialNumber = tempSensorSerialNumber {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.cGMLibre3TransmitterDelegate?.received(serialNumber: sensorSerialNumber.serialNumber, from: self)
            }
            
            // set to nil so we don't send it again to the delegate when there's a new connect
            tempSensorSerialNumber = nil
            
            // Verify the connected device matches the scanned sensor
            if let deviceName = deviceName, sensorSerialNumber.serialNumber.suffix(9).uppercased() != deviceName.suffix(9) {
                DispatchQueue.main.async { [weak self] in
                    self?.bluetoothTransmitterDelegate?.error(message: TextsLibreNFC.connectedLibre2DoesNotMatchScannedLibre2)
                }
                
            } else {
                // user should be informed not to scan with the Libre app
                DispatchQueue.main.async { [weak self] in
                    self?.bluetoothTransmitterDelegate?.error(message: TextsLibreNFC.donotusethelibrelinkapp)
                }
            }
        }
        
        // Initialize GATT manager if not already done
        if gattManager == nil {
            initializeGattManager(peripheral: peripheral)
        }
    }
    
    override func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        super.centralManager(central, didDisconnectPeripheral: peripheral, error: error)
        
        trace("didDisconnect from peripheral, error: %{public}@", log: log, category: ConstantsLog.categoryCGMLibre3, type: .info, error?.localizedDescription ?? "none")
        
        // Reset authentication state
        isAuthenticated = false
        
        // Clean up GATT manager
        gattManager = nil
    }
    
    override func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        super.peripheral(peripheral, didDiscoverServices: error)
        
        trace("didDiscoverServices, error: %{public}@", log: log, category: ConstantsLog.categoryCGMLibre3, type: .info, error?.localizedDescription ?? "none")
        
        // Let GATT manager handle service discovery
        gattManager?.didDiscoverServices(error: error)
    }
    
    override func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        super.peripheral(peripheral, didDiscoverCharacteristicsFor: service, error: error)
        
        trace("didDiscoverCharacteristicsFor service: %{public}@", log: log, category: ConstantsLog.categoryCGMLibre3, type: .info, service.uuid.uuidString)
        
        // Let GATT manager handle characteristic discovery
        gattManager?.didDiscoverCharacteristics(for: service, error: error)
    }
    
    override func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        super.peripheral(peripheral, didUpdateNotificationStateFor: characteristic, error: error)
        
        trace("didUpdateNotificationStateFor characteristic: %{public}@, isNotifying: %{public}@", log: log, category: ConstantsLog.categoryCGMLibre3, type: .info, characteristic.uuid.uuidString, characteristic.isNotifying.description)
        
        // Let GATT manager handle notification state changes
        gattManager?.didUpdateNotificationState(for: characteristic, error: error)
    }
    
    override func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        super.peripheral(peripheral, didUpdateValueFor: characteristic, error: error)
        
        guard error == nil else {
            trace("didUpdateValueFor characteristic error: %{public}@", log: log, category: ConstantsLog.categoryCGMLibre3, type: .error, error!.localizedDescription)
            return
        }
        
        guard let value = characteristic.value else {
            trace("didUpdateValueFor characteristic has nil value", log: log, category: ConstantsLog.categoryCGMLibre3, type: .error)
            return
        }
        
        trace("didUpdateValueFor characteristic: %{public}@, value length: %{public}@", log: log, category: ConstantsLog.categoryCGMLibre3, type: .debug, characteristic.uuid.uuidString, value.count.description)
        
        // Let GATT manager process the value
        gattManager?.didUpdateValue(for: characteristic, value: value)
    }
    
    override func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        super.peripheral(peripheral, didWriteValueFor: characteristic, error: error)
        
        trace("didWriteValueFor characteristic: %{public}@, error: %{public}@", log: log, category: ConstantsLog.categoryCGMLibre3, type: .debug, characteristic.uuid.uuidString, error?.localizedDescription ?? "none")
        
        // Let GATT manager handle write confirmations
        gattManager?.didWriteValue(for: characteristic, error: error)
    }
    
    override func prepareForRelease() {
        // Clear base CB delegates + unsubscribe common receiveCharacteristic synchronously on main
        super.prepareForRelease()
        
        // Libre3-specific transient state cleanup
        let tearDown = {
            self.gattManager = nil
            self.cryptoHelper = nil
            self.isAuthenticated = false
            self.tempSensorSerialNumber = nil
            self.libreNFC = nil
            self.libreSensorType = nil
            self.lastGlucoseTimestamp = nil
        }
        if Thread.isMainThread {
            tearDown()
        } else {
            DispatchQueue.main.sync(execute: tearDown)
        }
    }
    
    deinit {
        // Defensive: clear transient state
        gattManager = nil
        cryptoHelper = nil
        trace("CGMLibre3Transmitter deinitialized", log: log, category: ConstantsLog.categoryCGMLibre3, type: .info)
    }
    
    // MARK: - Private Helpers
    
    private func initializeGattManager(peripheral: CBPeripheral) {
        trace("Initializing GATT manager", log: log, category: ConstantsLog.categoryCGMLibre3, type: .info)
        
        // Get sensor UID from UserDefaults
        guard let sensorUID = UserDefaults.standard.libreSensorUID else {
            trace("Cannot initialize GATT manager: sensor UID not available", log: log, category: ConstantsLog.categoryCGMLibre3, type: .error)
            return
        }
        
        // Initialize crypto helper
        cryptoHelper = Libre3CryptoHelper(sensorUID: sensorUID)
        
        guard let cryptoHelper = cryptoHelper else {
            trace("Failed to initialize crypto helper", log: log, category: ConstantsLog.categoryCGMLibre3, type: .error)
            return
        }
        
        // Initialize GATT manager
        gattManager = Libre3GattManager(
            peripheral: peripheral,
            cryptoHelper: cryptoHelper,
            sensorUID: sensorUID,
            writeCharacteristicAction: { [weak self] data, type in
                self?.writeDataToPeripheral(data: data, type: type)
            },
            glucoseDataHandler: { [weak self] glucoseData, sensorAge in
                self?.handleGlucoseData(glucoseData, sensorAge: sensorAge)
            },
            historicDataHandler: { [weak self] historicData in
                self?.handleHistoricData(historicData)
            },
            authenticationStatusHandler: { [weak self] isAuthenticated in
                self?.handleAuthenticationStatus(isAuthenticated)
            },
            sensorStatusHandler: { [weak self] lifecycleCount in
                self?.handleSensorStatus(lifecycleCount)
            }
        )
        
        trace("GATT manager initialized successfully", log: log, category: ConstantsLog.categoryCGMLibre3, type: .info)
    }
    
    private func handleGlucoseData(_ glucoseData: [GlucoseData], sensorAge: TimeInterval) {
        trace("Received glucose data: %{public}@ readings", log: log, category: ConstantsLog.categoryCGMLibre3, type: .info, glucoseData.count.description)
        
        // Update last glucose timestamp
        if let lastReading = glucoseData.first {
            lastGlucoseTimestamp = lastReading.timeStamp
        }
        
        // Forward to delegate on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            var copy = glucoseData
            self.cgmTransmitterDelegate?.cgmTransmitterInfoReceived(
                glucoseData: &copy,
                transmitterBatteryInfo: nil,
                sensorAge: sensorAge
            )
            
            // Also notify Libre3-specific delegate
            if let sensorTimeInMinutes = Int(exactly: sensorAge / 60) {
                self.cGMLibre3TransmitterDelegate?.received(sensorTimeInMinutes: sensorTimeInMinutes, from: self)
            }
        }
    }
    
    private func handleHistoricData(_ historicData: [GlucoseData]) {
        trace("Received historic data: %{public}@ readings", log: log, category: ConstantsLog.categoryCGMLibre3, type: .info, historicData.count.description)
        
        // Forward historic data to delegate on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            var copy = historicData
            self.cgmTransmitterDelegate?.cgmTransmitterInfoReceived(
                glucoseData: &copy,
                transmitterBatteryInfo: nil,
                sensorAge: nil
            )
        }
    }
    
    private func handleAuthenticationStatus(_ authenticated: Bool) {
        trace("Authentication status changed: %{public}@", log: log, category: ConstantsLog.categoryCGMLibre3, type: .info, authenticated.description)
        
        isAuthenticated = authenticated
        
        if authenticated {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                // Notify that new sensor was detected (if first time)
                if self.sensorSerialNumber == nil {
                    self.cgmTransmitterDelegate?.newSensorDetected(sensorStartDate: nil)
                }
            }
        }
    }
    
    private func handleSensorStatus(_ lifecycleCount: Int) {
        trace("Sensor status update, lifecycle count: %{public}@", log: log, category: ConstantsLog.categoryCGMLibre3, type: .info, lifecycleCount.description)
        
        // Check if sensor has expired (Libre 3 typically lasts 14 days = 20160 minutes)
        let maxSensorAge = 14 * 24 * 60 // 14 days in minutes
        if lifecycleCount >= maxSensorAge {
            DispatchQueue.main.async { [weak self] in
                self?.cgmTransmitterDelegate?.sensorStopDetected()
            }
        }
    }
    
    // MARK: - CGMTransmitter Protocol Functions
    
    func setNonFixedSlopeEnabled(enabled: Bool) {
        if nonFixedSlopeEnabled != enabled {
            nonFixedSlopeEnabled = enabled
            trace("Non-fixed slope enabled set to: %{public}@", log: log, category: ConstantsLog.categoryCGMLibre3, type: .info, enabled.description)
        }
    }
    
    func setWebOOPEnabled(enabled: Bool) {
        if webOOPEnabled != enabled {
            webOOPEnabled = enabled
            trace("WebOOP enabled set to: %{public}@", log: log, category: ConstantsLog.categoryCGMLibre3, type: .info, enabled.description)
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
        // Libre 3 sensors last 14 days
        return 14.0
    }
    
    func getCBUUID_Service() -> String {
        return CBUUID_Service_Libre3
    }
    
    func getCBUUID_Receive() -> String {
        return CBUUID_ReceiveCharacteristic_Libre3
    }
    
    // MARK: - Empty implementations for unused protocol methods
    
    func startSensor(sensorCode: String?, startDate: Date) {
        // Libre 3 doesn't support manual sensor start via BLE
        trace("startSensor called but not supported for Libre 3", log: log, category: ConstantsLog.categoryCGMLibre3, type: .info)
    }
    
    func stopSensor(stopDate: Date) {
        // Libre 3 doesn't support manual sensor stop via BLE
        trace("stopSensor called but not supported for Libre 3", log: log, category: ConstantsLog.categoryCGMLibre3, type: .info)
    }
    
    func calibrate(calibration: Calibration) {
        // Libre 3 is factory calibrated
        trace("calibrate called but not supported for Libre 3", log: log, category: ConstantsLog.categoryCGMLibre3, type: .info)
    }
    
    func needsSensorStartTime() -> Bool {
        return false
    }
    
    func needsSensorStartCode() -> Bool {
        return false
    }
    
    func requestNewReading() {
        trace("requestNewReading called", log: log, category: ConstantsLog.categoryCGMLibre3, type: .info)
        // For Libre 3, readings come automatically when connected
        // Could potentially trigger a connection if disconnected
    }
    
    func isAnubisG6() -> Bool {
        return false
    }
}

#else

@objcMembers
class CGMLibre3Transmitter: BluetoothTransmitter, CGMTransmitter {}

#endif

// MARK: - LibreNFCDelegate functions

extension CGMLibre3Transmitter: LibreNFCDelegate {
    func received(fram: Data) {
        trace("received fram: %{public}@", log: log, category: ConstantsLog.categoryCGMLibre3, type: .info, fram.toHexString())
        
        // Store FRAM data if needed for Libre 3
        // For Libre 3, we primarily need UID and patch info from NFC
    }
    
    func received(sensorUID: Data, patchInfo: Data) {
        trace("received sensorUID: %{public}@, patchInfo: %{public}@", log: log, category: ConstantsLog.categoryCGMLibre3, type: .info, sensorUID.toHexString(), patchInfo.toHexString())
        
        // Store sensorUID in UserDefaults
        UserDefaults.standard.libreSensorUID = sensorUID
        
        // Store patchInfo in UserDefaults
        UserDefaults.standard.librePatchInfo = patchInfo
        
        // Determine sensor type
        libreSensorType = LibreSensorType.type(patchInfo: patchInfo.toHexString())
        
        // Create sensor serial number
        let receivedSensorSerialNumber = LibreSensorSerialNumber(withUID: sensorUID, with: libreSensorType)
        if let receivedSensorSerialNumber = receivedSensorSerialNumber {
            tempSensorSerialNumber = receivedSensorSerialNumber
        }
        
        let receivedSensorSerialNumberAsString = receivedSensorSerialNumber?.serialNumber
        
        if let receivedSensorSerialNumberAsString = receivedSensorSerialNumberAsString {
            // Check if it's a new sensor
            if sensorSerialNumber != receivedSensorSerialNumberAsString {
                trace("new sensor detected: %{public}@", log: log, category: ConstantsLog.categoryCGMLibre3, type: .info, receivedSensorSerialNumberAsString)
                
                sensorSerialNumber = receivedSensorSerialNumberAsString
                
                // Notify delegate on main thread
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.cgmTransmitterDelegate?.newSensorDetected(sensorStartDate: nil)
                    self.cGMLibre3TransmitterDelegate?.received(serialNumber: receivedSensorSerialNumberAsString, from: self)
                }
            }
            
        } else {
            trace("could not create sensor serial number from received sensorUID", log: log, category: ConstantsLog.categoryCGMLibre3, type: .error)
        }
    }
    
    func streamingEnabled(successful: Bool) {
        trace("streaming enabled: %{public}@", log: log, category: ConstantsLog.categoryCGMLibre3, type: .info, successful.description)
        
        if successful {
            // Reset unlock count
            UserDefaults.standard.libreActiveSensorUnlockCount = 0
        }
    }
    
    func nfcScanResult(successful: Bool) {
        trace("NFC scan result: %{public}@", log: log, category: ConstantsLog.categoryCGMLibre3, type: .info, successful.description)
        
        if successful {
            if !UserDefaults.standard.nfcScanSuccessful {
                UserDefaults.standard.nfcScanSuccessful = true
            }
        } else {
            if !UserDefaults.standard.nfcScanFailed {
                UserDefaults.standard.nfcScanFailed = true
            }
        }
    }
    
    func startBLEScanning() {
        trace("Starting BLE scanning after NFC scan", log: log, category: ConstantsLog.categoryCGMLibre3, type: .info)
        _ = super.startScanning()
    }
    
    func nfcScanExpectedDevice(serialNumber: String, macAddress: String) {
        trace("Expected device - serial: %{public}@, mac: %{public}@", log: log, category: ConstantsLog.categoryCGMLibre3, type: .info, serialNumber, macAddress)
        
        // For Libre 3, update expected device name
        updateExpectedDeviceName(name: "ABBOTT" + serialNumber)
    }
}
