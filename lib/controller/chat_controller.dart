import 'dart:async';
import 'dart:io'; // 플랫폼 확인을 위해 추가
import 'package:flutter/material.dart'; // Colors, WidgetsBindingObserver 사용을 위해 추가
import 'package:get/get.dart';
import '../service/ble_manager.dart';
import '../model/ble_device.dart';
import '../model/chat_message.dart';
import '../util/logger.dart';
import 'package:permission_handler/permission_handler.dart';

/// 앱의 전체적인 상태 관리와 BLE 비즈니스 로직을 담당하는 GetX 컨트롤러
class ChatController extends GetxController with WidgetsBindingObserver {
  final BleManager _bleManager = BleManager();

  // --- 반응형 상태 변수 (UI에서 관찰 가능) ---
  var isScanning = false.obs;           // 현재 주변 기기를 스캔 중인지 여부
  var isPeripheralMode = false.obs;     // 현재 내 기기가 주변 장치 모드(광고 중)인지 여부
  var connectionState = 'DISCONNECTED'.obs; // 현재 BLE 연결 상태
  var scanResults = <BleDevice>[].obs;  // 스캔된 주변 기기 리스트
  var messages = <ChatMessage>[].obs;   // 주고받은 채팅 메시지 리스트
  var connectedDevice = Rxn<BleDevice>(); // 현재 연결된 상대방 기기 정보

  // 스트림 구독 해제를 위한 객체들
  StreamSubscription? _scanSub;
  StreamSubscription? _connSub;
  StreamSubscription? _msgSub;
  StreamSubscription? _errSub;

  @override
  void onInit() {
    super.onInit();
    AppLogger.info('ChatController 초기화', tag: 'ChatController');
    // 앱 생명주기(백그라운드/포그라운드) 감지 등록
    WidgetsBinding.instance.addObserver(this);
    // 앱 시작 시 네이티브로부터의 이벤트 스트림 구독 시작
    _setupStreams();
  }

  @override
  void onClose() {
    AppLogger.info('ChatController 종료', tag: 'ChatController');
    WidgetsBinding.instance.removeObserver(this);
    // 컨트롤러 소멸 시 모든 스트림 구독 해제 (메모리 누수 방지)
    _scanSub?.cancel();
    _connSub?.cancel();
    _msgSub?.cancel();
    _errSub?.cancel();
    super.onClose();
  }

  /// 앱 생명주기 상태 변경 감지 (백그라운드/포그라운드)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused) {
      AppLogger.warn('앱이 백그라운드로 전환됨 (BLE 스캔이 제한될 수 있음)', tag: 'Lifecycle');
    } else if (state == AppLifecycleState.resumed) {
      AppLogger.info('앱이 포그라운드로 복귀함', tag: 'Lifecycle');
    }
  }

  /// 네이티브에서 전달되는 실시간 이벤트들을 구독하여 컨트롤러 상태에 반영
  void _setupStreams() {
    // 1. 연결 상태 변경 구독
    _connSub = _bleManager.connectionStream.listen((event) {
      if (event is Map) {
        final state = event['state'] ?? 'UNKNOWN';
        final deviceId = event['deviceId'] ?? 'Unknown';
        final role = event['role'] ?? 'UNKNOWN'; // 네이티브에서 보낸 역할 정보
        connectionState.value = state;
        
        AppLogger.info('연결 상태 변경: $state (DeviceId: $deviceId, Role: $role)', tag: 'ChatController');

        if (connectionState.value == 'CONNECTED') {
          if (role == 'PERIPHERAL') {
            // [중요] 내가 직접 연결을 시도한 기기라면 다이얼로그를 띄우지 않음 (중복 방지)
            if (connectedDevice.value != null && connectedDevice.value!.id == deviceId) {
              AppLogger.info('내가 시도한 연결(Central)에 대한 중복 이벤트이므로 다이얼로그를 생략합니다.', tag: 'ChatController');
              return;
            }
            
            // 순수하게 연결을 받은 경우에만 승인 다이얼로그 표시
            Future.delayed(const Duration(milliseconds: 500), () {
              _showConnectionApprovalDialog(deviceId);
            });
          } else if (role == 'CENTRAL') {
            // 내가 시도해서 성공한 연결인 경우 -> 즉시 채팅방 진입
            AppLogger.info('Central 모드: 채팅방으로 진입합니다.', tag: 'ChatController');
            Get.toNamed('/chat');
          }
        } else if (connectionState.value == 'DISCONNECTED') {
          _handleDisconnection();
        }
      }
    });

    // 2. 스캔 결과 업데이트 구독
    _scanSub = _bleManager.scanResultsStream.listen((event) {
      if (event is List) {
        for (var item in event) {
          try {
            var newDevice = BleDevice.fromMap(item);
            // 중복 기기 체크 후 리스트 업데이트
            int index = scanResults.indexWhere((d) => d.id == newDevice.id);
            if (index != -1) {
              scanResults[index] = newDevice;
            } else {
              AppLogger.debug('새로운 기기 발견: ${newDevice.name} (${newDevice.id})', tag: 'ChatController');
              scanResults.add(newDevice);
            }
          } catch (e) {
            AppLogger.error('기기 정보 파싱 실패', tag: 'ChatController', error: e);
          }
        }
      }
    });

    // 3. 수신 메시지 구독
    _msgSub = _bleManager.messagesStream.listen((event) {
      if (event is Map) {
        final String content = (event['content'] ?? '').toString().trim();
        final String sender = (event['sender'] ?? 'Unknown');
        
        AppLogger.debug('📩 메시지 수신됨: "$content" (길이: ${content.length})', tag: 'ChatController');

        // [시스템 신호 처리] 거절 신호 감지 (20바이트 미만의 짧은 신호 사용)
        if (content.startsWith('SIG_REJECT')) {
          AppLogger.warn('✅ 거절 시스템 신호 일치 확인! 연결 해제 로직 실행', tag: 'ChatController');
          
          // 1. 즉시 연결 해제
          _bleManager.disconnect(); 
          
          // 2. UI 알림
          if (connectionState.value == 'CONNECTED') {
            Get.snackbar('연결 거절', '상대방이 연결 요청을 거절했습니다.', 
              backgroundColor: Colors.orange, snackPosition: SnackPosition.BOTTOM);
          }
          
          // 3. 로딩 중일 경우 닫기
          if (Get.isDialogOpen == true) Get.back();
          return;
        }

        AppLogger.info('📩 일반 메시지로 판단되어 리스트에 추가합니다.', tag: 'ChatController');
        
        try {
          // 수신된 메시지를 리스트에 추가 (상대방 메시지이므로 isMe = false)
          messages.add(ChatMessage.fromMap(event, isMe: false));
        } catch (e) {
          AppLogger.error('메시지 파싱 실패', tag: 'ChatController', error: e);
        }
      }
    });
  }

  /// [Peripheral 전용] 연결 수락/거절 다이얼로그
  void _showConnectionApprovalDialog(String deviceId) {
    AppLogger.debug('승인 다이얼로그 출력 시도 (현재 Open 여부: ${Get.isDialogOpen})', tag: 'ChatController');
    
    if (Get.isDialogOpen == true) {
      AppLogger.warn('이미 다이얼로그가 열려 있어 무시합니다.', tag: 'ChatController');
      return;
    }

    Get.dialog(
      AlertDialog(
        title: const Text('연결 요청'),
        content: Text('상대방($deviceId)으로부터 대화 요청이 왔습니다.\n수락하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () async {
              const signal = 'SIG_REJECT'; // 짧은 신호로 변경
              AppLogger.info('거절 버튼 클릭: 신호 전송 시작 ("$signal")', tag: 'ChatController');
              
              // 1. 신호 전송
              await _bleManager.sendMessage(signal);
              
              // 2. 다이얼로그 닫기
              if (Get.isDialogOpen == true) Get.back(); 
              
              // 3. 전송 시간을 충분히 고려하여 2초 후 실제 연결 해제
              // (너무 빨리 끊으면 전송 큐에 있는 SIG_REJECT가 유실됨)
              AppLogger.debug('2초 후 연결 해제 대기 중 (신호 전달 보장)...', tag: 'ChatController');
              Future.delayed(const Duration(seconds: 2), () async {
                AppLogger.warn('Peripheral 모드: disconnect() 호출하여 물리적 연결 종료', tag: 'ChatController');
                await _bleManager.disconnect(); 
                
                // [중요] 거절 후에도 주변 장치 모드 스위치가 켜져 있다면 광고를 다시 시작함
                if (isPeripheralMode.value) {
                  AppLogger.info('거절 처리 완료: 광고를 다시 시작합니다.', tag: 'ChatController');
                  // 약간의 추가 지연 후 광고 재개 (하드웨어 안정화 시간)
                  await Future.delayed(const Duration(milliseconds: 500));
                  await _bleManager.startPeripheralMode();
                }
              });
            },
            child: const Text('거절', style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () {
              AppLogger.info('사용자가 연결을 수락했습니다.', tag: 'ChatController');
              
              // 상대방 기기 정보 저장 (이름을 알 수 없으므로 ID로 대체)
              connectedDevice.value = BleDevice(id: deviceId, name: '상대방($deviceId)', rssi: 0);
              
              if (Get.isDialogOpen == true) Get.back(); 
              Get.toNamed('/chat'); 
            },
            child: const Text('수락'),
          ),
        ],
      ),
      barrierDismissible: false,
    );
  }

  /// 연결 해제 시 내부 상태 초기화 및 UI 정리
  void _handleDisconnection() {
    AppLogger.warn('연결 해제 처리 시작 (현재 경로: ${Get.currentRoute})', tag: 'ChatController');
    
    // 1. 모든 다이얼로그/로딩창 강제 종료 (스택이 빌 때까지)
    while (Get.isDialogOpen == true) {
      Get.back();
    }

    // 2. 상태 초기화
    connectionState.value = 'DISCONNECTED';
    connectedDevice.value = null;
    messages.clear();
    
    // 3. 채팅 화면 탈출 로직
    // 안드로이드/iOS 라우트 명칭 차이를 고려하여 '/chat'과 'ChatPage' 모두 체크
    final currentRoute = Get.currentRoute;
    if (currentRoute.contains('chat') || currentRoute.contains('ChatPage')) {
      AppLogger.info('채팅 페이지 탈출 시도 (from $currentRoute)', tag: 'ChatController');
      // 스캔 페이지가 나올 때까지 또는 루트까지 모든 화면을 닫음
      Get.until((route) => Get.currentRoute == '/scan' || Get.currentRoute == '/');
    }
    
    // 4. 광고 모드 복구 (Peripheral 모드일 때만)
    if (isPeripheralMode.value) {
       AppLogger.info('연결 해제 감지: 광고 모드 재활성화 확인', tag: 'ChatController');
       _bleManager.startPeripheralMode(); 
    }

    Get.snackbar(
      '연결 종료', 
      '블루투스 연결이 해제되었습니다.', 
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.blueGrey.withValues(alpha: 0.7),
      colorText: Colors.white
    );
  }

  // --- 사용자 액션 (UI에서 호출) ---

  /// 블루투스 사용에 필요한 OS 권한 요청 및 결과 로깅
  Future<void> requestPermissions() async {
    AppLogger.info('OS 권한 요청 시작', tag: 'ChatController');
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.bluetooth, // iOS 호환성을 위해 추가
      Permission.location,
    ].request();

    // 권한 요청 결과 상세 로깅
    statuses.forEach((permission, status) {
      if (status.isDenied || status.isPermanentlyDenied) {
        AppLogger.warn('권한 거부됨: $permission ($status)', tag: 'Permissions');
      } else {
        AppLogger.debug('권한 허용됨: $permission', tag: 'Permissions');
      }
    });
  }

  /// 스캔 시작/중지 토글
  Future<void> toggleScan() async {
    if (isScanning.value) {
      AppLogger.info('사용자 액션: 스캔 중지', tag: 'ChatController');
      await _bleManager.stopScan();
      isScanning.value = false;
    } else {
      AppLogger.info('사용자 액션: 스캔 시작', tag: 'ChatController');
      await requestPermissions();
      bool success = await _bleManager.startScan();
      
      if (success) {
        scanResults.clear();
        isScanning.value = true;
      }
    }
  }

  /// 주변 장치 모드(광고) 시작/중지 토글
  Future<void> togglePeripheralMode() async {
    if (isPeripheralMode.value) {
      AppLogger.info('사용자 액션: 주변 장치 모드 중지', tag: 'ChatController');
      await _bleManager.stopPeripheralMode();
      isPeripheralMode.value = false;
    } else {
      AppLogger.info('사용자 액션: 주변 장치 모드 시작 시도', tag: 'ChatController');
      // 권한 요청
      await requestPermissions();
      
      bool isAllowed = false;
      if (Platform.isIOS) {
        // iOS는 기본 블루투스 권한만 확인
        isAllowed = await Permission.bluetooth.isGranted;
      } else {
        // 안드로이드는 연결 및 광고 권한 확인
        isAllowed = await Permission.bluetoothConnect.isGranted && 
                    await Permission.bluetoothAdvertise.isGranted;
      }

      if (isAllowed) {
        bool success = await _bleManager.startPeripheralMode();
        if (success) {
          isPeripheralMode.value = true;
        }
      } else {
        AppLogger.warn('권한 거부로 인해 주변 장치 모드를 시작할 수 없음', tag: 'ChatController');
        Get.snackbar(
          '권한 부족', 
          '주변 장치 모드를 시작하려면 블루투스 권한이 필요합니다.',
          backgroundColor: Colors.orange,
          snackPosition: SnackPosition.BOTTOM
        );
      }
    }
  }

  /// 특정 기기에 연결 시도
  Future<void> connectToDevice(BleDevice device) async {
    AppLogger.info('사용자 액션: 기기 연결 시도 -> ${device.name}', tag: 'ChatController');
    // 연결 전 권한 확인 (Android 12+ 대응)
    await requestPermissions();
    
    bool isAllowed = false;
    if (Platform.isIOS) {
      isAllowed = await Permission.bluetooth.isGranted;
    } else {
      isAllowed = await Permission.bluetoothConnect.isGranted;
    }

    if (isAllowed) {
      bool success = await _bleManager.connect(device.id);
      if (success) {
        connectedDevice.value = device;
        await _bleManager.stopScan(); // 연결 성공 시 스캔 중지
        isScanning.value = false;
      }
    } else {
      AppLogger.warn('연결 권한 없음', tag: 'ChatController');
      Get.snackbar('권한 오류', '블루투스 연결 권한이 필요합니다.', 
        backgroundColor: Colors.orange, snackPosition: SnackPosition.BOTTOM);
    }
  }

  /// 채팅 메시지 전송
  Future<void> sendMessage(String text) async {
    if (text.isEmpty) return;
    
    AppLogger.info('사용자 액션: 메시지 전송 시도 -> "$text"', tag: 'ChatController');
    bool success = await _bleManager.sendMessage(text);
    if (success) {
      AppLogger.debug('메시지 전송 성공 확인 (UI 업데이트)', tag: 'ChatController');
      // 전송 성공 시 화면에 내 메시지로 추가
      messages.add(ChatMessage(
        sender: 'Me',
        content: text,
        timestamp: DateTime.now(),
        isMe: true,
      ));
    } else {
      AppLogger.error('메시지 전송 실패', tag: 'ChatController');
    }
  }

  /// 연결 해제
  Future<void> disconnect() async {
    AppLogger.info('사용자 액션: 연결 해제 시도', tag: 'ChatController');
    await _bleManager.disconnect();
    connectedDevice.value = null;
  }
}

