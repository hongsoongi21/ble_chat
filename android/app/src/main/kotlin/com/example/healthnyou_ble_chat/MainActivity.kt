package com.example.healthnyou_ble_chat

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/// Flutter와 Android 네이티브 간의 통신을 중재하는 메인 액티비티
class MainActivity : FlutterActivity() {
    private val METHOD_CHANNEL = "kr.co.thejoin.ble_chat/methods"
    
    // Event Channels
    private val CONN_CHANNEL = "ble_chat/connection"
    private val SCAN_CHANNEL = "ble_chat/scan_results"
    private val MSG_CHANNEL = "ble_chat/messages"
    private val ERR_CHANNEL = "ble_chat/errors"

    private var connSink: EventChannel.EventSink? = null
    private var scanSink: EventChannel.EventSink? = null
    private var msgSink: EventChannel.EventSink? = null
    private var errSink: EventChannel.EventSink? = null

    // BLE Managers
    private lateinit var peripheralManager: BlePeripheralManager
    private lateinit var centralManager: BleCentralManager

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 매니저들 초기화
        peripheralManager = BlePeripheralManager(this)
        centralManager = BleCentralManager(this)

        // 1. Method Channel 설정
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startPeripheralMode" -> {
                    val success = peripheralManager.startPeripheral()
                    result.success(success)
                }
                "stopPeripheralMode" -> {
                    peripheralManager.stopPeripheral()
                    result.success(true)
                }
                "startScan" -> {
                    val success = centralManager.startScan()
                    result.success(success)
                }
                "stopScan" -> {
                    centralManager.stopScan()
                    result.success(true)
                }
                "connect" -> {
                    val deviceId = call.argument<String>("deviceId") ?: ""
                    val success = centralManager.connect(deviceId)
                    result.success(success)
                }
                "disconnect" -> {
                    peripheralManager.stopPeripheral()
                    centralManager.disconnect()
                    result.success(true)
                }
                "sendMessage" -> {
                    val message = call.argument<String>("message") ?: ""
                    // 두 매니저 모두에게 전송을 시도 (어느 쪽이든 실제 연결된 쪽에서 전송됨)
                    val pSuccess = peripheralManager.sendMessage(message)
                    val cSuccess = centralManager.sendMessage(message)
                    result.success(pSuccess || cSuccess)
                }
                "getConnectionState" -> {
                    result.success("UNKNOWN")
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        // 2. Event Channels 설정 및 Sink 연결
        setupEventChannel(flutterEngine, CONN_CHANNEL) { 
            connSink = it 
            peripheralManager.connectionSink = it
            centralManager.connectionSink = it
        }
        setupEventChannel(flutterEngine, SCAN_CHANNEL) { 
            scanSink = it 
            centralManager.scanSink = it
        }
        setupEventChannel(flutterEngine, MSG_CHANNEL) { 
            msgSink = it 
            peripheralManager.messageSink = it
            centralManager.messageSink = it
        }
        setupEventChannel(flutterEngine, ERR_CHANNEL) { errSink = it }
    }

    /**
     * EventChannel의 반복적인 설정을 돕는 도우미 메서드
     */
    private fun setupEventChannel(flutterEngine: FlutterEngine, channelName: String, onListen: (EventChannel.EventSink?) -> Unit) {
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    // Flutter에서 스트림을 구독(listen)하기 시작할 때 호출됨
                    onListen(events)
                }
                override fun onCancel(arguments: Any?) {
                    // Flutter에서 스트림 구독을 취소할 때 호출됨
                    onListen(null)
                }
            }
        )
    }
}
