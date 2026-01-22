import Flutter
import UIKit
import CoreBluetooth

@main
@objc class AppDelegate: FlutterAppDelegate {
  
  private var connSink: FlutterEventSink?
  private var scanSink: FlutterEventSink?
  private var msgSink: FlutterEventSink?
  private var errSink: FlutterEventSink?

  private var peripheralManager: BlePeripheralManager?
  private var centralManager: BleCentralManager?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    
    GeneratedPluginRegistrant.register(with: self)
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    
    if let controller = window?.rootViewController as? FlutterViewController {
        setupChannels(messenger: controller.binaryMessenger)
    }
    
    return result
  }

  private func setupChannels(messenger: FlutterBinaryMessenger) {
    peripheralManager = BlePeripheralManager()
    centralManager = BleCentralManager()

    let methodChannel = FlutterMethodChannel(name: "kr.co.thejoin.ble_chat/methods", binaryMessenger: messenger)
    methodChannel.setMethodCallHandler({ [weak self] (call, result) in
        self?.handleMethodCall(call, result: result)
    })

    setupEventChannel(messenger: messenger, name: "ble_chat/connection") { [weak self] sink in
        self?.connSink = sink
        self?.peripheralManager?.connectionSink = sink
        self?.centralManager?.connectionSink = sink
    }
    setupEventChannel(messenger: messenger, name: "ble_chat/scan_results") { [weak self] sink in
        self?.scanSink = sink
        self?.centralManager?.scanSink = sink
    }
    setupEventChannel(messenger: messenger, name: "ble_chat/messages") { [weak self] sink in
        self?.msgSink = sink
        self?.peripheralManager?.messageSink = sink
        self?.centralManager?.messageSink = sink
    }
    setupEventChannel(messenger: messenger, name: "ble_chat/errors") { [weak self] sink in
        self?.errSink = sink
        self?.peripheralManager?.errorSink = sink
        self?.centralManager?.errorSink = sink
    }
  }

  private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
      switch call.method {
      case "startPeripheralMode":
          result(peripheralManager?.startPeripheral() ?? false)
      case "stopPeripheralMode":
          peripheralManager?.stopPeripheral()
          result(true)
      case "startScan":
          result(centralManager?.startScan() ?? false)
      case "stopScan":
          centralManager?.stopScan()
          result(true)
      case "connect":
          if let args = call.arguments as? [String: Any], let deviceId = args["deviceId"] as? String {
              result(centralManager?.connect(to: deviceId) ?? false)
          } else { result(false) }
      case "disconnect":
          peripheralManager?.stopPeripheral()
          centralManager?.disconnect()
          result(true)
      case "sendMessage":
          if let args = call.arguments as? [String: Any], let message = args["message"] as? String {
              let pSuccess = peripheralManager?.sendMessage(message) ?? false
              let cSuccess = centralManager?.sendMessage(message) ?? false
              result(pSuccess || cSuccess)
          } else { result(false) }
      case "getConnectionState":
          result("UNKNOWN")
      default:
          result(FlutterMethodNotImplemented)
      }
  }

  private func setupEventChannel(messenger: FlutterBinaryMessenger, name: String, sinkSetter: @escaping (FlutterEventSink?) -> Void) {
    let eventChannel = FlutterEventChannel(name: name, binaryMessenger: messenger)
    eventChannel.setStreamHandler(EventStreamHandler(sinkSetter: sinkSetter))
  }
}

class EventStreamHandler: NSObject, FlutterStreamHandler {
    private var sinkSetter: (FlutterEventSink?) -> Void
    init(sinkSetter: @escaping (FlutterEventSink?) -> Void) { self.sinkSetter = sinkSetter }
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sinkSetter(events)
        return nil
    }
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        sinkSetter(nil)
        return nil
    }
}

// MARK: - BlePeripheralManager (최신 수정 반영)
class BlePeripheralManager: NSObject, CBPeripheralManagerDelegate {
    let SERVICE_UUID = CBUUID(string: "FF01") // FF01로 통일
    let CHARACTERISTIC_UUID = CBUUID(string: "FF02") // FF02로 통일
    
    private var peripheralManager: CBPeripheralManager?
    private var chatCharacteristic: CBMutableCharacteristic?
    private var connectedCentral: CBCentral?
    
    var messageSink: FlutterEventSink?
    var connectionSink: FlutterEventSink?
    var errorSink: FlutterEventSink?
    
    override init() {
        super.init()
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
    }
    
    func startPeripheral() -> Bool {
        guard peripheralManager?.state == .poweredOn else { return false }
        
        // 기존 광고 및 서비스 초기화 (중복 방지)
        peripheralManager?.stopAdvertising()
        peripheralManager?.removeAllServices()
        
        chatCharacteristic = CBMutableCharacteristic(
            type: CHARACTERISTIC_UUID,
            properties: [.write, .notify],
            value: nil,
            permissions: [.writeable]
        )
        
        let transferService = CBMutableService(type: SERVICE_UUID, primary: true)
        transferService.characteristics = [chatCharacteristic!]
        
        peripheralManager?.add(transferService)
        peripheralManager?.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [SERVICE_UUID],
            CBAdvertisementDataLocalNameKey: "HealthNYou-Chat"
        ])
        print("iOS Peripheral: 광고 시작 (HealthNYou-Chat)")
        return true
    }
    
    func stopPeripheral() {
        connectionSink?(["state": "DISCONNECTED", "deviceId": "ALL"])
        peripheralManager?.stopAdvertising()
        peripheralManager?.removeAllServices()
        connectedCentral = nil
    }
    
    func sendMessage(_ message: String) -> Bool {
        guard let characteristic = chatCharacteristic, let data = message.data(using: .utf8) else { return false }
        return peripheralManager?.updateValue(data, for: characteristic, onSubscribedCentrals: nil) ?? false
    }
    
    // MARK: Delegates
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn {
            print("iOS Peripheral 준비 완료")
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        if characteristic.uuid == CHARACTERISTIC_UUID {
            connectedCentral = central
            print("iOS Peripheral: Central 구독 시작 (\(central.identifier.uuidString))")
            connectionSink?(["state": "CONNECTED", "deviceId": central.identifier.uuidString, "role": "PERIPHERAL"])
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        if characteristic.uuid == CHARACTERISTIC_UUID {
            connectedCentral = nil
            print("iOS Peripheral: Central 구독 해제 (연결 끊김)")
            connectionSink?(["state": "DISCONNECTED", "deviceId": central.identifier.uuidString, "role": "PERIPHERAL"])
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            if request.characteristic.uuid == CHARACTERISTIC_UUID {
                if let data = request.value, let message = String(data: data, encoding: .utf8) {
                    print("iOS Peripheral: 메시지 수신 - \(message)")
                    messageSink?([
                        "sender": request.central.identifier.uuidString,
                        "content": message,
                        "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                    ])
                }
                peripheralManager?.respond(to: request, withResult: .success)
            }
        }
    }
}

// MARK: - BleCentralManager (최신 수정 반영)
class BleCentralManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    let SERVICE_UUID = CBUUID(string: "FF01") // FF01로 통일
    let CHARACTERISTIC_UUID = CBUUID(string: "FF02") // FF02로 통일
    
    private var centralManager: CBCentralManager?
    private var discoveredPeripheral: CBPeripheral?
    private var targetCharacteristic: CBCharacteristic?
    
    var scanSink: FlutterEventSink?
    var connectionSink: FlutterEventSink?
    var messageSink: FlutterEventSink?
    var errorSink: FlutterEventSink?
    
    override init() {
        super.init()
        print("🚀 [INTEGRATED] BleCentralManager 초기화 (v20260121_FINAL)")
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func startScan() -> Bool {
        guard centralManager?.state == .poweredOn else { return false }
        // 필터 없이 스캔하여 호환성 확보
        centralManager?.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        print("iOS Central: 스캔 시작 (v20260121_FINAL)")
        return true
    }
    
    func stopScan() {
        centralManager?.stopScan()
    }
    
    func connect(to deviceId: String) -> Bool {
        guard let peripheral = discoveredPeripheral, peripheral.identifier.uuidString == deviceId else { return false }
        centralManager?.connect(peripheral, options: nil)
        return true
    }
    
    func disconnect() {
        if let peripheral = discoveredPeripheral {
            connectionSink?(["state": "DISCONNECTED", "deviceId": peripheral.identifier.uuidString])
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        discoveredPeripheral = nil
        targetCharacteristic = nil
    }
    
    func sendMessage(_ message: String) -> Bool {
        guard let peripheral = discoveredPeripheral, let characteristic = targetCharacteristic, let data = message.data(using: .utf8) else {
            print("iOS Central: 전송 실패 (기기 없음)")
            return false
        }
        
        // [중요] .withoutResponse 사용 (안드로이드 호환성)
        peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
        print("iOS Central: 메시지 전송 (Without Response) - \(message)")
        return true
    }
    
    // MARK: Delegates
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            print("iOS Central 준비 완료")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? "이름 없음"
        // 타겟 기기 필터링 (이름 또는 UUID)
        let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let isTarget = name.contains("HealthNYou") || serviceUUIDs.contains(SERVICE_UUID)
        
        if isTarget {
            self.discoveredPeripheral = peripheral
            scanSink?([["id": peripheral.identifier.uuidString, "name": name, "rssi": RSSI.intValue]])
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("iOS Central: 연결 성공")
        peripheral.delegate = self
        peripheral.discoverServices([SERVICE_UUID])
        connectionSink?(["state": "CONNECTED", "deviceId": peripheral.identifier.uuidString])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("iOS Central: 연결 실패")
        connectionSink?(["state": "DISCONNECTED", "deviceId": peripheral.identifier.uuidString])
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("iOS Central: 연결 해제됨 (에러: \(error?.localizedDescription ?? "없음"))")
        connectionSink?(["state": "DISCONNECTED", "deviceId": peripheral.identifier.uuidString])
        self.targetCharacteristic = nil
        self.discoveredPeripheral = nil
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == SERVICE_UUID {
            peripheral.discoverCharacteristics([CHARACTERISTIC_UUID], for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics where characteristic.uuid == CHARACTERISTIC_UUID {
            self.targetCharacteristic = characteristic
            peripheral.setNotifyValue(true, for: characteristic)
            print("iOS Central: 채팅 특성 발견 및 구독 완료")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid == CHARACTERISTIC_UUID, let data = characteristic.value, let message = String(data: data, encoding: .utf8) {
            print("iOS Central: 메시지 수신 - \(message)")
            messageSink?([
                "sender": peripheral.identifier.uuidString,
                "content": message,
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
            ])
        }
    }
    
    // [중요] 안드로이드가 서비스를 종료했을 때(채팅방 나감) 감지
    @objc func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        print("iOS Central: 서비스 변경 감지 - \(invalidatedServices)")
        let isChatServiceRemoved = invalidatedServices.contains { $0.uuid == SERVICE_UUID }
        
        if isChatServiceRemoved {
            print("iOS Central: 채팅 서비스 종료됨. 연결 해제.")
            centralManager?.cancelPeripheralConnection(peripheral)
        }
    }
}