import Foundation
import CoreBluetooth
import Flutter

/// iOS 기기를 BLE 주변 장치(Peripheral)로 동작하게 관리하는 클래스
/// 역할: GATT 서버 운영, 서비스 등록, 신호 광고(Advertising), 데이터 수신/전달
class BlePeripheralManager: NSObject, CBPeripheralManagerDelegate {
    
    // --- GATT 설계 UUID (FF01 시리즈로 복구) ---
    let SERVICE_UUID = CBUUID(string: "0000FF01-0000-1000-8000-00805f9b34fb")
    let CHARACTERISTIC_UUID = CBUUID(string: "0000FF02-0000-1000-8000-00805f9b34fb")
    
    private var peripheralManager: CBPeripheralManager?
    private var chatCharacteristic: CBMutableCharacteristic?
    private var connectedCentral: CBCentral? // 현재 연결된 상대방(Central)
    
    // Flutter 레이어로 데이터를 실시간 전달하기 위한 통로 (Sink)
    var messageSink: FlutterEventSink?
    var connectionSink: FlutterEventSink?

    override init() {
        super.init()
        // Peripheral Manager 초기화 (대리자 설정)
        // 설정 시 블루투스 권한 및 상태 확인이 자동으로 이루어짐
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
    }

    /// 주변 장치 모드 시작 및 광고 활성화
    /// @return 성공 여부
    func startPeripheral() -> Bool {
        // 블루투스가 켜져 있는지 확인
        guard peripheralManager?.state == .poweredOn else {
            print("오류: 블루투스 전원이 켜져 있지 않습니다.")
            return false
        }
        
        // 1. 캐릭터리스틱(특성) 설정
        // .write: 상대방이 나에게 데이터를 쓸 수 있음
        // .notify: 내가 상대방에게 데이터 변화를 알릴 수 있음
        chatCharacteristic = CBMutableCharacteristic(
            type: CHARACTERISTIC_UUID,
            properties: [.write, .notify],
            value: nil,
            permissions: [.writeable]
        )
        
        // 2. 서비스 설정 및 캐릭터리스틱 등록
        let transferService = CBMutableService(type: SERVICE_UUID, primary: true)
        transferService.characteristics = [chatCharacteristic!]
        
        peripheralManager?.add(transferService)
        
        // 3. 광고(Advertising) 시작: 주변에서 내 기기를 찾을 수 있게 함
        peripheralManager?.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [SERVICE_UUID],
            CBAdvertisementDataLocalNameKey: "HealthNYou-Chat" // 검색될 때 보일 이름
        ])
        
        return true
    }

    /// 주변 장치 모드 중지 및 모든 서비스 제거
    func stopPeripheral() {
        peripheralManager?.stopAdvertising()
        peripheralManager?.removeAllServices()
        connectedCentral = nil
    }

    /// 연결된 상대방에게 메시지 전송 (Notify 방식)
    /// @param message 보낼 텍스트
    func sendMessage(_ message: String) -> Bool {
        guard let characteristic = chatCharacteristic,
              let data = message.data(using: .utf8) else { return false }
        
        // 구독(Subscribe) 중인 상대방에게 데이터 업데이트 신호를 보냄
        let success = peripheralManager?.updateValue(
            data,
            for: characteristic,
            onSubscribedCentrals: nil
        ) ?? false
        
        return success
    }

    // MARK: - CBPeripheralManagerDelegate (주요 콜백)

    /// 블루투스 상태가 변할 때마다 호출됨 (필수 구현)
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            print("iOS Peripheral 준비 완료")
        case .poweredOff:
            print("블루투스 꺼짐")
        case .unauthorized:
            print("블루투스 권한 거부됨")
        default:
            break
        }
    }

    /// 광고 시작 성공/실패 여부를 알려주는 콜백
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error = error {
            print("광고 시작 실패: \(error.localizedDescription)")
        } else {
            print("iOS BLE 광고 시작 성공 (HealthNYou-Chat)")
        }
    }

    /// 상대방(Central)이 나의 캐릭터리스틱을 구독하기 시작했을 때 (연결 수립으로 간주)
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        if characteristic.uuid == CHARACTERISTIC_UUID {
            connectedCentral = central
            print("iOS [Peripheral] Central 기기 연결 및 구독 시작: \(central.identifier.uuidString)")
            // Flutter UI에 연결 상태 알림
            connectionSink?(["state": "CONNECTED", "deviceId": central.identifier.uuidString])
        } else {
            print("iOS [Peripheral] 알 수 없는 특성 구독 요청: \(characteristic.uuid)")
        }
    }
    
    /// 상대방이 구독을 해제했을 때 (연결 종료로 간주)
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        if characteristic.uuid == CHARACTERISTIC_UUID {
            connectedCentral = nil
            print("iOS [Peripheral] Central 기기 구독 해제 (연결 끊김 처리): \(central.identifier.uuidString)")
            // Flutter UI에 연결 끊김 알림
            connectionSink?(["state": "DISCONNECTED", "deviceId": central.identifier.uuidString])
        } else {
            print("iOS [Peripheral] 알 수 없는 특성 구독 해제: \(characteristic.uuid)")
        }
    }

    /// 상대방이 나에게 Write 요청(데이터 전송)을 보냈을 때 호출됨
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            if request.characteristic.uuid == CHARACTERISTIC_UUID {
                if let data = request.value {
                    let dataSize = data.count
                    let hexString = data.map { String(format: "%02hhx", $0) }.joined()
                    print("iOS [Peripheral] Write 요청 수신 - 크기: \(dataSize) bytes, Hex: \(hexString)")
                    
                    if let message = String(data: data, encoding: .utf8) {
                        print("iOS [Peripheral] 메시지 디코딩 성공: \(message)")
                        
                        // Flutter 메시지 스트림으로 데이터 전달
                        messageSink?([
                            "sender": request.central.identifier.uuidString,
                            "content": message,
                            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                        ])
                    } else {
                        print("iOS [Peripheral] 메시지 디코딩 실패")
                    }
                } else {
                     print("iOS [Peripheral] Write 요청 수신했으나 데이터가 비어있음")
                }
                // 쓰기 작업 성공에 대한 응답 전송
                peripheralManager?.respond(to: request, withResult: .success)
            }
        }
    }
}
