# 📘 BLE 프로젝트 기술 분석 보고서

본 문서는 Flutter 기반 BLE 채팅 애플리케이션 개발 중 발생한 핵심 버그 2가지와 그 해결 과정을 기술적으로 분석하여 정리한 학습 리포트입니다.

---

## 1. 메시지 전송 실패 (iOS → Android)

### 🧐 현상
*   **Android → iOS:** 메시지 전송 및 수신 성공.
*   **iOS → Android:** iOS에서는 성공 로그가 찍히지만, Android 기기에서는 메시지가 전혀 수신되지 않음.

### 🔍 원인 분석: GATT Write 방식의 차이
BLE에서 데이터를 수신 측에 쓸 때(Write), 크게 두 가지 모드가 있습니다.

1.  **Write With Response (응답이 필요한 쓰기):**
    *   **작동 방식:** 클라이언트가 데이터를 보낸 후, 서버(수신 측)로부터 "잘 받았다"는 응답(ACK)을 받을 때까지 기다립니다.
    *   **문제점:** 이기종간(iOS-Android) 통신 시, OS 내부 블루투스 스택의 핸드셰이킹(Handshaking) 과정에서 응답 신호가 유실되거나 지연되면 애플리케이션 계층까지 데이터가 도달하지 못하고 버려질 수 있습니다. 이번 버그의 핵심 원인이었습니다.

2.  **Write Without Response (응답 없는 쓰기):**
    *   **작동 방식:** 응답을 기다리지 않고 데이터를 즉시 "던지는" 방식입니다.
    *   **장점:** 속도가 빠르고, 복잡한 응답 과정이 생략되므로 연결된 상태라면 훨씬 안정적으로 데이터가 전달됩니다.

### 🛠 해결책
iOS의 전송 코드를 **`type: .withResponse`**에서 **`type: .withoutResponse`**로 변경하여 Android 기기와의 호환성을 확보했습니다.

```swift
// BleCentralManager.swift 수정 내용
// [기존] 응답을 기다리다 유실됨
peripheral.writeValue(data, for: characteristic, type: .withResponse)

// [수정] 응답 없이 즉시 전송 (Android 수신 성공)
peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
```

---

## 2. 연결 해제 미감지 (Android 나가기 시)

### 🧐 현상
*   Android 사용자가 채팅방을 나가서 서비스를 종료(`clearServices`)했음에도 불구하고, iOS 사용자의 화면은 여전히 `CONNECTED` 상태로 유지되며 아무런 변화가 없음.

### 🔍 원인 분석: 서비스 변경 알림 누락
Android가 채팅방을 나갈 때 단순히 연결을 끊는 것이 아니라, 자기가 갖고 있던 **GATT 서비스 목록을 삭제**합니다. 이때 Android는 연결된 모든 기기에 **"내 서비스 목록이 변했다!"**라는 신호를 보냅니다.

*   **iOS의 특징:** iOS 하드웨어는 이 신호를 받으면 델리게이트(Delegate) 메서드인 `peripheral(_:didModifyServices:)`를 호출하려고 시도합니다.
*   **문제점:** 기존 코드에는 이 메서드가 구현되어 있지 않았습니다. 따라서 iOS 앱은 신호를 받았음에도 불구하고 어떻게 행동해야 할지 몰라 무시하게 되었고, 사용자는 상대방이 나간 것을 알 수 없었습니다.

### 🛠 해결책
`CBPeripheralDelegate` 프로토콜의 **`didModifyServices`** 메서드를 구현하여, 우리가 사용하던 채팅 서비스(`FF01`)가 사라지면 즉시 연결을 해제하도록 로직을 추가했습니다.

```swift
// AppDelegate.swift (통합 코드) 수정 내용
@objc func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
    // 사라진 서비스들 중에 우리 채팅 서비스가 있는지 확인
    let isChatServiceRemoved = invalidatedServices.contains { $0.uuid == SERVICE_UUID }
    
    if isChatServiceRemoved {
        print("상대방이 서비스를 종료함 -> 연결 강제 해제")
        centralManager?.cancelPeripheralConnection(peripheral)
    }
}
```
*   **@objc 키워드:** 이 메서드는 iOS 내부 시스템(Objective-C 런타임)에서 호출하므로, Swift 코드임을 알려주는 `@objc` 키워드가 필수적입니다.

---

## 💡 학습 포인트 요약

1.  **BLE 데이터 전송은 최대한 가볍게:** 실시간 채팅이나 지속적인 데이터 전송에는 `Write Without Response`가 이기종 호환성과 속도 면에서 유리합니다.
2.  **모든 상태 변화에 대응하라:** 연결이 끊기는 방식은 "물리적 거리 멀어짐", "소프트웨어적 연결 종료", "서비스 구성 변경" 등 다양합니다. 각각의 콜백 메서드를 모두 챙겨야 견고한 앱이 됩니다.
3.  **네이티브 캐시의 영향력:** 코드를 수정했는데도 반영이 안 된다면 반드시 `flutter clean`과 더불어 네이티브 빌드 폴더를 수동으로 삭제하여 Xcode가 새 코드를 읽도록 강제해야 합니다.

---
*본 보고서는 2026년 1월 21일, BLE 통신 최적화 작업을 바탕으로 작성되었습니다.*
