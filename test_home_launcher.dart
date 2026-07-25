import 'dart:io';
import 'package:http/http.dart' as http;

void main() async {
  const ip = '192.168.0.213';
  print('=== LAUNCHING YOUTUBE VIA DIAL REST PORT 8008 ($ip:8008) ===');

  try {
    final dialUrl = Uri.parse('http://$ip:8008/apps/youtube');
    print('Sending HTTP POST to $dialUrl... Look at your TV screen!');
    final res = await http.post(dialUrl, body: '').timeout(const Duration(seconds: 4));
    print('  TV Response: Status ${res.statusCode}');
    print('  TV Response Headers: ${res.headers}');
  } catch (e) {
    print('  DIAL Error: $e');
  }
}
