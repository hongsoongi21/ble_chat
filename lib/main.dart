import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'controller/chat_controller.dart';
import 'ui/scan_page.dart';
import 'ui/chat_page.dart';

void main() {
  print('홍순기 앱 가동!');
  // 플러터 엔진과 네이티브 간의 바인딩 초기화 보장
  WidgetsFlutterBinding.ensureInitialized();
  
  // 앱 시작 시 컨트롤러 주입
  Get.put(ChatController());
  
  runApp(const BleChatApp());
}

class BleChatApp extends StatelessWidget {
  const BleChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'HealthNYou BLE Chat',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      debugShowCheckedModeBanner: false,
      // 초기 화면 설정
      home: const ScanPage(),
      // 라우트 등록
      getPages: [
        GetPage(name: '/scan', page: () => const ScanPage()),
        GetPage(name: '/chat', page: () => const ChatPage()),
      ],
    );
  }
}