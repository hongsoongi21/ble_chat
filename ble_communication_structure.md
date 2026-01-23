# Bluetooth BLE 통신 구조 정의서 (HealthNYou Chat)

본 문서는 HealthNYou BLE 채팅 프로젝트의 블루투스 통신 아키텍처와 세부 프로토콜을 정의합니다.

## 1. 개요
이 프로젝트는 Flutter 앱 간의 저전력 블루투스(BLE)를 이용한 실시간 채팅 기능을 제공합니다. 각 기기는 상황에 따라 **Central(중앙 장치)** 또는 **Peripheral(주변 장치)** 역할을 수행하며 데이터를 주고받습니다.

---

## 2. 시스템 아키텍처

### 2.1 계층 구조
1.  **Flutter Layer (`chat_controller.dart`)**: UI와 비즈니스 로직을 연결하며, 플랫폼 채널을 통해 네이티브 기능을 제어합니다.
2.  **Bridge Layer (Platform Channels)**:
    *   **MethodChannel**: `kr.co.thejoin.ble_chat/methods` (제어 명령: 스캔, 연결, 전송 등)
    *   **EventChannels**: 비동기 데이터 스트림 (연결 상태, 스캔 결과, 메시지 수신 등)
3.  **Native Layer (iOS/Android)**: 각 OS의 BLE 스택(CoreBluetooth / Android BLE API)을 사용하여 실제 통신을 수행합니다.

### 2.2 플랫폼 채널 명세

| 종류 | 채널 이름 | 용도 |
| :--- | :--- | :--- |
| Method | `kr.co.thejoin.ble_chat/methods` | 명령 호출 (startScan, connect, sendMessage 등) |
| Event | `ble_chat/connection` | 연결 상태 변경 알림 (CONNECTED, DISCONNECTED) |
| Event | `ble_chat/scan_results` | 스캔된 주변 기기 목록 전달 |
| Event | `ble_chat/messages` | 상대방으로부터 수신된 채팅 메시지 데이터 |
| Event | `ble_chat/errors` | 통신 중 발생한 오류 정보 |

---

## 3. GATT 프로필 설계

상대방 기기를 식별하고 데이터를 교환하기 위해 정의된 전용 서비스 및 특성(Characteristic)입니다.

*   **Service UUID**: `0000FF01-0000-1000-8000-00805f9b34fb` (Short: `FF01`)
*   **Characteristic UUID**: `0000FF02-0000-1000-8000-00805f9b34fb` (Short: `FF02`)
    *   **Properties**: `Write`, `WriteWithoutResponse`, `Notify`
    *   **Permissions**: `Writeable`

---

## 4. 역할별 동작 프로세스

### 4.1 Central (중앙 장치) - 주로 연결을 시도하는 쪽
1.  **Scan**: `FF01` 서비스를 광고(Advertising)하거나 이름에 "HealthNYou"가 포함된 기기를 찾습니다.
2.  **Connect**: 발견된 기기의 UUID/MAC 주소로 연결을 시도합니다.
3.  **Service Discovery**: 연결 성공 시 `FF01` 서비스와 그 하위의 `FF02` 특성을 탐색합니다.
4.  **Subscribe**: `FF02` 특성에 대해 **Notify**를 활성화하여 상대방이 보내는 데이터를 받을 준비를 합니다.
5.  **Send**: 메시지 전송 시 `FF02` 특성에 `WriteWithoutResponse` 방식으로 데이터를 씁니다.

### 4.2 Peripheral (주변 장치) - 주로 대기하는 쪽
1.  **Advertising**: `FF01` 서비스 UUID와 기기 이름(예: "HealthNYou-Chat")을 포함한 신호를 주변에 뿌립니다.
2.  **GATT Server**: 자신의 메모리에 `FF01` 서비스와 `FF02` 특성을 생성하여 대기합니다.
3.  **Subscribe Handling**: Central이 `FF02`를 구독(Notify 설정)하면 이를 연결 수립 시점으로 간주합니다.
4.  **Receive**: Central이 `FF02`에 데이터를 쓰면 `didReceiveWrite` 콜백을 통해 메시지를 수신합니다.
5.  **Send**: 메시지 전송 시 `FF02` 특성의 값을 업데이트하여 구독 중인 Central에게 **Notification**을 보냅니다.

---

## 5. 데이터 흐름 (Message Flow)

### 메시지 전송 (A -> B)
1.  **Flutter**: `MethodChannel.invokeMethod('sendMessage', {'message': "안녕"})` 호출.
2.  **Native (Sender)**:
    *   현재 자신이 **Central**이면: 상대방의 특성에 `writeValue` (Write) 수행.
    *   현재 자신이 **Peripheral**이면: 자신의 특성 값을 `updateValue` (Notify) 수행.
3.  **Native (Receiver)**:
    *   **Central**인 경우: `didUpdateValueFor` 콜백으로 데이터 수신.
    *   **Peripheral**인 경우: `didReceiveWrite` 콜백으로 데이터 수신.
4.  **Bridge**: 수신된 바이너리 데이터를 UTF-8 문자열로 디코딩하여 `ble_chat/messages` EventChannel로 전송.
5.  **Flutter**: 스트림을 구독 중인 UI에서 메시지를 화면에 출력.

---

## 6. 구현 시 주의사항 (Compatibility)

*   **iOS UUID**: iOS는 보안 정책상 타 기기의 실제 MAC 주소를 제공하지 않고 자체 생성된 UUID를 사용하므로, 스캔 시점에 이 UUID를 식별자로 관리해야 합니다.
*   **MTU Size**: 기본 MTU 크기를 초과하는 긴 메시지의 경우 패킷 분할 처리가 필요할 수 있습니다 (현재는 단순 전송 구조).
*   **Write Type**: 안드로이드와의 호환성 및 성능을 위해 `writeWithoutResponse` 방식을 우선적으로 사용합니다.
