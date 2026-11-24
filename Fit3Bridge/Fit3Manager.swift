import Foundation
import CoreBluetooth
import Combine

final class Fit3Manager: NSObject, ObservableObject {
    static let shared = Fit3Manager()

    @Published var isScanning = false
    @Published var isConnected = false
    @Published var connectionState = "Desconectado"
    @Published var peripheralName: String?
    @Published var steps: Int = 0
    @Published var distanceMeters: Double = 0
    @Published var calories: Int = 0
    @Published var heartRate: Int = 0
    @Published var batteryLevel: Int = 0
    @Published var bleLogs: [String] = []

    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var activityCharacteristic: CBCharacteristic?
    private var heartRateCharacteristic: CBCharacteristic?
    private var batteryCharacteristic: CBCharacteristic?
    private var samsungService: CBService?

    private let fit3NamePrefixes = ["Fit3", "4C20", "SM-R390"]
    private let samsungServiceUUID = CBUUID(string: "FEE7")
    private let activityCharUUID = CBUUID(string: "FEC7")
    private let heartRateServiceUUID = CBUUID(string: "180D")
    private let heartRateCharUUID = CBUUID(string: "2A37")
    private let batteryServiceUUID = CBUUID(string: "180F")
    private let batteryCharUUID = CBUUID(string: "2A19")

    private var handshakeSent = false
    private var pendingCommands: [Data] = []
    private var commandQueue: [Data] = []
    private var isProcessingCommand = false

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
        log("Fit3Manager initialized")
    }

    func startScan() {
        guard centralManager.state == .poweredOn else {
            log("Bluetooth no está encendido: \(centralManager.state.rawValue)")
            connectionState = "Bluetooth apagado"
            return
        }
        isScanning = true
        connectionState = "Escaneando..."
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        log("Inicio escaneo BLE")
    }

    func stopScan() {
        centralManager.stopScan()
        isScanning = false
        log("Escaneo detenido")
    }

    func connect(to peripheral: CBPeripheral) {
        self.peripheral = peripheral
        centralManager.stopScan()
        isScanning = false
        centralManager.connect(peripheral, options: nil)
        connectionState = "Conectando..."
        log("Conectando a \(peripheral.name ?? "desconocido")")
    }

    func disconnect() {
        if let peripheral = peripheral {
            centralManager.cancelPeripheralConnection(peripheral)
            log("Desconectando...")
        }
    }

    func requestBatteryLevel() {
        guard let char = batteryCharacteristic else { return }
        peripheral?.readValue(for: char)
        log("Solicitando nivel de batería")
    }

    private func log(_ message: String) {
        let timestamp = DateFormatter.logFormatter.string(from: Date())
        let entry = "[\(timestamp)] \(message)"
        DispatchQueue.main.async {
            self.bleLogs.append(entry)
            if self.bleLogs.count > 200 { self.bleLogs.removeFirst() }
        }
        print(entry)
    }

    private func logHex(_ label: String, _ data: Data) {
        let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        log("\(label): \(hex)")
    }

    private func sendHandshake() {
        let timeCommand = buildTimeSyncCommand()
        sendCommand(timeCommand, description: "Handshake/Sync Time")
        handshakeSent = true
    }

    private func buildTimeSyncCommand() -> Data {
        var cmd = Data([0x01, 0x00, 0x00, 0x00, 0x00])
        let now = Date()
        let timestamp = UInt32(now.timeIntervalSince1970)
        withUnsafeBytes(of: timestamp.littleEndian) { cmd.append(contentsOf: $0) }
        let crc = calculateCRC(cmd)
        cmd.append(crc)
        return cmd
    }

    private func buildActivityRequestCommand() -> Data {
        var cmd = Data([0x02, 0x00, 0x00, 0x00, 0x00])
        let crc = calculateCRC(cmd)
        cmd.append(crc)
        return cmd
    }

    private func calculateCRC(_ data: Data) -> UInt8 {
        var crc: UInt8 = 0
        for byte in data {
            crc ^= byte
        }
        return crc
    }

    private func sendCommand(_ data: Data, description: String) {
        guard let char = activityCharacteristic, let peripheral = peripheral else { return }
        commandQueue.append(data)
        log("Encolado \(description): \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")
        processCommandQueue()
    }

    private func processCommandQueue() {
        guard !isProcessingCommand, !commandQueue.isEmpty,
              let char = activityCharacteristic, let peripheral = peripheral else { return }

        isProcessingCommand = true
        let cmd = commandQueue.removeFirst()
        peripheral.writeValue(cmd, for: char, type: .withResponse)
        log("Enviado: \(cmd.map { String(format: "%02X", $0) }.joined(separator: " "))")
    }

    private func parseActivityData(_ data: Data) {
        guard data.count >= 16 else {
            log("Trama de actividad muy corta: \(data.count) bytes")
            return
        }

        let stepCount = data.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let distance = data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let calorieCount = data.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }

        DispatchQueue.main.async {
            self.steps = Int(stepCount)
            self.distanceMeters = Double(distance) / 100.0
            self.calories = Int(calorieCount)
        }
        log("Actividad parseada - Pasos: \(stepCount), Distancia: \(Double(distance)/100)m, Calorías: \(calorieCount)")
    }

    private func parseHeartRate(_ data: Data) {
        guard data.count >= 2 else { return }
        let flags = data[0]
        let hrValue: Int
        if flags & 0x01 == 0 {
            hrValue = Int(data[1])
        } else {
            hrValue = Int(data.subdata(in: 1..<3).withUnsafeBytes { $0.load(as: UInt16.self).littleEndian })
        }
        DispatchQueue.main.async { self.heartRate = hrValue }
        log("Frecuencia cardíaca: \(hrValue) BPM")
    }

    private func parseBattery(_ data: Data) {
        guard data.count >= 1 else { return }
        let level = Int(data[0])
        DispatchQueue.main.async { self.batteryLevel = level }
        log("Nivel de batería: \(level)%")
    }
}

extension Fit3Manager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        log("Estado Bluetooth: \(central.state.rawValue)")
        switch central.state {
        case .poweredOn:
            connectionState = "Listo"
        case .poweredOff:
            connectionState = "Bluetooth apagado"
        case .unauthorized:
            connectionState = "Sin permisos Bluetooth"
        case .unsupported:
            connectionState = "BLE no soportado"
        default:
            connectionState = "Estado: \(central.state.rawValue)"
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        let matches = fit3NamePrefixes.contains { name.uppercased().contains($0.uppercased()) }

        if matches || (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.contains(samsungServiceUUID) == true {
            log("Dispositivo Fit3 encontrado: \(name) RSSI: \(RSSI)")
            connect(to: peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log("Conectado a \(peripheral.name ?? "desconocido")")
        connectionState = "Conectado - Descubriendo servicios"
        isConnected = true
        peripheralName = peripheral.name
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log("Error al conectar: \(error?.localizedDescription ?? "desconocido")")
        connectionState = "Error de conexión"
        isConnected = false
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        log("Desconectado: \(error?.localizedDescription ?? "normal")")
        connectionState = "Desconectado"
        isConnected = false
        handshakeSent = false
        activityCharacteristic = nil
        heartRateCharacteristic = nil
        batteryCharacteristic = nil
        samsungService = nil
    }
}

extension Fit3Manager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            log("Error descubriendo servicios: \(error)")
            return
        }
        guard let services = peripheral.services else { return }
        log("Servicios descubiertos: \(services.count)")
        for service in services {
            log("  Servicio: \(service.uuid.uuidString)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            log("Error descubriendo características: \(error)")
            return
        }
        guard let characteristics = service.characteristics else { return }

        for char in characteristics {
            log("  Característica: \(char.uuid.uuidString) - Props: \(char.properties.rawValue)")

            switch (service.uuid, char.uuid) {
            case (samsungServiceUUID, activityCharUUID):
                activityCharacteristic = char
                samsungService = service
                peripheral.setNotifyValue(true, for: char)
                log("  -> Actividad Samsung (Notify habilitado)")
                if !handshakeSent {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.sendHandshake() }
                }
            case (heartRateServiceUUID, heartRateCharUUID):
                heartRateCharacteristic = char
                peripheral.setNotifyValue(true, for: char)
                log("  -> Heart Rate (Notify habilitado)")
            case (batteryServiceUUID, batteryCharUUID):
                batteryCharacteristic = char
                peripheral.setNotifyValue(true, for: char)
                peripheral.readValue(for: char)
                log("  -> Battery (Notify habilitado)")
            default:
                break
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            log("Error leyendo característica: \(error)")
            return
        }
        guard let data = characteristic.value else { return }
        logHex("RX \(characteristic.uuid.uuidString)", data)

        switch characteristic.uuid {
        case activityCharUUID:
            parseActivityData(data)
            if !handshakeSent {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.sendCommand(self.buildActivityRequestCommand(), description: "Solicitud actividad")
                }
            }
        case heartRateCharUUID:
            parseHeartRate(data)
        case batteryCharUUID:
            parseBattery(data)
        default:
            break
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            log("Error escribiendo: \(error)")
        } else {
            log("Escritura confirmada para \(characteristic.uuid.uuidString)")
        }
        isProcessingCommand = false
        processCommandQueue()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            log("Error notificación \(characteristic.uuid.uuidString): \(error)")
        } else {
            log("Notificación \(characteristic.uuid.uuidString): \(characteristic.isNotifying ? "ON" : "OFF")")
        }
    }
}

private extension DateFormatter {
    static let logFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
}