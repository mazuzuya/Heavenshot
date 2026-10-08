import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heavenshot/game/game.dart';
import 'package:heavenshot/main.dart';

Future<HeavenshotGame> _pumpWithControls(WidgetTester tester) async {
  await tester.pumpWidget(const HeavenshotApp());
  final game = tester.widget<GameScreen>(find.byType(GameScreen)).game;
  // Kontrol disembunyikan saat toko terbuka di awal; tampilkan untuk test.
  game.hudVisible.value = true;
  await tester.pump();
  return game;
}

void main() {
  testWidgets('Heavenshot app builds', (WidgetTester tester) async {
    await _pumpWithControls(tester);
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byKey(const Key('movement-joystick')), findsOneWidget);
    expect(find.byKey(const Key('jump-button')), findsOneWidget);
    for (int i = 0; i < 4; i++) {
      expect(find.byKey(Key('arrow-button-$i')), findsOneWidget);
    }
  });

  testWidgets('arrow buttons and jump drive the input controller', (
    WidgetTester tester,
  ) async {
    final game = await _pumpWithControls(tester);

    await tester.tap(find.byKey(const Key('arrow-button-2')));
    expect(game.input.arrowRequest, 2);

    final jump = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('jump-button'))),
    );
    await tester.pump();
    expect(game.input.jump, isTrue);
    expect(game.input.jumpPressed, isTrue);
    await jump.up();
    await tester.pump();
    expect(game.input.jump, isFalse);
  });

  testWidgets('movement joystick drives and releases horizontal input', (
    WidgetTester tester,
  ) async {
    final game = await _pumpWithControls(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('movement-joystick'))),
    );

    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    expect(game.input.right, isTrue);

    await gesture.up();
    await tester.pump();
    expect(game.input.right, isFalse);
  });
}
