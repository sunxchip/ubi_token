import 'package:flutter_test/flutter_test.dart';
import 'package:ubi_token/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const UbiTokenApp());
    // SplashScreen에 2초 타이머가 있으므로 그 이상 시간을 진행시켜 타이머를 소진한다.
    await tester.pump(const Duration(seconds: 3));
  });
}
