# [해결 완료] 🐞 버그 리포트: iOS -> Android 메시지 수신 실패

**최종 수정일:** 2026년 1월 21일
**상태:** ✅ **해결됨 (Resolved)**
**작성자:** Gemini CLI Agent

---

## 1. 📝 문제 상황 요약
Flutter BLE 채팅 앱 개발 중, **안드로이드에서 iOS로는 메시지가 잘 가는데, iOS에서 안드로이드로는 메시지가 전송되지 않는 현상**이 발생함.

- **증상:** iOS는 전송 성공으로 처리하지만, 안드로이드 로그(`adb logcat`)에는 `onCharacteristicWriteRequest` 콜백 자체가 찍히지 않음.
- **환경:** Android (Peripheral/GATT Server) <-> iOS (Central/GATT Client)

---

## 2. 🔍 원인 분석 (Root Cause)

### 2.1 BLE 전송 방식의 불일치
Bluetooth Low Energy(BLE)의 데이터 쓰기(Write) 방식에는 크게 두 가지가 있습니다.

1.  **Write Request (`.withResponse`):**
    - 데이터를 보낸 후, 수신 측(Android)으로부터 "잘 받았다"는 응답(ACK)을 기다림.
    - 응답이 올 때까지 다음 패킷을 보내지 않음 (신뢰성 높음, 속도 느림).
    - **문제점:** iOS 코드는 이 방식을 사용했으나, 안드로이드 GATT 서버가 이 요청을 수신했을 때 적절한 처리를 하지 못하거나, 블루투스 스택 단계에서 필터링 되어 **애플리케이션 계층(Flutter/Kotlin)으로 전달되지 않음.**

2.  **Write Command (`.withoutResponse`):**
    - 데이터를 보내고 응답을 기다리지 않음 (Fire-and-forget).
    - **해결책:** 채팅과 같은 실시간성 데이터 전송에는 이 방식이 훨씬 빠르고, 이기종(iOS<->Android) 간 호환성이 높음.

### 2.2 결론
iOS는 엄격한 **`Write Request`**를 시도했으나, 안드로이드 기기와의 핸드셰이킹 과정에서 호환성 문제로 인해 요청이 유실되었습니다.

---

## 3. 🛠 해결 과정 (Solution applied)

### 3.1 [핵심 수정] iOS 전송 방식 변경
iOS의 `BleCentralManager.swift` 파일에서 메시지 전송 타입을 변경하여 안드로이드가 즉시 수신할 수 있도록 조치했습니다.

**수정 파일:** `ios/Runner/BleCentralManager.swift`

```swift
// [변경 전] .withResponse 사용 (실패 원인)
peripheral.writeValue(data, for: characteristic, type: .withResponse)

// [변경 후] .withoutResponse 사용 (해결)
// 안드로이드의 PROPERTY_WRITE_NO_RESPONSE 특성과 매칭되어 즉시 전송됨
peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
print("iOS [Central] 메시지 전송 시도 (Without Response): \(message)")
```

### 3.2 [보완] 안드로이드 로그 강화
추후 유사한 문제 발생 시 빠른 파악을 위해 안드로이드 수신부의 로그를 강화했습니다.

**수정 파일:** `android/app/src/main/kotlin/com/example/healthnyou_ble_chat/BlePeripheralManager.kt`

```kotlin
override fun onCharacteristicWriteRequest(...) {
    val msg = String(value)
    // 요청이 들어오면 무조건 로그 출력 (UUID 확인용)
    Log.d(TAG, "AOS [Peripheral] Write 요청 수신 (UUID: ${characteristic.uuid}, ResponseNeeded: $responseNeeded): $msg")
    
    // ... (이하 로직)
}
```

---

## 4. ✅ 검증 결과 (Verification)

사용자 피드백을 통해 다음 사항이 확인되었습니다.

1.  **iOS -> Android 전송:** iOS에서 메시지를 보내면 안드로이드 화면에 즉시 텍스트가 출력됨.
2.  **로그 확인:** 안드로이드 `adb logcat`에 `Write 요청 수신` 로그가 정상적으로 기록됨.
3.  **양방향 통신:** Android <-> iOS 간 자유로운 대화 가능.

## 5. 💡 교훈 (Lessons Learned)
- **BLE 크로스 플랫폼 개발 시:** 데이터 전송(`Write`)은 특별한 이유(펌웨어 업데이트 등)가 없다면 **`Write Command (.withoutResponse)`**를 기본으로 사용하는 것이 연결 안정성과 속도 면에서 유리하다.
- **로그의 중요성:** 수신 측(안드로이드) 로그에 아무것도 찍히지 않는다는 것은 "연결이 안 됐거나" 혹은 "전송 방식(Protocol)이 맞지 않아 OS 단에서 거절됨"을 의미한다.