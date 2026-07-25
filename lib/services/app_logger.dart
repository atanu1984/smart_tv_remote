import 'dart:async';

class AppLogger {
  static final List<String> _logs = [];
  static final StreamController<String> _controller = StreamController<String>.broadcast();

  static List<String> get logs => List.unmodifiable(_logs);
  static Stream<String> get logStream => _controller.stream;

  static void log(String message) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    final formatted = '[$timestamp] $message';
    _logs.add(formatted);
    if (_logs.length > 500) {
      _logs.removeAt(0);
    }
    _controller.add(formatted);
    // Print to stdout for debug mode
    print(formatted);
  }

  static void clear() {
    _logs.clear();
    _controller.add('=== Logs Cleared ===');
  }

  static String getFormattedLogs() {
    return _logs.join('\n');
  }
}
