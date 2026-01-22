package com.example.healthnyou_ble_chat

import android.bluetooth.*
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.util.Log
import io.flutter.plugin.common.EventChannel
import java.util.*

/**
 * Android 주변 장치 매니저 (UUID: FF01, FF02)
 */
class BlePeripheralManager(private val context: Context) {
    private val TAG = "BLE_DEBUG_AOS"

    companion object {
        // UUID 복구 (일부 안드로이드 스택에서 더 안정적일 수 있음)
        val SERVICE_UUID: UUID = UUID.fromString("0000FF01-0000-1000-8000-00805f9b34fb")
        val CHARACTERISTIC_UUID: UUID = UUID.fromString("0000FF02-0000-1000-8000-00805f9b34fb")
    }

    private var bluetoothManager: BluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    private var bluetoothAdapter: BluetoothAdapter? = bluetoothManager.adapter
    private var gattServer: BluetoothGattServer? = null
    private var connectedDevices = mutableSetOf<BluetoothDevice>()

    var messageSink: EventChannel.EventSink? = null
    var connectionSink: EventChannel.EventSink? = null
    var errorSink: EventChannel.EventSink? = null

    fun startPeripheral(): Boolean {
        if (bluetoothAdapter == null || !bluetoothAdapter!!.isEnabled) {
            Log.e(TAG, "블루투스 미활성화 상태")
            return false
        }
        gattServer = bluetoothManager.openGattServer(context, gattServerCallback)
        val service = BluetoothGattService(SERVICE_UUID, BluetoothGattService.SERVICE_TYPE_PRIMARY)
        val characteristic = BluetoothGattCharacteristic(
            CHARACTERISTIC_UUID,
            BluetoothGattCharacteristic.PROPERTY_WRITE or 
            BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE or 
            BluetoothGattCharacteristic.PROPERTY_NOTIFY,
            BluetoothGattCharacteristic.PERMISSION_WRITE
        )
        service.addCharacteristic(characteristic)
        gattServer?.addService(service)
        startAdvertising()
        return true
    }

    private fun startAdvertising() {
        val advertiser = bluetoothAdapter?.bluetoothLeAdvertiser
        
        // 설정 강화: 전송 파워 높임
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .setConnectable(true)
            .build()
            
        // 메인 패킷: 서비스 UUID 포함
        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(true) // 메인 패킷에도 이름 포함 시도 (공간 부족 시 자동 조정됨)
            .addServiceUuid(ParcelUuid(SERVICE_UUID))
            .build()
            
        // 스캔 응답: 추가 정보 없음 (메인에 집중)
        // 만약 메인 패킷이 너무 커서 실패하면 분리해야 함
        val scanResponse = AdvertiseData.Builder()
            .build()
            
        Log.d(TAG, "광고 시작 요청: UUID=$SERVICE_UUID (Power: HIGH)")
        advertiser?.startAdvertising(settings, data, scanResponse, advertiseCallback)
    }

    fun stopPeripheral() {
        Log.d(TAG, "Peripheral 모드 중지")
        connectionSink?.success(mapOf("state" to "DISCONNECTED", "deviceId" to "ALL"))
        bluetoothAdapter?.bluetoothLeAdvertiser?.stopAdvertising(advertiseCallback)
        gattServer?.clearServices()
        gattServer?.close()
        gattServer = null
        connectedDevices.clear()
    }

    fun sendMessage(message: String): Boolean {
        val service = gattServer?.getService(SERVICE_UUID)
        val characteristic = service?.getCharacteristic(CHARACTERISTIC_UUID)
        if (characteristic != null) {
            characteristic.value = message.toByteArray()
            Log.d(TAG, "AOS [Peripheral] 메시지 전송 시도: $message (${connectedDevices.size}대 기기)")
            
            var allSuccess = true
            connectedDevices.forEach { device ->
                val success = gattServer?.notifyCharacteristicChanged(device, characteristic, false) ?: false
                Log.d(TAG, " -> 기기(${device.address}) 전송 결과: $success")
                if (!success) allSuccess = false
            }
            return allSuccess
        }
        Log.e(TAG, "전송 실패: 캐릭터리스틱을 찾을 수 없음")
        return false
    }

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) { Log.d(TAG, "광고 시작 성공") }
        override fun onStartFailure(errorCode: Int) { Log.e(TAG, "광고 실패: $errorCode") }
    }

    private val gattServerCallback = object : BluetoothGattServerCallback() {
        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            Log.d(TAG, "Peripheral 연결 상태 변경: $status -> $newState (${device.address})")
            Handler(Looper.getMainLooper()).post {
                if (newState == BluetoothProfile.STATE_CONNECTED) {
                    connectedDevices.add(device)
                    connectionSink?.success(mapOf(
                        "state" to "CONNECTED", 
                        "deviceId" to device.address,
                        "role" to "PERIPHERAL" // 역할 추가
                    ))
                } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                    connectedDevices.remove(device)
                    connectionSink?.success(mapOf(
                        "state" to "DISCONNECTED", 
                        "deviceId" to device.address,
                        "role" to "PERIPHERAL" // 역할 추가
                    ))
                }
            }
        }

        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice, requestId: Int, characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray
        ) {
            val msg = String(value)
            Log.d(TAG, "AOS [Peripheral] Write 요청 수신 (UUID: ${characteristic.uuid}, ResponseNeeded: $responseNeeded): $msg")
            
            if (responseNeeded) {
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value)
            }
            
            // 정확한 UUID 매칭 확인
            if (characteristic.uuid.toString().equals(CHARACTERISTIC_UUID.toString(), ignoreCase = true)) {
                Handler(Looper.getMainLooper()).post {
                    messageSink?.success(mapOf(
                        "sender" to device.address, 
                        "content" to msg, 
                        "timestamp" to System.currentTimeMillis()
                    ))
                }
            } else {
                Log.w(TAG, " -> 무시됨 (UUID 불일치)")
            }
        }
    }
}
