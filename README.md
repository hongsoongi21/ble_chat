# HealthNYou BLE Chat (블루투스 1:1 채팅)

**HealthNYou BLE Chat**은 인터넷이나 데이터 연결 없이, **블루투스(Bluetooth Low Energy, BLE)**만을 이용하여 근거리에서 1:1로 안전하게 대화할 수 있는 모바일 애플리케이션입니다.

Flutter 프레임워크를 기반으로 개발되었으며, Android와 iOS 간의 원활한 통신을 위해 플랫폼 네이티브 BLE API(Kotlin/Swift)를 직접 연동하여 높은 안정성과 연결성을 제공합니다.

---

## ✨ 주요 기능

*   **오프라인 채팅**: Wi-Fi나 데이터 없이 오직 블루투스만으로 메시지를 주고받을 수 있습니다.
*   **크로스 플랫폼 지원**: Android와 iOS 기기 간의 상호 연결 및 채팅을 지원합니다.
*   **이중 모드 지원**: 하나의 앱에서 **Central(스캔/연결)** 역할과 **Peripheral(광고/대기)** 역할을 모두 수행할 수 있습니다.
*   **실시간 메시지 전송**: 연결된 즉시 지연 없이 텍스트 메시지를 전송합니다.
*   **자동 권한 관리**: 복잡한 블루투스 및 위치 권한 요청 프로세스를 간편하게 처리합니다.

---

## 🛠 기술 스택 (Tech Stack)

*   **Framework**: [Flutter](https://flutter.dev/) (SDK 3.8.1 이상)
*   **Language**: Dart
*   **Native Code**:
    *   **Android**: Kotlin (BluetoothLeScanner, BluetoothGattServer)
    *   **iOS**: Swift (CoreBluetooth)
*   **State Management**: [GetX](https://pub.dev/packages/get)
*   **Packages**:
    *   `permission_handler`: 런타임 권한 요청 관리
    *   `intl`: 날짜 및 시간 포맷팅

---

## 🚀 설치 및 실행 방법

이 프로젝트는 Flutter 환경이 구성된 컴퓨터에서 실행할 수 있습니다.

### 1. 전제 조건 (Prerequisites)
*   Flutter SDK 설치 완료
*   Android Studio 또는 VS Code
*   실제 모바일 기기 (Android 또는 iOS)
    *   *참고: 블루투스 기능은 에뮬레이터/시뮬레이터에서 정상 작동하지 않을 수 있으므로 **실기기 테스트**를 권장합니다.*

### 2. 프로젝트 클론 (Clone)
```bash
git clone https://github.com/hongsoongi21/ble_chat.git
cd healthnyou_ble_chat
```

### 3. 패키지 설치
```bash
flutter pub get
```

### 4. 앱 실행
디바이스를 PC에 연결한 후 아래 명령어로 실행합니다.
```bash
flutter run
```

---

## 📖 사용 가이드

앱을 정상적으로 사용하기 위해서는 두 대의 기기가 필요하며, 각각 다른 역할을 수행해야 합니다.

### [역할 1] 대기자 (신호 보내기)
1.  앱 실행 후 상단의 **'주변 장치 모드'** 스위치를 **ON**으로 켭니다.
2.  상대방이 나를 찾을 때까지 대기합니다.

### [역할 2] 찾는 사람 (연결 하기)
1.  앱 실행 후 **[기기 스캔]** 버튼을 누릅니다.
2.  목록에서 상대방 기기(예: `HealthNYou-Chat`)를 찾아 선택합니다.

✅ **연결 성공 시**: 두 기기 모두 자동으로 채팅 화면으로 이동하며 대화를 시작할 수 있습니다.

---

## 📂 폴더 구조

```text
lib/
├── controller/      # 비즈니스 로직 및 상태 관리 (GetX Controller)
│   └── chat_controller.dart
├── model/           # 데이터 모델
│   ├── ble_device.dart
│   └── chat_message.dart
├── service/         # 네이티브 통신 및 서비스 로직
│   └── ble_manager.dart
├── ui/              # 화면 UI 구성
│   ├── chat_page.dart
│   └── scan_page.dart
└── util/            # 유틸리티 (로거 등)
    └── logger.dart
```

---

## ⚠️ 문제 해결 및 주의사항

*   **권한 허용**: 앱 최초 실행 시 요청하는 **'근처 기기'** 및 **'위치'** 권한을 반드시 허용해야 검색이 가능합니다.
*   **검색이 안 될 때**: 스마트폰의 블루투스를 껐다 켜거나, 앱을 완전히 종료 후 다시 실행해 보세요.
*   **거리 제한**: BLE 기술 특성상 약 10m 이내의 거리에서 가장 안정적으로 작동합니다.

---

## 📝 라이선스

이 프로젝트는 개인 학습 및 포트폴리오 목적으로 제작되었습니다.