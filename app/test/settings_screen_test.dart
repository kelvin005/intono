import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intono_app/src/settings_screen.dart';

// Settings (ADR 0015 decision 9): "Clear history" deletes every session only after a confirmation. Written before the screen.

Widget host(Widget w) => Directionality(textDirection: TextDirection.ltr, child: w);

void main() {
  late int cleared;
  late int closed;
  Widget screen({Future<void> Function()? onClear}) => host(SettingsScreen(
        onClearHistory: onClear ?? () async => cleared++,
        onClose: () => closed++,
      ));

  setUp(() {
    cleared = 0;
    closed = 0;
  });

  testWidgets('Clear history asks first; Cancel keeps the history', (t) async {
    await t.pumpWidget(screen());
    await t.tap(find.text('Clear history'));
    await t.pump();
    expect(find.textContaining('cannot be undone'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pump();
    expect(cleared, 0);
    expect(find.textContaining('cannot be undone'), findsNothing);
  });

  testWidgets('confirming deletes the history once and says so', (t) async {
    await t.pumpWidget(screen());
    await t.tap(find.text('Clear history'));
    await t.pump();
    await t.tap(find.text('Delete all history'));
    await t.pump();
    await t.pump();
    expect(cleared, 1);
    expect(find.text('Practice history cleared.'), findsOneWidget);
  });

  testWidgets('a failure is reported, not hidden', (t) async {
    await t.pumpWidget(screen(onClear: () async => throw StateError('locked')));
    await t.tap(find.text('Clear history'));
    await t.pump();
    await t.tap(find.text('Delete all history'));
    await t.pump();
    await t.pump();
    expect(find.textContaining('could not be cleared'), findsOneWidget);
  });

  testWidgets('Back closes the screen', (t) async {
    await t.pumpWidget(screen());
    await t.tap(find.text('Back'));
    expect(closed, 1);
  });
}
