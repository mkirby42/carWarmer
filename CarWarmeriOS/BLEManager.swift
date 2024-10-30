//
//  BLEManager.swift
//  CarWarmeriOS
//
//  Created by Mathew Kirby on 10/30/24.
//

import Combine
import CoreBluetooth
import Foundation
import OSLog

class SensorPeripheral: NSObject, ObservableObject {
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "SensorPeripheral")
    var peripheral: CBPeripheral
    
    init(from peripheral: CBPeripheral) {
        logger.debug("Initialization")
        self.peripheral = peripheral
        super.init()
        self.peripheral.delegate = self
    }
}

enum BLEService {
    static let sensorInformation = CBUUID(string: "0x180A")
}

enum BLECharacteristic {
    static let temperature = CBUUID(string: "0x2A6E")
    static let humidity = CBUUID(string: "0x2A6F")
    static let battery = CBUUID(string: "0x2A19")
}

extension SensorPeripheral: CBPeripheralDelegate {
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else {
            return
        }
        
        switch characteristic.uuid {
        case BLECharacteristic.temperature:
            print("temperature \(data)")
        case BLECharacteristic.humidity:
            print("humidity \(data)")
        case BLECharacteristic.battery:
            print("battery \(data)")
        default:
            break
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else {
            return
        }
        
        for service in services {
            switch service.uuid {
            case BLEService.sensorInformation:
                peripheral.discoverCharacteristics(nil, for: service)
            default:
                logger.warning("Unhandled Service: \(service)")
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            logger.error("\(#function) \(error)")
            return
        }
        
        guard let characteristics = service.characteristics else {
            return
        }
        
        switch service.uuid {
        case BLEService.sensorInformation:
            for characteristic in characteristics {
                switch characteristic.uuid {
                case BLECharacteristic.temperature:
                    peripheral.setNotifyValue(true, for: characteristic)
                case BLECharacteristic.humidity:
                    peripheral.setNotifyValue(true, for: characteristic)
                case BLECharacteristic.battery:
                    peripheral.setNotifyValue(true, for: characteristic)
                default:
                    logger.warning("Unhandled lightLace Characteristic \(characteristic)")
                }
                
                peripheral.readValue(for: characteristic)
            }
        default:
            break
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        if let error = error {
            logger.error("Error reading RSSI: \(error.localizedDescription)")
            return
        }
        print("RSSI \(RSSI.intValue)")
    }
}

extension Notification.Name {
    static let manualBluetoothManagerStateChange = Notification.Name("manualBluetoothManagerStateChange")
}

final class BLEManager: NSObject, ObservableObject {
    
    @Published var sensors: [UUID: SensorPeripheral] = [:]
    @Published var isScanning = false
    static let shared = BLEManager()
    private var centralManager: CBCentralManager!
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "BLEManager")
    var manualUpdateCancellable: Cancellable?

    override private init() {
        super.init()
        logger.debug("BLEManager initialized")
        centralManager = CBCentralManager(delegate: self, queue: .main)
        logger.debug("CBCentralManager manager initialized")
        
        manualUpdateCancellable = NotificationCenter.default
            .publisher(for: .manualBluetoothManagerStateChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.objectWillChange.send()
            }
    }
    
    func startScanningFor(_ duration: Double?) {
        logger.debug("Attempting to begin scanning for \(duration ?? Double.infinity) seconds")
        guard centralManager.state == .poweredOn else {
            logger.error("Error Bluetooth manager not powered on.")
            return
        }
        logger.debug("Scanning")
        centralManager.scanForPeripherals(withServices: nil)
        isScanning = centralManager.isScanning
        
        guard let duration = duration else {
            // Indefinite scan
            return
        }
        
        // Stop scanning after duration
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self else { return }
            stopScanning()
        }
    }
    
    func stopScanning() {
        logger.debug("End scanning")
        self.centralManager.stopScan()
        self.isScanning = self.centralManager.isScanning
    }
}

extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        logger.debug("Central manager did update state: \(central.state)")
        if central.state == .poweredOn {
            startScanningFor(3)
        }
    }
    
    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        let advertisingName = advertisementData["kCBAdvDataLocalName"] as? String ?? ""
        logger.info("Discovered peripheral. Advertising name: \(advertisingName). Peripheral name: \(peripheral.name ?? ""). ID: \(peripheral.identifier)")
        
        guard advertisingName == "Nano33BLE_Sensor" else {
            return
        }
        
        // The discovered peripheral may already be in the dictionary
        // if so, update it, if not, make a new one
        if let existing = sensors[peripheral.identifier] {
            logger.info("Accessing existing peripheral")
        } else {
            logger.info("Creating new peripheral")
            let new = SensorPeripheral(from: peripheral)
            sensors[peripheral.identifier] = new
        }
        
        centralManager.connect(peripheral)
    }
        
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        logger.error("didFailToConnect \(peripheral) \(error)")
        guard let error = error else {
            return
        }
        logger.error("\(error)")
    }
    
    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral
                        peripheral: CBPeripheral,
                        error: Error?) {
        logger.warning("⚠️ Peripheral disconnection. \(peripheral.identifier). Reason: \(error)")
        
        guard let error = error else {
            // Intentional disconnect: exit
            return
        }
        logger.error("\(error)")
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        logger.info("Connected to peripheral. Peripheral name: \(peripheral.name ?? ""). ID: \(peripheral.identifier).")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.objectWillChange.send()
            peripheral.discoverServices(nil)
        }
    }
    
    func centralManager(_ central: CBCentralManager, connectionEventDidOccur event: CBConnectionEvent, for peripheral: CBPeripheral) {
        logger.debug("Event: \(String(describing: event)) \(peripheral)")
    }
}

extension CBManagerState: @retroactive CustomStringConvertible {
    public var description: String {
        switch self {
        case .unknown:
            return "unknown"
        case .resetting:
            return "resetting"
        case .unsupported:
            return "unsupported"
        case .unauthorized:
            return "unauthorized"
        case .poweredOff:
            return "poweredOff"
        case .poweredOn:
            return "poweredOn"
        @unknown default:
            return "poweredOn default"
        }
    }
}
