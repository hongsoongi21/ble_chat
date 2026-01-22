# BLE 1:1 채팅 애플리케이션 구현 계획서

본 문서는 '헬스앤유 신입 개발자 온보딩 과제'인 BLE 기반 1:1 채팅 애플리케이션의 구현 계획을 정의합니다.

## 1. 프로젝트 개요
- **목표**: 두 대의 스마트폰 간 BLE 통신을 이용한 1:1 채팅 앱 개발
- **핵심 기술**: Flutter, Method Channel, Event Channel, BLE (GATT), GetX

## 2. 기술 아키텍처 (3-Tier)
과제 요구사항에 따라 다음과 같이 계층을 분리하여 구현합니다.

| 계층 | 역할 | 주요 컴포넌트 |
| :--- | :--- | :--- |
| **Flutter Layer** | UI 및 비즈니스 로직 | GetX Controller, BleManager (Service) |
| **Platform Bridge** | Flutter <-> Native 연결 | Method Channel Handler, Event Sink |
| **Native BLE Layer** | 실제 BLE 통신 수행 | BluetoothGattServer (Android), CBCentralManager (iOS) |

## 3. 상세 통신 명세

### 3.1 Method Channel (Flutter -> Native)
- 채널명: `kr.co.thejoin.ble_chat/methods`
- 주요 메서드:
    - `startPeripheralMode()`: GATT 서버 시작 및 광고(Advertising) 시작
    - `stopPeripheralMode()`: 광고 중지 및 서버 종료
    - `startScan()`: 주변 기기 스캔 시작
    - `stopScan()`: 스캔 중지
    - `connect(deviceId)`: 특정 기기에 연결 시도 (Central)
    - `disconnect()`: 연결 해제
    - `sendMessage(message)`: GATT Write를 통한 메시지 전송
    - `getConnectionState()`: 현재 연결 상태 확인

### 3.2 Event Channel (Native -> Flutter)
- `ble_chat/connection`: 연결 상태 변경 알림 (`connected`, `disconnected` 등)
- `ble_chat/scan_results`: 스캔된 디바이스 리스트 전달
- `ble_chat/messages`: 수신된 채팅 메시지 전달
- `ble_chat/errors`: BLE 관련 에러 발생 알림

## 4. GATT 프로토콜 설계
- **Chat Service UUID**: `00001234-0000-1000-8000-00805f9b34fb` (예시)
- **Message Characteristic**: `00005678-0000-1000-8000-00805f9b34fb` (Write/Notify)

## 5. 구현 단계별 계획

### 1단계: 환경 설정 및 UI 뼈대 구성
- [x] 프로젝트 구조 생성 (controller, service, ui, model)
- [x] **권한 설정 (Permissions Configuration)**
    - [x] **Android**: `AndroidManifest.xml`에 BLE 권한 선언 완료
    - [x] **iOS**: `Info.plist`에 블루투스 사용 목적 설명 추가 완료
- [x] GetX 및 `permission_handler`, `intl` 패키지 설정 완료
- [x] 기본 UI 구성 (스캔 화면, 채팅 화면, 상태 표시바) 완료

### 2단계: 플랫폼 브리지 및 서비스 정의
- [x] Flutter: `BleManager` 서비스 클래스 및 Method/Event Channel 정의 완료
- [x] Flutter: `ChatController` (GetX) 상태 관리 기초 및 스트림 구독 로직 완료
- [x] Android: `MainActivity` 내 Method/Event Channel 핸들러 뼈대 작성 완료
- [x] iOS: `AppDelegate` 내 Method/Event Channel 핸들러 뼈대 작성 완료

### 3단계: Native BLE Peripheral 구현 (GATT Server)
- [x] Android: `BlePeripheralManager` 및 광고(Advertising) 로직 구현 완료
- [x] iOS: `BlePeripheralManager` 및 서비스/캐릭터리스틱 광고 구현 완료
- [x] GATT Write/Notify를 통한 양방향 통신 기초 마련 완료

### 4단계: Native BLE Central 구현 (GATT Client)
- [x] Android: `BleCentralManager` 스캔, 연결, 서비스 탐색 구현 완료
- [x] iOS: `BleCentralManager` 스캔, 연결, 서비스 탐색 구현 완료
- [x] 캐릭터리스틱 구독(Notification) 및 데이터 송수신 연동 완료

### 5단계: 강력한 연결 관리 및 자원 해제 (안정화 및 고도화)
- [x] 상세 에러 처리 (블루투스 미활성화, 권한 거부 등) 완료
- [ ] **자원 정리 로직 강화 (Resource Clean-up)**
    - [ ] 연결 해제 시 GATT 서버/클라이언트 객체 완전 파기 및 메모리 해제
    - [ ] 광고(Advertising)와 스캔(Scanning)의 상환 관계 정리 (연결 시 스캔 자동 중지 등)
- [ ] **재연결 및 상태 복구 (Re-connection Cycle)**
    - [ ] 연결 끊김 감지 시 Flutter UI 자동 내비게이션 (채팅방 -> 스캔 화면)
    - [ ] 세션 종료 시 채팅 로그 및 스캔 결과 초기화 로직 보완
- [x] 코드 리팩토링 및 주석 최종 점검 완료

## 6. 프로젝트 완료 요약
본 프로젝트는 Flutter와 Native(Android/iOS) 간의 효율적인 통신 아키텍처를 바탕으로, 실시간 BLE 1:1 채팅 기능을 구현하였습니다. 3-Tier 계층 분리를 통해 유지보수성을 높였으며, 특히 연결 해제 후 다른 기기와의 재연결이 원활하도록 자원 정리 로직을 강화하는 데 집중하고 있습니다.

## 6. 평가 기준 자가 체크리스트
- [ ] Central/Peripheral 모드 각각 정상 동작 여부
- [ ] 두 기기 간 안정적인 연결 수립
- [ ] 양방향 메시지 송수신 및 UI 반영
- [ ] 3-Tier 구조에 따른 코드 분리 및 논리적 설계
