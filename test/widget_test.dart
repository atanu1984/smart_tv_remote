import 'package:flutter_test/flutter_test.dart';
import 'package:smart_tv_remote/main.dart';

void main() {
  testWidgets('App renders main screen smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const SmartTvRemoteApp());
    await tester.pump();
    expect(find.text('Smart TV Remote'), findsOneWidget);
  });
}

