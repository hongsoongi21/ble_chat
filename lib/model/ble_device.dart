class BleDevice {
  final String id;
  final String name;
  final int rssi;

  BleDevice({
    required this.id,
    required this.name,
    required this.rssi,
  });

  factory BleDevice.fromMap(Map<dynamic, dynamic> map) {
    return BleDevice(
      id: map['id'] ?? '',
      name: map['name'] ?? 'Unknown Device',
      rssi: map['rssi'] ?? 0,
    );
  }
}
