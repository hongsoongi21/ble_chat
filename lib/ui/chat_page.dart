import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controller/chat_controller.dart';
import 'package:intl/intl.dart';

class ChatPage extends StatelessWidget {
  const ChatPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<ChatController>();
    final TextEditingController textController = TextEditingController();

    return Scaffold(
      appBar: AppBar(
        title: Obx(() => Text(controller.connectedDevice.value?.name ?? 'BLE 채팅')),
        actions: [
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            onPressed: () async {
              // 연결이 되어 있는 경우에만 끊기 시도
              if (controller.connectionState.value == 'CONNECTED') {
                await controller.disconnect();
              }
              // 확실하게 스캔 페이지로 이동
              Get.until((route) => Get.currentRoute == '/scan' || Get.currentRoute == '/');
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 연결 상태 바
          Obx(() => Container(
                width: double.infinity,
                color: controller.connectionState.value == 'CONNECTED' ? Colors.green : Colors.red,
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  controller.connectionState.value,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              )),

          // 메시지 목록
          Expanded(
            child: Obx(() => ListView.builder(
                  padding: const EdgeInsets.all(16),
                  reverse: true, // 최신 메시지가 아래에 오도록
                  itemCount: controller.messages.length,
                  itemBuilder: (context, index) {
                    // 리스트를 뒤집었으므로 인덱스 계산
                    final message = controller.messages[controller.messages.length - 1 - index];
                    return _buildMessageBubble(message);
                  },
                )),
          ),

          // 입력창
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: textController,
                    decoration: const InputDecoration(
                      hintText: '메시지를 입력하세요...',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.blue),
                  onPressed: () {
                    if (textController.text.isNotEmpty) {
                      controller.sendMessage(textController.text);
                      textController.clear();
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(dynamic message) {
    bool isMe = message.isMe;
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isMe ? Colors.blue[100] : Colors.grey[200],
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(isMe ? 12 : 0),
            bottomRight: Radius.circular(isMe ? 0 : 12),
          ),
        ),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(message.content, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 4),
            Text(
              DateFormat('HH:mm').format(message.timestamp),
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
