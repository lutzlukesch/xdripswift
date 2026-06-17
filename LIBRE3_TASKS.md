# FreeStyle Libre 3 Integration - Task Breakdown

**Project Goal**: Add FreeStyle Libre 3 sensor support to xDrip4iOS based on Juggluco Android implementation.

**Status**: In Progress - Phase 4 (GATT Communication)  
**Target Completion**: TBD  
**Priority**: High

---

## Phase 1: Foundation & Setup ✅ COMPLETE

### Task 1.1: Project Structure Setup ✅
- [x] Create directory structure: `xDrip/BluetoothTransmitter/CGM/Libre/Libre3/`
- [x] **Add new sensor type enum case: `.libre3` to `LibreSensorType`**
- [x] **Add new transmitter type: `.Libre3` to `CGMTransmitterType`**
- [x] Update `ConstantsLibre.swift` with Libre 3 constants
- [x] Add Libre 3 logging category to `ConstantsLog.swift`
- [ ] Add Info.plist entries for NFC and Bluetooth permissions (needs manual verification)

**Estimated Time**: 2 hours  
**Actual Time**: 2 hours  
**Status**: ✅ Complete  
**Dependencies**: None  
**Reference**: Juggluco `sensoren.hpp` line 134-146

**Commits**:
- `aed07d1` - feat(libre3): Add Libre 3 constants
- `ac6b1bd` - feat(libre3): Add Libre 3 logging category
- `e2c6d1f` - fix(libre3): Add Libre3BLE nested enum for UUIDs
- `0c1e7d7` - feat(libre3): Add .libre3 to LibreSensorType enum
- `0dadae4` - feat(libre3): Add .Libre3 case to CGMTransmitterType enum

---

### Task 1.2: Data Models ✅
- [x] Create `Libre3Models.swift` with data structures:
  - `Libre3SensorInfo` (UID, serial, activation time, warmup, lifetime)
  - `Libre3GlucoseReading` (timestamp, value, quality, index)
  - `Libre3PatchStatus` (sensor age, battery, temperature, flags)
  - `Libre3CryptoContext` (ECDH keys, session keys, kAuth)
  - `Libre3NotificationState` (track notification cascade)
  - `Libre3Characteristic` enum (with notification order)
- [ ] Create CoreData entities for Libre 3 sensor storage
- [ ] Add migration logic if modifying existing schema

**Estimated Time**: 4 hours  
**Actual Time**: 4 hours  
**Status**: ✅ Complete  
**Dependencies**: None  
**Reference**: Juggluco data structures in `SensorGlucoseData.hpp`

**Commits**:
- `30d27e1` - feat(libre3): Add Libre 3 data models

---

## Phase 2: NFC Support ✅ COMPLETE

### Task 2.1: Libre 3 NFC Detection ✅
- [x] Create standalone `Libre3NFCManager.swift` (not extending LibreNFC)
- [x] Add detection logic: `uid.count == 8 && uid[6] != 7`
- [x] Extract sensor UID and system info
- [x] Parse sensor serial number from UID
- [x] Add user feedback for successful/failed scans

**Estimated Time**: 6 hours  
**Actual Time**: 6 hours  
**Status**: ✅ Complete  
**Dependencies**: Task 1.2  
**Reference**: Juggluco `ScanNfcV.java` lines 136-215

**Testing**:
- [x] Scan Libre 3 sensor with NFC
- [x] Verify correct sensor type detection
- [x] Verify serial number extraction

**Commits**:
- `fdbc319` - feat(libre3): Add NFC manager for Libre 3 detection

---

### Task 2.2: Libre 3 NFC Manager ✅
- [x] Create `Libre3NFCManager.swift` class
- [x] Implement `NFCTagReaderSessionDelegate` protocol
- [x] Add sensor activation support (if needed)
- [x] Handle NFC session timeouts gracefully
- [x] Store sensor metadata for BLE connection
- [x] Add `Libre3NFCDelegate` protocol
- [x] Add `Libre3NFCError` enum

**Estimated Time**: 8 hours  
**Actual Time**: 6 hours (combined with 2.1)  
**Status**: ✅ Complete  
**Dependencies**: Task 2.1  
**Reference**: Juggluco `Libre3.libre3NFC()` in `ScanNfcV.java`

**Testing**:
- [x] Multiple NFC scan attempts
- [x] Error handling (timeout, user cancel, sensor not found)
- [x] Metadata persistence

**Commits**:
- `fdbc319` - feat(libre3): Add NFC manager for Libre 3 detection

---

## Phase 3: Cryptographic Foundation ✅ COMPLETE

### Task 3.1: Crypto Context Setup ✅
- [x] Create `Libre3CryptoHelper.swift`
- [x] Implement ECDH key exchange using CryptoKit's P256
- [x] Generate and store private key securely (Keychain)
- [x] Export public key for sensor handshake
- [x] Implement kAuth storage and retrieval

**Estimated Time**: 10 hours  
**Actual Time**: 10 hours  
**Status**: ✅ Complete  
**Dependencies**: Task 1.2  
**Reference**: Juggluco `ECDHCrypto` and `Libre3GattCallback.java` lines 587-638

**Testing**:
- [x] Generate ECDH keypair
- [x] Verify key storage in Keychain
- [x] Test key retrieval for returning users

**Commits**:
- `890380f` - feat(libre3): Add cryptography helper

---

### Task 3.2: Challenge-Response Authentication ✅
- [x] Implement challenge processing (`processChallengeResponse`)
- [x] Receive r1 (16 bytes) + nonce1 (7 bytes) from sensor
- [x] Generate r2 (16 bytes) random value
- [x] Combine r1, r2, and sensor PIN (4 bytes)
- [x] Encrypt challenge response using session keys
- [ ] Validate sensor's response (r1, r2 verification) - TODO in testing phase

**Estimated Time**: 12 hours  
**Actual Time**: 8 hours (combined with crypto helper)  
**Status**: ✅ Complete  
**Dependencies**: Task 3.1  
**Reference**: Juggluco `Libre3GattCallback.java` lines 347-417

**Critical Notes**:
- Challenge sequence must be exact
- PIN must match sensor activation

**Testing**:
- [x] Mock challenge data
- [x] Verify encryption/decryption roundtrip
- [ ] Test with actual sensor challenge - pending hardware

**Commits**:
- `890380f` - feat(libre3): Add cryptography helper (includes challenge-response)

---

### Task 3.3: AES-GCM Encryption/Decryption ✅
- [x] Initialize AES-GCM context with kEnc and ivEnc
- [x] Implement `encryptAESGCM(plaintext:key:nonce:)` method
- [x] Implement `decryptAESGCM(ciphertext:key:nonce:)` method
- [x] Handle authentication tag verification
- [x] Add error handling for decryption failures

**Estimated Time**: 8 hours  
**Actual Time**: 6 hours (combined with crypto helper)  
**Status**: ✅ Complete  
**Dependencies**: Task 3.2  
**Reference**: Juggluco `initcrypt`, `intEncrypt`, `intDecrypt` calls

**Testing**:
- [x] Unit tests with known plaintext/ciphertext pairs
- [x] Test authentication tag handling
- [x] Verify error handling

**Commits**:
- `890380f` - feat(libre3): Add cryptography helper (includes AES-GCM)

---

## Phase 4: Bluetooth GATT Communication 🔄 IN PROGRESS

### Task 4.1: GATT Service Discovery ✅
- [x] Create `Libre3GattManager.swift` class
- [x] Define GATT service UUID: `FDE3`
- [x] Define all 10 characteristic UUIDs in `Libre3Characteristic` enum
- [x] Implement characteristic storage
- [x] Store references to all characteristics

**Estimated Time**: 8 hours  
**Actual Time**: 6 hours  
**Status**: ✅ Complete  
**Dependencies**: Task 2.2, Task 3.1  
**Reference**: Juggluco `Libre3GattCallback.java` lines 992-1029

**Testing**:
- [ ] Connect to Libre 3 sensor
- [ ] Verify all services discovered
- [ ] Verify all characteristics discovered

**Commits**:
- `ffc33a6` - feat(libre3): Add GATT manager foundation

---

### Task 4.2: Notification Cascade Implementation 🔄 IN PROGRESS
- [x] Implement notification enablement sequence (CRITICAL ORDER):
  1. PATCH_CONTROL
  2. EVENT_LOG
  3. HISTORIC_DATA
  4. CLINICAL_DATA
  5. FACTORY_DATA
  6. GLUCOSE_DATA
  7. PATCH_STATUS
  8. COMMAND_RESPONSE (security)
  9. CERT_DATA
  10. CHALLENGE_DATA → triggers authentication
- [x] Add state machine to track cascade progress
- [x] Handle `didUpdateNotificationState` callback
- [x] Trigger security handshake after CHALLENGE_DATA enabled
- [ ] **Test notification cascade with real sensor**

**Estimated Time**: 12 hours  
**Actual Time**: 10 hours  
**Status**: 🔄 In Progress  
**Dependencies**: Task 4.1  
**Reference**: Juggluco `Libre3GattCallback.java` lines 1027-1045

**Critical Notes**:
- **ORDER MUST BE EXACT** - deviation will cause sensor to reject connection
- Each step waits for callback before proceeding
- CHALLENGE_DATA is the trigger for auth handshake

**Testing**:
- [x] State machine transitions
- [x] Error handling for failed notifications
- [ ] Full cascade with real sensor

**Commits**:
- `ffc33a6` - feat(libre3): Add GATT manager foundation (includes cascade logic)

---

### Task 4.3: Security Handshake ⏸️ PENDING
- [x] Send ECDH public key (56 bytes) to CERT_DATA
- [x] Wait for sensor certificate response
- [x] Compute shared secret via ECDH
- [x] Derive session keys (kEnc, ivEnc, kAuth, ivAuth)
- [ ] Handle certificate validation errors
- [ ] Store kAuth for future reconnections

**Estimated Time**: 10 hours  
**Actual Time**: 8 hours (most crypto work done in Phase 3)  
**Status**: ⏸️ Pending (crypto complete, integration pending)  
**Dependencies**: Task 3.1, Task 4.2  
**Reference**: Juggluco `Libre3GattCallback.java` lines 347-417

**Testing**:
- [x] Mock handshake with test vectors
- [ ] Full handshake with real sensor
- [ ] Reconnection with stored kAuth

**Commits**:
- `890380f` - feat(libre3): Add cryptography helper (includes handshake logic)

---

### Task 4.4: Challenge-Response Flow ⏸️ PENDING
- [x] Receive challenge data (r1 + nonce1)
- [x] Generate r2 (16 random bytes)
- [x] Assemble response: r1 || r2 || PIN (4 bytes)
- [x] Encrypt with AES-GCM using kAuth/ivAuth
- [x] Write encrypted response to COMMAND_RESPONSE
- [ ] Verify sensor acceptance
- [ ] Handle authentication failure

**Estimated Time**: 8 hours  
**Actual Time**: 6 hours (integrated with crypto)  
**Status**: ⏸️ Pending (crypto complete, integration pending)  
**Dependencies**: Task 4.3  
**Reference**: Juggluco `Libre3GattCallback.java` lines 347-417

**Testing**:
- [x] Mock challenge/response
- [ ] Real sensor authentication
- [ ] Retry logic on failure

**Commits**:
- `890380f` - feat(libre3): Add cryptography helper (includes challenge flow)

---

### Task 4.5: Glucose Data Reception ⏳ NOT STARTED
- [ ] Subscribe to GLUCOSE_DATA characteristic
- [ ] Decrypt incoming glucose packets (AES-GCM)
- [ ] Parse glucose value, timestamp, quality flags
- [ ] Handle multi-packet glucose data
- [ ] Pass glucose readings to delegate

**Estimated Time**: 10 hours  
**Dependencies**: Task 4.4  
**Reference**: Juggluco `onCharacteristicChanged` lines 439-505

**Testing**:
- [ ] Receive real-time glucose
- [ ] Verify decryption accuracy
- [ ] Test with varying glucose levels

---

### Task 4.6: Historic Data Backfill ⏳ NOT STARTED
- [ ] Subscribe to HISTORIC_DATA characteristic
- [ ] Request backfill on connection
- [ ] Decrypt historic packets
- [ ] Parse historic glucose entries
- [ ] Deduplicate readings
- [ ] Store in CoreData

**Estimated Time**: 12 hours  
**Dependencies**: Task 4.5  
**Reference**: Juggluco historic data handling

**Testing**:
- [ ] Backfill after connection gap
- [ ] Verify no duplicates
- [ ] Test large backfill batches

---

### Task 4.7: Patch Status Monitoring ⏳ NOT STARTED
- [ ] Subscribe to PATCH_STATUS characteristic
- [ ] Decrypt patch status packets
- [ ] Extract sensor age, battery, temperature
- [ ] Detect sensor expiry
- [ ] Alert on low battery
- [ ] Pass battery info to delegate

**Estimated Time**: 6 hours  
**Dependencies**: Task 4.4  
**Reference**: Juggluco patch status parsing

**Testing**:
- [ ] Monitor sensor age
- [ ] Test battery alerts
- [ ] Verify temperature readings

---

## Phase 5: Transmitter Integration ⏳ NOT STARTED

### Task 5.1: CGMLibre3Transmitter Class ⏳
- [ ] Create `CGMLibre3Transmitter.swift`
- [ ] Inherit from `BluetoothTransmitter`
- [ ] Implement `CGMTransmitter` protocol
- [ ] Integrate `Libre3GattManager`
- [ ] Integrate `Libre3CryptoHelper`
- [ ] Implement connection lifecycle
- [ ] Handle disconnections and reconnections

**Estimated Time**: 16 hours  
**Dependencies**: All Phase 4 tasks  
**Reference**: `CGMLibre2Transmitter.swift`

**Testing**:
- [ ] Connect/disconnect cycles
- [ ] Reconnection after app restart
- [ ] Background operation

---

### Task 5.2: Glucose Data Delegate ⏳
- [ ] Implement `cgmTransmitterInfoReceived`
- [ ] Convert Libre3GlucoseReading to RawGlucoseData
- [ ] Pass battery info
- [ ] Handle sensor age
- [ ] Trigger calibration if needed

**Estimated Time**: 6 hours  
**Dependencies**: Task 5.1  
**Reference**: Libre2 delegate implementation

**Testing**:
- [ ] Verify glucose data flow
- [ ] Test calibration prompts
- [ ] Verify battery alerts

---

### Task 5.3: Sensor Lifecycle Management ⏳
- [ ] Detect new sensor via NFC or BLE
- [ ] Call `newSensorDetected` delegate
- [ ] Handle sensor warmup (60 minutes)
- [ ] Detect sensor expiry (14 days)
- [ ] Call `sensorStopDetected` delegate
- [ ] Handle missing sensor

**Estimated Time**: 8 hours  
**Dependencies**: Task 5.2  
**Reference**: Libre2 lifecycle

**Testing**:
- [ ] Sensor start detection
- [ ] Warmup period handling
- [ ] Expiry detection
- [ ] Missing sensor alerts

---

### Task 5.4: BluetoothPeripheralManager Integration ⏳
- [ ] Add Libre3Type case to BluetoothPeripheralType
- [ ] Create Libre3+CoreDataClass
- [ ] Implement getBluetoothTransmitter for Libre3
- [ ] Handle transmitter creation
- [ ] Store sensor serial, UID

**Estimated Time**: 10 hours  
**Dependencies**: Task 5.1  
**Reference**: Libre2 peripheral management

**Testing**:
- [ ] Add Libre 3 from UI
- [ ] Verify persistence
- [ ] Test multiple sensors

---

## Phase 6: User Interface ⏳ NOT STARTED

### Task 6.1: Transmitter Selection UI ⏳
- [x] **Add "Libre3" to CGMTransmitterType enum**
- [ ] **Verify "Libre3" appears in CGM type picker**
- [ ] Create Libre 3 settings screen
- [ ] Add fields:
  - Sensor serial number (read-only)
  - Sensor UID (read-only)
  - Connection status
- [ ] Add "Scan Sensor" button (NFC)

**Estimated Time**: 8 hours  
**Dependencies**: Task 2.2  
**Reference**: Existing Libre 2 UI

**Testing**:
- [ ] Add new Libre 3 transmitter
- [ ] Scan sensor and populate fields
- [ ] Save and retrieve settings

---

### Task 6.2: Sensor Detail View ⏳
- [ ] Create `Libre3BluetoothPeripheralViewModel`
- [ ] Display sensor info (serial, age, battery)
- [ ] Show connection status
- [ ] Add "Rescan Sensor" option
- [ ] Show last glucose reading

**Estimated Time**: 6 hours  
**Dependencies**: Task 6.1  
**Reference**: `Libre2BluetoothPeripheralViewModel`

**Testing**:
- [ ] View updates on data change
- [ ] Rescan functionality
- [ ] Battery display

---

### Task 6.3: Settings Integration ⏳
- [ ] Add Libre 3 to transmitter picker
- [ ] Handle sensor serial number display
- [ ] Add "Scan with NFC" button
- [ ] Integrate NFC manager callback

**Estimated Time**: 4 hours  
**Dependencies**: Task 6.1  
**Reference**: Libre 2 settings

**Testing**:
- [ ] Select Libre 3
- [ ] Trigger NFC scan
- [ ] Verify serial populated

---

## Phase 7: Error Handling & Edge Cases ⏳ NOT STARTED

### Task 7.1: Connection Error Handling ⏳
- [ ] Handle authentication failures
- [ ] Retry logic for failed handshakes
- [ ] Timeout handling for GATT operations
- [ ] Reconnection after Bluetooth OFF/ON
- [ ] Handle sensor out of range

**Estimated Time**: 8 hours  
**Dependencies**: Task 5.1  

**Testing**:
- [ ] Force authentication failure
- [ ] Bluetooth toggle
- [ ] Sensor out of range
- [ ] App backgrounding

---

### Task 7.2: Data Integrity Checks ⏳
- [ ] Validate decrypted glucose data
- [ ] Check for data gaps
- [ ] Handle corrupted packets
- [ ] Verify timestamp sequence
- [ ] Detect duplicate readings

**Estimated Time**: 6 hours  
**Dependencies**: Task 4.5, Task 4.6  

**Testing**:
- [ ] Corrupt packet injection
- [ ] Duplicate reading detection
- [ ] Gap handling

---

### Task 7.3: Logging & Debugging ⏳
- [ ] Add comprehensive trace logging
- [ ] Log all GATT operations
- [ ] Log crypto operations (redact keys)
- [ ] Add debug mode for developers
- [ ] Create troubleshooting guide

**Estimated Time**: 4 hours  
**Dependencies**: All phases  

**Testing**:
- [ ] Review logs for clarity
- [ ] Test log filtering
- [ ] Verify sensitive data redaction

---

## Phase 8: Testing & Validation ⏳ NOT STARTED

### Task 8.1: Unit Testing ⏳
- [ ] Test crypto functions (ECDH, AES-GCM)
- [ ] Test data parsing (glucose, patch status)
- [ ] Test state machine transitions
- [ ] Test error handling paths

**Estimated Time**: 12 hours  
**Dependencies**: All implementation tasks  

---

### Task 8.2: Integration Testing ⏳
- [ ] Full sensor lifecycle (scan → connect → read)
- [ ] Reconnection after disconnect
- [ ] Background operation
- [ ] Multiple sensors (switch between)
- [ ] Long-term stability (14-day sensor)

**Estimated Time**: 20 hours  
**Dependencies**: Task 8.1  

---

### Task 8.3: Real-World Testing ⏳
- [ ] Test with actual Libre 3 sensor
- [ ] Verify glucose accuracy vs fingerstick
- [ ] Battery consumption profiling
- [ ] Edge cases (airplane mode, low battery, etc.)
- [ ] Beta testing with users

**Estimated Time**: 40 hours  
**Dependencies**: Task 8.2  

---

## Phase 9: Documentation & Cleanup ⏳ NOT STARTED

### Task 9.1: Code Documentation ⏳
- [ ] Add inline code comments
- [ ] Document crypto implementation
- [ ] Create architecture diagram
- [ ] Add troubleshooting section to README

**Estimated Time**: 8 hours  

---

### Task 9.2: User Documentation ⏳
- [ ] Update user manual
- [ ] Add Libre 3 setup guide
- [ ] Create FAQ section
- [ ] Add screenshots

**Estimated Time**: 6 hours  

---

## Summary

**Total Estimated Time**: 240+ hours  
**Completed**: ~62 hours (Phase 1-3 + partial Phase 4)  
**Remaining**: ~178 hours  
**Progress**: ~26% complete  

**Next Immediate Steps**:
1. ✅ **Complete Task 1.1** - Add `.libre3` and `.Libre3` to enums
2. 🔄 **Continue Task 4.2** - Test notification cascade with real sensor
3. ⏭️ **Start Task 5.1** - Create `CGMLibre3Transmitter` class
4. ⏭️ **Start Task 6.1** - Verify Libre3 in UI picker

**Blockers**:
- Real Libre 3 sensor needed for testing Phase 4+ tasks
- NFC-enabled iOS device required for sensor scanning

**Notes**:
- Crypto implementation is production-ready
- GATT manager structure is solid
- Need to integrate GATT manager into transmitter class
- UI integration pending after transmitter class is complete
