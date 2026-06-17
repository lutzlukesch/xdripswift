import Foundation

protocol CGMLibre3TransmitterDelegate: AnyObject {
    
    /// received sensor Serial Number
    func received(serialNumber: String, from cGMLibre3Transmitter: CGMLibre3Transmitter)
    
    /// received sensor time in minutes
    func received(sensorTimeInMinutes: Int, from cGMLibre3Transmitter: CGMLibre3Transmitter)
}
