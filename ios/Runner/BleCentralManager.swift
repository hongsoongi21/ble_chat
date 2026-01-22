import Foundation
import CoreBluetooth
import Flutter

/// iOS 기기를 BLE 중앙 장치(Central)로 동작하게 관리하는 클래스
/// 역할: 주변 기기 스캔(Scan), 기기 연결(Connect), 서비스 및 캐릭터리스틱 탐색, 데이터 송수신
class BleCentralManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    // --- GATT 설계 UUID (FF01 시리즈로 복구) ---
    let SERVICE_UUID = CBUUID(string: "0000FF01-0000-1000-8000-00805f9b34fb")
    let CHARACTERISTIC_UUID = CBUUID(string: "0000FF02-0000-1000-8000-00805f9b34fb")
    
    private var centralManager: CBCentralManager?
    private var discoveredPeripheral: CBPeripheral?
    private var targetCharacteristic: CBCharacteristic?
    
    // Flutter 레이어로 데이터를 실시간 전달하기 위한 통로들 (Sink)
    var scanSink: FlutterEventSink?
    var connectionSink: FlutterEventSink?
    var messageSink: FlutterEventSink?

    override init() {
        super.init()
        // Central Manager 초기화 (대리자 설정)
        print("🚀 [BUILD_CHECK] BleCentralManager 초기화됨 (v20260121_v3)")
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    /// 주변 기기 스캔 시작
    func startScan() -> Bool {
        // 블루투스가 켜져 있는지 확인
        guard centralManager?.state == .poweredOn else { return false }
        
        // 특정 서비스 UUID 필터 제거 (nil 전달)하여 모든 기기 스캔
        centralManager?.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        print("iOS BLE Central 스캔 시작 (v20260121_v3_scan)")
        return true
    }

    /// 스캔 중지
    func stopScan() {
        centralManager?.stopScan()
        print("iOS BLE Central 스캔 중지")
    }

    /// 특정 식별자(UUID String)를 가진 기기에 연결을 시도합니다.
    func connect(to deviceId: String) -> Bool {
        // iOS는 보안상 실제 MAC 주소를 가리고 내부용 UUID를 사용함
        // 스캔 시점에 발견하여 캐싱된 peripheral 객체가 필요함
        guard let peripheral = discoveredPeripheral, peripheral.identifier.uuidString == deviceId else {
            print("연결 오류: 발견된 기기 목록에 해당 UUID가 없습니다.")
            return false
        }
        
        // 해당 기기에 연결 요청
        centralManager?.connect(peripheral, options: nil)
        return true
    }

    /// 현재 연결된 기기와의 연결을 해제합니다.
    func disconnect() {
        if let peripheral = discoveredPeripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
    }

    /// 연결된 상대방에게 메시지를 전송합니다 (GATT Write).
    func sendMessage(_ message: String) -> Bool {
        guard let peripheral = discoveredPeripheral,
              let characteristic = targetCharacteristic,
              let data = message.data(using: .utf8) else {
            print("iOS [Central] 전송 실패: 기기 또는 특성을 찾을 수 없음")
            return false
        }
        
        // .withoutResponse: 안드로이드 기기와의 호환성 및 전송 속도를 위해 응답 없이 즉시 전송
        peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
        print("iOS [Central] 메시지 전송 시도 (Without Response): \(message)")
        return true
    }

    // MARK: - CBCentralManagerDelegate (스캔 및 연결 상태 관리)

    /// 블루투스 상태 변경 시 호출됨
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            print("iOS Central Manager 준비 완료 (v20260121_fix_check)")
        }
    }

    /// 주변 기기 발견 시 호출되는 콜백
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let deviceName = peripheral.name ?? "이름 없음"
        
        // 디버깅용: 발견된 모든 기기 로그 (필요 시 주석 해제)
        print("스캔 발견: \(deviceName) (\(peripheral.identifier.uuidString))")

        // 1. 광고 데이터에서 서비스 UUID들 확인
        let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        
        // 2. 타겟 기기 여부 확인 (이름에 HealthNYou가 있거나, 우리가 찾는 UUID가 있는 경우)
        let isTarget = deviceName.contains("HealthNYou") || serviceUUIDs.contains(SERVICE_UUID)
        
        if isTarget {
            print(">>> 타겟 기기 발견: \(deviceName), UUIDs: \(serviceUUIDs)")
            
            // 발견된 기기를 멤버 변수에 보관 (나중에 연결할 때 필요)
            self.discoveredPeripheral = peripheral
            
            // Flutter UI에 전달할 기기 정보 구성
            let deviceInfo: [String: Any] = [
                "id": peripheral.identifier.uuidString,
                "name": deviceName,
                "rssi": RSSI.intValue
            ]
            
            // Flutter로 스캔된 기기 목록 전달 (리스트 형태)
            scanSink?([deviceInfo])
        }
    }

    /// 기기 연결 성공 시 호출됨
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("iOS 연결 성공: \(peripheral.name ?? "Unknown")")
        
        // 1. 통신 이벤트를 받기 위해 기기의 대리자(Delegate) 설정
        peripheral.delegate = self
        // 2. 서비스 탐색 시작 (우리가 정의한 채팅 서비스 찾기)
        peripheral.discoverServices([SERVICE_UUID])
        
        // Flutter에 연결 성공 상태 알림
        connectionSink?(["state": "CONNECTED", "deviceId": peripheral.identifier.uuidString])
    }

    /// 연결 실패 시 호출됨
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("iOS [Central] 기기 연결 실패: \(peripheral.name ?? "Unknown") (에러: \(error?.localizedDescription ?? "없음"))")
        connectionSink?(["state": "DISCONNECTED", "deviceId": peripheral.identifier.uuidString])
    }

    /// 연결이 끊겼을 때 호출됨 (상대방이 연결을 끊거나 신호가 약해져서 끊긴 경우 포함)
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if let error = error {
            print("iOS [Central] 기기 연결 비정상 해제: \(peripheral.name ?? "Unknown") (원인: \(error.localizedDescription))")
        } else {
            print("iOS [Central] 기기 연결 정상 해제: \(peripheral.name ?? "Unknown")")
        }
        
        connectionSink?(["state": "DISCONNECTED", "deviceId": peripheral.identifier.uuidString])
        self.targetCharacteristic = nil // 캐릭터리스틱 정보 초기화
    }

    // MARK: - CBPeripheralDelegate (연결된 기기와의 데이터 통신)

    /// 기기의 서비스 탐색이 완료되었을 때 호출됨
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        
        for service in services {
            if service.uuid == SERVICE_UUID {
                // 3. 채팅 서비스 내의 캐릭터리스틱 탐색 시작
                peripheral.discoverCharacteristics([CHARACTERISTIC_UUID], for: service)
            }
        }
    }

    /// 캐릭터리스틱 탐색이 완료되었을 때 호출됨
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            if characteristic.uuid == CHARACTERISTIC_UUID {
                self.targetCharacteristic = characteristic
                
                // 4. 상대방이 보낼 데이터를 실시간으로 받기 위해 알림(Notify) 구독 설정
                peripheral.setNotifyValue(true, for: characteristic)
                print("iOS 채팅 특성(Characteristic) 탐색 및 알림 구독 성공")
            }
        }
    }

    /// 데이터 수신 시 호출됨 (Notify를 통해 상대방 메시지가 올 때)
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("iOS [Central] 데이터 수신 오류: \(error.localizedDescription)")
            return
        }
        
        if characteristic.uuid == CHARACTERISTIC_UUID, let data = characteristic.value {
            let dataSize = data.count
            let hexString = data.map { String(format: "%02hhx", $0) }.joined()
            print("iOS [Central] Raw 데이터 수신 - 크기: \(dataSize) bytes, Hex: \(hexString)")

            if let message = String(data: data, encoding: .utf8) {
                print("iOS [Central] 메시지 디코딩 성공: \(message)")
                
                // Flutter의 메시지 리스트로 데이터 전달
                messageSink?([
                    "sender": peripheral.identifier.uuidString,
                    "content": message,
                    "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                ])
            } else {
                print("iOS [Central] 메시지 디코딩 실패 (UTF-8 아님)")
            }
        }
    }

    /// 기기의 서비스가 변경되었을 때 호출됨 (예: 안드로이드가 채팅방을 나가서 clearServices()를 호출한 경우)
    @objc func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        print("iOS [Central] 기기 서비스 변경 감지: \(invalidatedServices.map { $0.uuid.uuidString })")
        
        // 채팅 서비스(FF01)가 무효화된 서비스 목록에 포함되어 있다면 연결 종료
        let isChatServiceRemoved = invalidatedServices.contains { $0.uuid == SERVICE_UUID }
        
        if isChatServiceRemoved {
            print("iOS [Central] 상대방이 채팅 서비스를 종료했습니다. 연결을 해제합니다.")
            centralManager?.cancelPeripheralConnection(peripheral)
            // 이후 didDisconnectPeripheral가 호출되어 Flutter로 종료 상태가 전달됨
        }
    }
}
