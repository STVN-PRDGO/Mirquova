import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirquova/ui/launch_intro.dart';

void main() {
  Widget app({bool reduceMotion = false}) => MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: MaterialApp(
      builder: (context, child) => LaunchIntro(child: child!),
      home: Scaffold(
        body: Center(
          child: TextButton(onPressed: () {}, child: const Text('Behind')),
        ),
      ),
    ),
  );

  testWidgets('plays the brand intro, then leaves only the app', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('Mirquova'), findsOneWidget);
    expect(find.text('Every screen. One connection.'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Mirquova'), findsNothing);
    expect(find.text('Behind'), findsOneWidget);
  });

  testWidgets('skips the intro when animations are reduced', (tester) async {
    await tester.pumpWidget(app(reduceMotion: true));
    await tester.pump();
    expect(find.text('Mirquova'), findsNothing);
  });

  testWidgets('never blocks taps on the app underneath', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => LaunchIntro(child: child!),
        home: Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => taps++,
              child: const Text('Behind'),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Behind'), warnIfMissed: false);
    expect(taps, 1);
    await tester.pumpAndSettle();
  });
}
