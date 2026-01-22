import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controller/chat_controller.dart';
import '../util/logger.dart';
import 'chat_page.dart';

class ScanPage extends StatelessWidget {
  const ScanPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<ChatController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('BLE 채팅 스캔'),
        actions: [
          // 현재 연결 상태 표시
          Obx(() => Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(
                    controller.connectionState.value,
                    style: TextStyle(
                      color: controller.connectionState.value == 'CONNECTED'
                          ? Colors.greenAccent
                          : Colors.redAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              )),
        ],
      ),
      body: Column(
        children: [
          // 내 기기 설정 섹션 (Peripheral 모드)
          Container(
            padding: const EdgeInsets.all(16.0),
            color: Colors.blueGrey.withOpacity(0.1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('내 기기 설정', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('주변 장치 모드 (광고)'),
                    Obx(() => Switch(
                          value: controller.isPeripheralMode.value,
                          onChanged: (_) => controller.togglePeripheralMode(),
                        )),
                  ],
                ),
              ],
            ),
          ),

          // 스캔 컨트롤 섹션
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('주변 기기 목록', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                Obx(() => ElevatedButton(
                      onPressed: controller.toggleScan,
                      child: Text(controller.isScanning.value ? '스캔 중지' : '기기 스캔'),
                    )),
              ],
            ),
          ),

          // 스캔 결과 목록
          Expanded(
            child: Obx(() {
              if (controller.scanResults.isEmpty) {
                return const Center(child: Text('스캔된 기기가 없습니다.'));
              }
              return ListView.builder(
                itemCount: controller.scanResults.length,
                itemBuilder: (context, index) {
                  final device = controller.scanResults[index];
                  return ListTile(
                    leading: const Icon(Icons.bluetooth),
                    title: Text(device.name),
                    subtitle: Text(device.id),
                    trailing: Text('${device.rssi} dBm'),
                    onTap: () async {
                      AppLogger.info('사용자가 기기 선택: ${device.name}', tag: 'ScanPage');
                      
                      // 로딩 다이얼로그 표시
                      Get.dialog(
                        const Center(child: CircularProgressIndicator()),
                        barrierDismissible: false,
                      );
                      
                      try {
                        // 연결 시도 (네이티브 메서드 호출)
                        await controller.connectToDevice(device);
                        AppLogger.debug('connectToDevice 호출 완료', tag: 'ScanPage');
                      } finally {
                        // 성공/실패 여부와 상관없이 로딩 다이얼로그가 열려있다면 닫음
                        if (Get.isDialogOpen == true) {
                          AppLogger.debug('로딩 다이얼로그 닫기', tag: 'ScanPage');
                          Get.back();
                        }
                      }
                    },
                  );
                },
              );
            }),
          ),
        ],
      ),
      
      // 이미 연결된 경우 채팅방으로 바로 이동하는 버튼 (디버그용)
      floatingActionButton: Obx(() => controller.connectionState.value == 'CONNECTED' 
        ? FloatingActionButton(
            onPressed: () => Get.to(() => const ChatPage()),
            child: const Icon(Icons.chat),
          )
        : Container()),
    );
  }
}
