package com.example.healthnyou_ble_chat

import android.bluetooth.*
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.util.Log
import io.flutter.plugin.common.EventChannel

/**
 * Android 중앙 장치 매니저 (UUID: FF01 필터링 적용)
 */
class BleCentralManager(private val context: Context) {
    private val TAG = "BLE_DEBUG_AOS"

    private val bluetoothManager: BluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    private val bluetoothAdapter: BluetoothAdapter? = bluetoothManager.adapter
    private var bluetoothGatt: BluetoothGatt? = null
    
    var scanSink: EventChannel.EventSink? = null
    var connectionSink: EventChannel.EventSink? = null
    var messageSink: EventChannel.EventSink? = null

    fun startScan(): Boolean {
        val scanner = bluetoothAdapter?.bluetoothLeScanner ?: return false
        
        // 디버깅을 위해 스캔 필터 제거 (모든 기기 검색)
        // val filter = ScanFilter.Builder()
        //    .setServiceUuid(ParcelUuid(BlePeripheralManager.SERVICE_UUID))
        //    .build()
        
        val settings = ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build()
        
        // 필터 없이 스캔 시작 (null 전달)
        scanner.startScan(null, settings, scanCallback)
        Log.d(TAG, "스캔 시작 (필터 없음 - 모든 기기 검색)")
        return true
    }

    fun stopScan() { bluetoothAdapter?.bluetoothLeScanner?.stopScan(scanCallback) }

    fun connect(address: String): Boolean {
        val device = bluetoothAdapter?.getRemoteDevice(address) ?: return false
        bluetoothGatt?.close()
        // autoConnect=false로 설정하여 즉시 연결 시도
        bluetoothGatt = device.connectGatt(context, false, gattCallback)
        Log.d(TAG, "연결 시도: $address")
        return true
    }

    fun disconnect() {
        bluetoothGatt?.let {
            Handler(Looper.getMainLooper()).post { connectionSink?.success(mapOf("state" to "DISCONNECTED", "deviceId" to it.device.address)) }
            it.disconnect()
            it.close()
        }
        bluetoothGatt = null
        Log.d(TAG, "연결 해제 요청됨")
    }

    fun sendMessage(message: String): Boolean {
        val gatt = bluetoothGatt ?: return false
        val service = gatt.getService(BlePeripheralManager.SERVICE_UUID)
        if (service == null) {
            Log.e(TAG, "전송 실패: 서비스를 찾을 수 없음")
            return false
        }
        val characteristic = service.getCharacteristic(BlePeripheralManager.CHARACTERISTIC_UUID)
        if (characteristic == null) {
            Log.e(TAG, "전송 실패: 캐릭터리스틱을 찾을 수 없음")
            return false
        }
        
        characteristic.value = message.toByteArray()
        characteristic.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        
        val success = gatt.writeCharacteristic(characteristic)
        Log.d(TAG, "AOS [Central] 메시지 전송 요청: '$message', 결과: $success")
        return success
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val deviceName = result.scanRecord?.deviceName ?: result.device.name ?: "이름 없음"
            
            // HealthNYou 관련 기기만 로그 출력 및 UI 전달 (이름으로 1차 필터링)
            // iOS BlePeripheralManager.swift에서 설정한 이름: "HealthNYou-Chat"
            
            // 모든 기기 로그 출력 (디버깅용)
            // Log.d(TAG, "스캔됨: $deviceName (${result.device.address})")

            val uuids = result.scanRecord?.serviceUuids
            if (uuids != null && uuids.isNotEmpty()) {
                 Log.d(TAG, "Device: $deviceName, UUIDs: $uuids")
            }

            // 이름이 일치하거나, 우리가 찾는 UUID를 포함하는 경우에만 리스트에 추가
            val targetUuid = ParcelUuid(BlePeripheralManager.SERVICE_UUID)
            val isTarget = (uuids != null && uuids.contains(targetUuid)) || deviceName.contains("HealthNYou")
            
            if (isTarget) {
                 Log.d(TAG, ">>> 타겟 기기 발견: $deviceName, $uuids")
                 val deviceInfo = mapOf("id" to result.device.address, "name" to deviceName, "rssi" to result.rssi)
                 Handler(Looper.getMainLooper()).post { scanSink?.success(listOf(deviceInfo)) }
            }
        }
    }

    private val gattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            Log.d(TAG, "Central 연결 상태 변경: $status -> $newState")
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                // [추가] MTU 확장 요청 (최대 512바이트)
                Log.d(TAG, "MTU 확장 요청 시작 (512)")
                gatt.requestMtu(512)
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                Handler(Looper.getMainLooper()).post { connectionSink?.success(mapOf("state" to "DISCONNECTED", "deviceId" to gatt.device.address, "role" to "CENTRAL")) }
                gatt.close()
                bluetoothGatt = null
            }
        }

        override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
            super.onMtuChanged(gatt, mtu, status)
            Log.d(TAG, "MTU 변경 완료: $mtu (Status: $status)")
            // MTU 설정이 완료된 후 서비스 탐색 시작
            gatt.discoverServices()
            
            Handler(Looper.getMainLooper()).post { 
                connectionSink?.success(mapOf(
                    "state" to "CONNECTED", 
                    "deviceId" to gatt.device.address,
                    "role" to "CENTRAL"
                )) 
            }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            if (status == BluetoothGatt.GATT_SUCCESS) {
                Log.d(TAG, "서비스 발견 성공")
                val service = gatt.getService(BlePeripheralManager.SERVICE_UUID)
                val characteristic = service?.getCharacteristic(BlePeripheralManager.CHARACTERISTIC_UUID)
                if (characteristic != null) {
                    gatt.setCharacteristicNotification(characteristic, true)
                    val descriptor = characteristic.getDescriptor(java.util.UUID.fromString("00002902-0000-1000-8000-00805f9b34fb"))
                    descriptor.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                    gatt.writeDescriptor(descriptor)
                    Log.d(TAG, "Notification 활성화 완료")
                }
            } else {
                Log.e(TAG, "서비스 발견 실패: $status")
            }
        }
        
        // 메시지 전송 결과 확인용 콜백 추가
        override fun onCharacteristicWrite(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) {
            super.onCharacteristicWrite(gatt, characteristic, status)
            if (status == BluetoothGatt.GATT_SUCCESS) {
                Log.d(TAG, "AOS [Central] 쓰기(Write) 성공")
            } else {
                Log.e(TAG, "AOS [Central] 쓰기 실패: $status")
            }
        }

        override fun onCharacteristicChanged(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
            // UUID 정확한 비교
            if (characteristic.uuid == BlePeripheralManager.CHARACTERISTIC_UUID) {
                val msg = String(characteristic.value)
                Log.d(TAG, "AOS [Central] Notification 수신: $msg")
                Handler(Looper.getMainLooper()).post { messageSink?.success(mapOf("sender" to gatt.device.address, "content" to msg, "timestamp" to System.currentTimeMillis())) }
            }
        }
    }
}
