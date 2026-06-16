# FreeStyle Libre 3 Integration - Task Breakdown

**Project Goal**: Add FreeStyle Libre 3 sensor support to xDrip4iOS based on Juggluco Android implementation.

**Status**: In Progress - Phase 1  
**Target Completion**: TBD  
**Priority**: High

---

## Phase 1: Foundation & Setup

### Task 1.1: Project Structure Setup
- [x] Create directory structure: `xDrip/BluetoothTransmitter/CGM/Libre/Libre3/`
- [ ] Add new sensor type enum case: `.libre3` to `LibreSensorType`
- [x] Update `ConstantsLibre.swift` with Libre 3 constants
- [ ] Add Info.plist entries for NFC and Bluetooth permissions

**Estimated Time**: 2 hours  
**Dependencies**: None  
**Reference**: Juggluco `sensoren.hpp` line 134-146

**Commits**:
- `aed07d1` - feat(libre3): Add Libre 3 constants
- `ac6b1bd` - feat(libre3): Add Libre 3 logging category

---

### Task 1.2: Data Models
- [x] Create `Libre3Models.swift` with data structures:
  - `Libre3SensorData` (UID, serial, device address, start time)
  - `Libre3GlucoseReading` (timestamp, value, trend, record number)
  - `Libre3HistoricEntry` (timestamp, value, factory timestamp)
  - `TrendArrow` enum (rapid rise/fall, stable, etc.)
- [ ] Create CoreData entities for Libre 3 sensor storage
- [ ] Add migration logic if modifying existing schema

**Estimated Time**: 4 hours  
**Dependencies**: None  
**Reference**: Juggluco data structures in `SensorGlucoseData.hpp`

**Commits**:
- `30d27e1` - feat(libre3): Add Libre 3 data models

---

## Phase 2: NFC Support

### Task 2.1: Libre 3 NFC Detection
- [ ] Extend `LibreNFC.swift` to detect Libre 3 sensors
- [ ] Add detection logic: `uid.count == 8 && uid[6] != 7`
- [ ] Extract sensor UID and system info
- [ ] Parse sensor serial number from UID
- [ ] Add user feedback for successful/failed scans

**Estimated Time**: 6 hours  
**Dependencies**: Task 1.2  
**Reference**: Juggluco `ScanNfcV.java` lines 136-215

**Testing**:
- Scan Libre 3 sensor with NFC
- Verify correct sensor type detection
- Verify serial number extraction

---

### Task 2.2: Libre 3 NFC Manager
- [ ] Create `Libre3NFCManager.swift` class
- [ ] Implement `NFCTagReaderSessionDelegate` protocol
- [ ] Add sensor activation support (if needed)
- [ ] Handle NFC session timeouts gracefully
- [ ] Store sensor metadata for BLE connection

**Estimated Time**: 8 hours  
**Dependencies**: Task 2.1  
**Reference**: Juggluco `Libre3.libre3NFC()` in `ScanNfcV.java`

**Testing**:
- Multiple NFC scan attempts
- Error handling (timeout, user cancel, sensor not found)
- Metadata persistence

---

## Phase 3: Cryptographic Foundation

### Task 3.1: Crypto Context Setup
- [x] Create `Libre3CryptoContext.swift`
- [x] Implement ECDH key exchange using CryptoKit's P256
- [x] Generate and store private key securely (Keychain)
- [x] Export public key for sensor handshake
- [x] Implement kAuth storage and retrieval

**Estimated Time**: 10 hours  
**Dependencies**: Task 1.2  
**Reference**: Juggluco `ECDHCrypto` and `Libre3GattCallback.java` lines 587-638

**Testing**:
- Generate ECDH keypair
- Verify key storage in Keychain
- Test key retrieval for returning users

**Commits**:
- `890380f` - feat(libre3): Add cryptography helper

---

### Task 3.2: Challenge-Response Authentication
- [x] Implement challenge processing (`processChallenge`)
- [x] Receive r1 (16 bytes) + nonce1 (7 bytes) from sensor
- [x] Generate r2 (16 bytes) random value
- [x] Combine r1, r2, and sensor PIN (4 bytes)
- [x] Encrypt challenge response
- [ ] Validate sensor's response (r1, r2 verification)

**Estimated Time**: 12 hours  
**Dependencies**: Task 3.1  
**Reference**: Juggluco `Libre3GattCallback.java` lines 347-417

**Critical Notes**:
- Challenge sequence must be exact
- PIN must match sensor activation

**Testing**:
- Mock challenge data
- Verify encryption/decryption roundtrip
- Test with actual sensor challenge

**Commits**:
- `890380f` - feat(libre3): Add cryptography helper (includes challenge-response)

---

### Task 3.3: AES-GCM Encryption/Decryption
- [x] Initialize AES-GCM context with kEnc and ivEnc
- [x] Implement `encrypt(data:type:)` method
- [x] Implement `decrypt(data:type:)` method
- [ ] Handle different data types (glucose=3, historic=4, status=2, etc.)
- [x] Add error handling for decryption failures

**Estimated Time**: 8 hours  
**Dependencies**: Task 3.2  
**Reference**: Juggluco `initcrypt`, `intEncrypt`, `intDecrypt` calls

**Testing**:
- Unit tests with known plaintext/ciphertext pairs
- Test all data type codes
- Verify padding and authentication tags

**Commits**:
- `890380f` - feat(libre3): Add cryptography helper (includes AES-GCM)

---

## Phase 4: Bluetooth GATT Communication

### Task 4.1: GATT Service Discovery
- [ ] Create `Libre3GattManager.swift` class
- [ ] Define GATT service UUIDs:
  - Data Service: `FDE3`
  - Security Service: TBD (find from Juggluco)
- [ ] Define characteristic UUIDs:
  - Glucose Data
  - Historic Data
  - Patch Status
  - Patch Control
  - Event Log
  - Command Response
  - Challenge Data
  - Certificate Data
- [ ] Implement service and characteristic discovery
- [ ] Store references to all characteristics

**Estimated Time**: 8 hours  
**Dependencies**: Task 2.2, Task 3.1  
**Reference**: Juggluco `Libre3GattCallback.java` lines 992-1029

**Testing**:
- Connect to Libre 3 sensor
- Verify all services discovered
- Verify all characteristics discovered

---

### Task 4.2: Notification Cascade Implementation
- [ ] Implement notification enablement sequence (CRITICAL ORDER):
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
- [ ] Add state machine to track cascade progress
- [ ] Handle `didUpdateNotificationState` callback
- [ ] Trigger security handshake after CHALLENGE_DATA enabled

**Estimated Time**: 12 hours  
**Dependencies**: Task 4.1  
**Reference**: Juggluco `handleonDescriptorWrite` lines 718-783

**Critical Notes**:
- Order MUST be exact
- Each step waits for previous notification to be enabled
- Missing steps will cause authentication failure

**Testing**:
- Monitor notification enablement order
- Verify handshake triggers correctly
- Test reconnection with existing kAuth

---

### Task 4.3: Security Handshake Flow
- [ ] Implement security command sending
- [ ] Handle command phase state machine (phases 1-5):
  - Phase 1: Send command 1, receive certificate prompt
  - Phase 2: Send app certificate
  - Phase 3: Wait for sensor certificate
  - Phase 4: Send ephemeral keys
  - Phase 5: Complete authentication
- [ ] Process certificate data (140 bytes or 65 bytes)
- [ ] Send ephemeral keys for ECDH
- [ ] Complete kAuth generation and storage

**Estimated Time**: 16 hours  
**Dependencies**: Task 3.2, Task 4.2  
**Reference**: Juggluco `oncharwrite` lines 923-989

**Critical Notes**:
- Pre-authorized users skip to phase 5 (command 17)
- New users must complete full handshake

**Testing**:
- First-time sensor pairing
- Returning user reconnection
- Failed authentication handling

---

### Task 4.4: Glucose Data Reception
- [ ] Implement `didUpdateValue` for glucose characteristic
- [ ] Accumulate 35-byte glucose packets
- [ ] Decrypt glucose data (type 3)
- [ ] Parse glucose value and timestamp
- [ ] Extract trend arrow
- [ ] Store reading in CoreData
- [ ] Trigger UI update

**Estimated Time**: 10 hours  
**Dependencies**: Task 3.3, Task 4.2  
**Reference**: Juggluco `glucose_data` lines 1039-1058

**Testing**:
- Receive live glucose readings
- Verify values match LibreLink app
- Test trend arrow accuracy

---

### Task 4.5: Historic Data Backfill
- [ ] Implement `didUpdateValue` for historic characteristic
- [ ] Decrypt historic data (type 4)
- [ ] Parse 5-minute interval readings
- [ ] Handle backfill requests (fill gaps)
- [ ] Store historic readings in CoreData
- [ ] Avoid duplicate storage

**Estimated Time**: 10 hours  
**Dependencies**: Task 4.4  
**Reference**: Juggluco `save_history` lines 502-505

**Testing**:
- Request backfill after connection
- Verify 5-minute intervals
- Test gap detection and filling

---

### Task 4.6: Patch Status Monitoring
- [ ] Implement `didUpdateValue` for patch status characteristic
- [ ] Decrypt status data (type 2)
- [ ] Parse lifecycle count
- [ ] Determine sensor expiration
- [ ] Trigger backfill requests if needed
- [ ] Update UI with sensor status

**Estimated Time**: 8 hours  
**Dependencies**: Task 4.4  
**Reference**: Juggluco `receivedpatchstatus` lines 1155-1184

**Testing**:
- Monitor sensor lifecycle
- Test expiration warnings
- Verify backfill triggering

---

### Task 4.7: Connection Management
- [ ] Implement auto-reconnect logic
- [ ] Handle disconnections gracefully
- [ ] Implement connection retry with exponential backoff
- [ ] Add "disconnect after data" mode (for Apple Watch battery saving)
- [ ] Store connection preferences

**Estimated Time**: 8 hours  
**Dependencies**: Task 4.4  
**Reference**: Juggluco `realdisconnected` lines 646-676

**Testing**:
- Force disconnections
- Test auto-reconnect
- Monitor battery usage with different modes

---

## Phase 5: LibreView Cloud Integration

### Task 5.1: LibreView API Client
- [ ] Create `Libre3LibreViewUploader.swift`
- [ ] Implement OAuth token storage (Keychain)
- [ ] Add API endpoint constants
- [ ] Implement authentication flow
- [ ] Handle token refresh

**Estimated Time**: 6 hours  
**Dependencies**: Task 1.2  
**Reference**: Juggluco `newlibre3.cpp` lines 46-327

**Testing**:
- Obtain LibreView API credentials
- Test authentication
- Verify token storage

---

### Task 5.2: JSON Payload Builder
- [ ] Implement device settings builder
- [ ] Implement header builder (device info)
- [ ] Implement measurement log builder:
  - Current glucose entries
  - Scheduled continuous glucose entries (historic)
  - Food entries (if applicable)
  - Insulin entries (if applicable)
- [ ] Build complete payload structure
- [ ] Validate JSON schema

**Estimated Time**: 12 hours  
**Dependencies**: Task 5.1  
**Reference**: Juggluco `sendlibre3viewdata` lines 336-589

**Payload Structure**:
```json
{
  "DeviceData": {
    "deviceSettings": { ... },
    "header": { "device": { ... } },
    "measurementLog": { ... }
  },
  "UserToken": "...",
  "Domain": "Libreview",
  "GatewayType": "FSLibreLink3.iOS"
}
```

**Testing**:
- Build payload with test data
- Validate against LibreView schema
- Test with minimal and full datasets

---

### Task 5.3: Upload Implementation
- [ ] Implement `uploadGlucoseData()` method
- [ ] Add retry logic for failed uploads
- [ ] Track upload state (what's been sent)
- [ ] Handle 429 rate limiting
- [ ] Add background upload support
- [ ] Log upload success/failure

**Estimated Time**: 10 hours  
**Dependencies**: Task 5.2  
**Reference**: Juggluco `libresendmeasurements` call

**Testing**:
- Upload test data to LibreView
- Verify data appears in LibreView web/app
- Test error handling and retries

---

### Task 5.4: Upload Scheduling
- [ ] Implement background upload scheduler
- [ ] Upload on new glucose reading
- [ ] Upload historic data on connection
- [ ] Handle app backgrounding
- [ ] Add user preference for upload frequency

**Estimated Time**: 6 hours  
**Dependencies**: Task 5.3  
**Reference**: Integration logic from Juggluco

**Testing**:
- Background upload while app inactive
- Test upload frequency settings
- Monitor network usage

---

## Phase 6: UI Integration

### Task 6.1: Transmitter Selection UI
- [ ] Add "FreeStyle Libre 3" to CGM type picker
- [ ] Create Libre 3 settings screen
- [ ] Add fields:
  - Sensor serial number (read-only)
  - LibreView account ID
  - Upload preferences
  - Connection mode (continuous/disconnect after reading)
- [ ] Add "Scan Sensor" button

**Estimated Time**: 8 hours  
**Dependencies**: Task 2.2  
**Reference**: Existing Libre 2 UI

**Testing**:
- Add new Libre 3 transmitter
- Scan sensor and populate fields
- Save and retrieve settings

---

### Task 6.2: Real-time Glucose Display
- [ ] Integrate Libre 3 readings into main glucose chart
- [ ] Display trend arrow
- [ ] Show connection status indicator
- [ ] Add sensor expiration countdown
- [ ] Update watch complications

**Estimated Time**: 6 hours  
**Dependencies**: Task 4.4, Task 6.1  
**Reference**: Existing glucose display code

**Testing**:
- Verify readings display correctly
- Test chart updates in real-time
- Verify watch complications update

---

### Task 6.3: Alerts & Notifications
- [ ] Add sensor expiration alerts
- [ ] Add connection lost notifications
- [ ] Add authentication failure notifications
- [ ] Integrate with existing alert system

**Estimated Time**: 4 hours  
**Dependencies**: Task 6.2  
**Reference**: Existing alert system

**Testing**:
- Test all notification types
- Verify alert sounds and vibrations
- Test Do Not Disturb integration

---

## Phase 7: Testing & Refinement

### Task 7.1: Unit Testing
- [ ] Write tests for `Libre3CryptoContext`:
  - ECDH key generation
  - Challenge-response
  - Encryption/decryption
- [ ] Write tests for data parsing:
  - Glucose value extraction
  - Historic data parsing
  - Patch status parsing
- [ ] Write tests for LibreView payload builder
- [ ] Achieve >80% code coverage

**Estimated Time**: 16 hours  
**Dependencies**: All implementation tasks  

**Testing Framework**: XCTest

---

### Task 7.2: Integration Testing
- [ ] Test complete NFC → BLE → Data flow
- [ ] Test reconnection scenarios
- [ ] Test sensor expiration handling
- [ ] Test LibreView upload end-to-end
- [ ] Test background mode behavior
- [ ] Test with multiple sensors (sensor change)

**Estimated Time**: 20 hours  
**Dependencies**: Task 7.1  

**Test Scenarios**:
1. Fresh sensor activation
2. Returning user reconnection
3. App killed and restarted
4. Bluetooth interruptions
5. Network failures during upload

---

### Task 7.3: Field Testing
- [ ] Beta test with real users (5-10 testers)
- [ ] Monitor crash reports
- [ ] Collect battery usage data
- [ ] Gather accuracy feedback vs. LibreLink
- [ ] Fix critical bugs

**Estimated Time**: 40 hours (over 2-4 weeks)  
**Dependencies**: Task 7.2  

**Success Criteria**:
- <1% crash rate
- Glucose accuracy within ±10% of LibreLink
- Battery usage <15% per day
- Successful LibreView uploads >95%

---

### Task 7.4: Documentation
- [ ] Update README with Libre 3 support
- [ ] Create user guide for Libre 3 setup
- [ ] Document LibreView account setup
- [ ] Add troubleshooting section
- [ ] Document known limitations

**Estimated Time**: 8 hours  
**Dependencies**: Task 7.3  

---

## Phase 8: Release Preparation

### Task 8.1: Code Review & Cleanup
- [ ] Remove debug logging
- [ ] Add proper error messages
- [ ] Review memory management (no leaks)
- [ ] Optimize battery usage
- [ ] Code review with team

**Estimated Time**: 12 hours  
**Dependencies**: Task 7.4  

---

### Task 8.2: App Store Submission
- [ ] Update app version number
- [ ] Update What's New text
- [ ] Add Libre 3 screenshots
- [ ] Submit for TestFlight beta
- [ ] Address review feedback
- [ ] Submit to App Store

**Estimated Time**: 8 hours  
**Dependencies**: Task 8.1  

---

## Total Estimated Time

| Phase | Hours |
|-------|-------|
| Phase 1: Foundation | 6 |
| Phase 2: NFC Support | 14 |
| Phase 3: Cryptography | 30 |
| Phase 4: BLE Communication | 72 |
| Phase 5: LibreView | 34 |
| Phase 6: UI Integration | 18 |
| Phase 7: Testing | 84 |
| Phase 8: Release | 20 |
| **TOTAL** | **278 hours** |

**Estimated Calendar Time**: 10-14 weeks (part-time development)

---

## Dependencies & Prerequisites

### Required Hardware
- ✅ iPhone with NFC (iPhone 7 or later)
- ✅ FreeStyle Libre 3 sensor(s) for testing
- ✅ Mac with Xcode 14+ for development

### Required Accounts
- ✅ Apple Developer Account (for device testing)
- ✅ LibreView account with sensor activated
- ⚠️ LibreView API access (may require special permission from Abbott)

### Technical Prerequisites
- ✅ Understanding of CoreBluetooth
- ✅ Understanding of CoreNFC
- ✅ Understanding of CryptoKit
- ✅ Swift 5.5+ knowledge
- ⚠️ Cryptography knowledge (ECDH, AES-GCM)

---

## Risk Assessment

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| LibreView API changes | High | Medium | Monitor Juggluco updates |
| Crypto implementation errors | High | Medium | Extensive unit testing |
| iOS background limitations | Medium | High | Design for disconnections |
| Sensor firmware updates | High | Low | Monitor Abbott changes |
| App Store rejection | Medium | Low | Follow guidelines strictly |

---

## Success Criteria

- [ ] Libre 3 sensors detected via NFC scan
- [ ] Successful BLE connection and authentication
- [ ] Real-time glucose readings displayed
- [ ] Historic data backfilled on connection
- [ ] LibreView upload working
- [ ] Battery usage acceptable (<15% per day)
- [ ] No crashes in 48-hour test period
- [ ] Glucose accuracy within ±10 mg/dL of LibreLink

---

## Notes

- **Sensor PIN**: Required for authentication, stored during sensor activation
- **kAuth Storage**: Must persist between app restarts (Keychain)
- **Background Mode**: Limited on iOS, design for intermittent connections
- **Multiple Sensors**: Support sensor changes (store historical sensors)
- **Debugging**: Use BLE packet captures for troubleshooting

---

## Progress Summary

**Completed Tasks**: 4 / ~50 tasks  
**Current Phase**: Phase 1 - Foundation & Setup  
**Next Task**: NFC Detection (Task 2.1)  

**Recent Commits**:
- `aed07d1` - Add Libre 3 constants
- `ac6b1bd` - Add Libre 3 logging category
- `30d27e1` - Add Libre 3 data models
- `890380f` - Add cryptography helper

---

**Document Version**: 1.1  
**Last Updated**: 2026-06-16  
**Maintained By**: @lutzlukesch
