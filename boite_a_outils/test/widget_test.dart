// Basic smoke test for the Boîte à Outils home screen.

import 'package:flutter_test/flutter_test.dart';

import 'package:boite_a_outils/main.dart';

void main() {
  testWidgets('Home screen shows the PDF converter tool card',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Convertisseur PDF'), findsOneWidget);

    await tester.tap(find.text('Convertisseur PDF'));
    await tester.pumpAndSettle();

    // Phase 4 reduced the flow to a single primary conversion entry point.
    expect(
      find.text('Convertir un fichier'),
      findsOneWidget,
    );
  });
}
