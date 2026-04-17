import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:worker_app/main.dart';

void main() {
  testWidgets('Worker splash shows title', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: WorkerApp()));
    expect(find.text('RidDev Worker'), findsOneWidget);
  });
}
