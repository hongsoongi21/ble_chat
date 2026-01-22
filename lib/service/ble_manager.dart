import 'dart:async';
import 'package:flutter/services.dart';
import '../util/logger.dart';

/// 네이티브 플랫폼(Android/iOS)의 BLE 기능과 통신을 담당하는 서비스 클래스
class BleManager {
  // --- 채널 정의 ---
  // 명령을 전달하고 즉각적인 결과를 받는 Method Channel
  static const MethodChannel _methodChannel = MethodChannel('kr.co.thejoin.ble_chat/methods');

  // 네이티브에서 발생하는 비동기 이벤트(연결 상태, 메시지 수신 등)를 실시간으로 받는 Event Channels
  static const EventChannel _connectionChannel = EventChannel('ble_chat/connection');
  static const EventChannel _scanResultsChannel = EventChannel('ble_chat/scan_results');
  static const EventChannel _messagesChannel = EventChannel('ble_chat/messages');
  static const EventChannel _errorsChannel = EventChannel('ble_chat/errors');

  // 싱글톤 패턴 적용: 앱 전체에서 하나의 인스턴스만 공유
  static final BleManager _instance = BleManager._internal();
  factory BleManager() => _instance;
  BleManager._internal();

  // --- Method Channel 메서드 호출 (Flutter -> Native) ---

  /// 주변 장치(Peripheral) 모드 시작 (GATT 서버 및 광고 시작)
  Future<bool> startPeripheralMode() async {
    try {
      final bool result = await _methodChannel.invokeMethod('startPeripheralMode');
      AppLogger.info('주변 장치 모드 시작됨', tag: 'BleManager');
      return result;
    } catch (e) {
      AppLogger.error('주변 장치 모드 시작 오류', tag: 'BleManager', error: e);
      return false;
    }
  }

  /// 주변 장치 모드 중지
  Future<bool> stopPeripheralMode() async {
    try {
      final bool result = await _methodChannel.invokeMethod('stopPeripheralMode');
      AppLogger.info('주변 장치 모드 중지됨', tag: 'BleManager');
      return result;
    } catch (e) {
      AppLogger.error('주변 장치 모드 중지 오류', tag: 'BleManager', error: e);
      return false;
    }
  }

  /// 주변 BLE 기기 스캔 시작
  Future<bool> startScan() async {
    try {
      final bool result = await _methodChannel.invokeMethod('startScan');
      AppLogger.info('BLE 스캔 시작 요청', tag: 'BleManager');
      return result;
    } catch (e) {
      AppLogger.error('스캔 시작 오류', tag: 'BleManager', error: e);
      return false;
    }
  }

  /// 스캔 중지
  Future<bool> stopScan() async {
    try {
      final bool result = await _methodChannel.invokeMethod('stopScan');
      AppLogger.info('BLE 스캔 중지 요청', tag: 'BleManager');
      return result;
    } catch (e) {
      AppLogger.error('스캔 중지 오류', tag: 'BleManager', error: e);
      return false;
    }
  }

  /// 특정 디바이스 ID로 연결 시도 (Central 역할)
  Future<bool> connect(String deviceId) async {
    try {
      AppLogger.info('기기 연결 시도: $deviceId', tag: 'BleManager');
      final bool result = await _methodChannel.invokeMethod('connect', {'deviceId': deviceId});
      return result;
    } catch (e) {
      AppLogger.error('기기 연결 오류 ($deviceId)', tag: 'BleManager', error: e);
      return false;
    }
  }

  /// 현재 연결된 기기와 연결 해제
  Future<bool> disconnect() async {
    try {
      final bool result = await _methodChannel.invokeMethod('disconnect');
      AppLogger.info('연결 해제 요청', tag: 'BleManager');
      return result;
    } catch (e) {
      AppLogger.error('연결 해제 오류', tag: 'BleManager', error: e);
      return false;
    }
  }

  /// 상대방에게 채팅 메시지 전송 (GATT Write 수행)
  Future<bool> sendMessage(String message) async {
    try {
      final bool result = await _methodChannel.invokeMethod('sendMessage', {'message': message});
      AppLogger.debug('메시지 전송 성공 여부: $result ("$message")', tag: 'BleManager');
      return result;
    } catch (e) {
      AppLogger.error('메시지 전송 오류', tag: 'BleManager', error: e);
      return false;
    }
  }

  /// 현재 BLE 연결 상태 조회
  Future<String> getConnectionState() async {
    try {
      final String state = await _methodChannel.invokeMethod('getConnectionState');
      return state;
    } catch (e) {
      AppLogger.error('연결 상태 조회 오류', tag: 'BleManager', error: e);
      return 'UNKNOWN';
    }
  }

  // --- Event Channel 스트림 (Native -> Flutter) ---

  /// 연결 상태 변경 알림 스트림
  Stream<dynamic> get connectionStream => _connectionChannel.receiveBroadcastStream();
  
  /// 스캔된 기기 리스트 스트림
  Stream<dynamic> get scanResultsStream => _scanResultsChannel.receiveBroadcastStream();
  
  /// 수신된 메시지 스트림
  Stream<dynamic> get messagesStream => _messagesChannel.receiveBroadcastStream();
  
  /// 오류 발생 알림 스트림
  Stream<dynamic> get errorStream => _errorsChannel.receiveBroadcastStream();
}
