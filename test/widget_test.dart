import 'package:flutter_test/flutter_test.dart';
import 'package:ubi_token/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const UbiTokenApp());
  });
}