import 'package:flutter_test/flutter_test.dart';
import 'package:boxer/main.dart';

void main() {
  testWidgets('Boxer smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const BoxerApp());

    // Verifica presença do título BOXER e logo TerlineT
    expect(find.text('B O X E R'), findsOneWidget);
    expect(find.text('INICIAR LUTA'), findsOneWidget);
    expect(find.text('DESFERIR GOLPE'), findsNothing);
  });
}
