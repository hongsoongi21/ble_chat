import 'dart:developer' as developer;

class AppLogger {
  // 로그 레벨 활성화 여부 (배포 시 debug는 끌 수 있음)
  static bool isDebugEnabled = true;

  /// 🐛 [DEBUG] 상세한 디버깅 정보
  static void debug(String message, {String? tag}) {
    if (!isDebugEnabled) return;
    _log('🐛', 'DEBUG', message, tag);
  }

  /// ℹ️ [INFO] 일반적인 정보 및 흐름
  static void info(String message, {String? tag}) {
    _log('ℹ️', 'INFO', message, tag);
  }

  /// ⚠️ [WARN] 경고, 잠재적인 문제
  static void warn(String message, {String? tag}) {
    _log('⚠️', 'WARN', message, tag);
  }

  /// ❌ [ERROR] 심각한 오류 발생
  static void error(String message, {String? tag, Object? error, StackTrace? stackTrace}) {
    _log('❌', 'ERROR', message, tag);
    if (error != null) {
      developer.log('   Error: $error', name: tag ?? 'AppLogger');
    }
    if (stackTrace != null) {
      developer.log('   Stack: $stackTrace', name: tag ?? 'AppLogger');
    }
  }

  /// 내부 로그 출력 함수
  static void _log(String emoji, String level, String message, String? tag) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 19); // HH:mm:ss
    final tagStr = tag != null ? '[$tag] ' : '';
    
    // print() 대신 developer.log를 사용하면 DevTools에서도 보기 좋게 나옵니다.
    // 하지만 VS Code 디버그 콘솔에서 직관적으로 보려면 print가 나을 때도 있습니다.
    // 여기서는 포맷팅된 문자열을 출력합니다.
    print('$emoji $timestamp [$level] $tagStr$message');
  }
}
