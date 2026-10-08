import 'dart:ui';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:heavenshot/game/constants.dart';
import 'package:heavenshot/game/input_state.dart';
import 'package:heavenshot/game/simulation.dart';
import 'package:heavenshot/game/world.dart';

void main() {
  test('arrow keeps the exact pointer aim instead of snapping to an enemy', () {
    final world = World();
    final simulation = Simulation(
      world: world,
      input: InputController(),
      tuning: Tuning(230, 470, 1080, 5.5, 1),
      saved: null,
      events: Events(),
    );
    final enemy = world.enemies.first;
    final player = simulation.state.player;
    final target = Offset(enemy.x + 90, enemy.y + 28);

    simulation.fireArrow(AimTarget(target: target));

    final arrow = simulation.state.arrows.single;
    final dx = target.dx - arrow.x;
    final dy = target.dy - arrow.y;
    final distance = hypot(dx, dy);
    expect(arrow.vx / 820, closeTo(dx / distance, 1e-9));
    expect(arrow.vy / 820, closeTo(dy / distance, 1e-9));
    expect(arrow.x, closeTo(player.x + player.facing * 24, 1e-9));
  });

  test('skin perks are unique and enemy health scales by area', () {
    expect(skins.map((skin) => skin.perk).toSet(), hasLength(skins.length));
    expect(scaledEnemyHp(10, 0), 13);
    expect(scaledEnemyHp(10, 1), 14);
    expect(scaledEnemyHp(10, 19), 32);

    final normal = makeChunk(1).enemies.firstWhere((enemy) => !enemy.miniBoss);
    final normalArea = zoneAt(normal.y);
    expect(normal.hp, scaledEnemyHp(2 + (normalArea / 3).floor(), normalArea));
    final miniBoss = makeChunk(2).enemies.firstWhere((enemy) => enemy.miniBoss);
    final miniArea = miniBoss.zoneIndex!;
    expect(miniBoss.hp, scaledEnemyHp(8 + (miniArea / 2).floor(), miniArea));

    final boss = World().bossSpecs.first;
    expect(boss.hp, scaledEnemyHp(22, 4));
  });

  test('Ember Fox reduces fire energy cost', () {
    final simulation = Simulation(
      world: World(),
      input: InputController(),
      tuning: Tuning(230, 470, 1080, 5.5, 1),
      saved: null,
      events: Events(),
    );
    final player = simulation.state.player
      ..energy = 100
      ..selectedArrow = 1
      ..unlocks.fire = true;
    simulation.state.selectedSkin = 1;

    simulation.fireArrow(AimTarget(direction: const Offset(1, 0)));

    expect(player.energy, closeTo(87.4, 1e-9));
  });

  test('damage decreases the HP value rendered by the HUD', () {
    final simulation = Simulation(
      world: World(),
      input: InputController(),
      tuning: Tuning(230, 470, 1080, 5.5, 1),
      saved: null,
      events: Events(),
    );

    simulation.damagePlayer(900, 'test');

    expect(simulation.state.player.hp, 2);
    expect(simulation.state.player.hearts, 2);
  });

  test('Prism Emperor fires a three-arrow fan every third shot', () {
    final simulation = Simulation(
      world: World(),
      input: InputController(),
      tuning: Tuning(230, 470, 1080, 5.5, 1),
      saved: null,
      events: Events(),
    )..state.selectedSkin = 19;

    for (int i = 0; i < 3; i++) {
      simulation.fireArrow(AimTarget(direction: const Offset(1, 0)));
    }

    expect(simulation.state.arrows, hasLength(5));
  });

  test('enemies are shielded beyond 600 vertical meters', () {
    final world = World();
    final simulation = Simulation(
      world: world,
      input: InputController(),
      tuning: Tuning(230, 470, 1080, 5.5, 1),
      saved: null,
      events: Events(),
    );
    final enemy = world.enemies.first;
    final player = simulation.state.player;
    final arrow = GameArrow(
      enemy.x,
      enemy.y,
      enemy.x,
      enemy.y,
      820,
      0,
      'normal',
      0,
      3.2,
      0,
    );
    final hp = enemy.hp;

    enemy.y = player.y + 601;
    simulation.hitEnemy(enemy, arrow);
    expect(enemy.hp, hp);

    enemy.y = player.y + 600;
    simulation.hitEnemy(enemy, arrow);
    expect(enemy.hp, hp - 1);
  });

  test('normal enemies, minibosses, and bosses retaliate at long range', () {
    final world = World();
    final simulation = Simulation(
      world: world,
      input: InputController(),
      tuning: Tuning(230, 470, 1080, 5.5, 1),
      saved: null,
      events: Events(),
    );
    final player = simulation.state.player;
    simulation.state.shopOpen = false;

    for (final enemy in [
      world.enemies.firstWhere((enemy) => !enemy.miniBoss),
      world.enemies.firstWhere((enemy) => enemy.miniBoss),
    ]) {
      player
        ..x = enemy.x
        ..y = enemy.y - 500;
      simulation.state.zone = zoneAt(player.y);
      enemy
        ..cooldown = 0
        ..attackTimer = 0.5;

      simulation.updateEnemies(0.01);

      expect(enemy.attackTimer, closeTo(0.55, 1e-9));
    }

    world.ensure(8400);
    final boss = world.boss!;
    player.y = boss.y - 500;
    simulation.state.zone = zoneAt(player.y);
    boss
      ..cooldown = 0
      ..attackTimer = 0;

    simulation.updateEnemies(0.01);

    expect(boss.attackTimer, closeTo(0.54, 1e-9));
  });

  test('hostile enemies from earlier areas stop attacking', () {
    final world = World();
    final simulation = Simulation(
      world: world,
      input: InputController(),
      tuning: Tuning(230, 470, 1080, 5.5, 1),
      saved: null,
      events: Events(),
    );
    world.ensure(9000);
    final enemy = world.enemies.firstWhere(
      (enemy) => !enemy.miniBoss && zoneAt(enemy.y) == 4,
    );
    simulation.state
      ..zone = 5
      ..shopOpen = false;
    simulation.state.player
      ..x = enemy.x
      ..y = 9000;
    enemy
      ..cooldown = 0
      ..attackTimer = 0.5;

    simulation.updateEnemies(0.01);

    expect(enemy.attackTimer, 0.5);
    expect(simulation.state.enemyShots, isEmpty);
  });

  test('world streams nearby chunks and reuses flattened entity lists', () {
    final world = World()..ensure(0);
    final startingPlatforms = world.platforms;

    expect(identical(startingPlatforms, world.platforms), isTrue);

    final highAreaHeight = areaHeight * 16;
    final center = (highAreaHeight / chunkHeight).floor();
    world.ensure(highAreaHeight);

    expect(world.chunks.length, lessThanOrEqualTo(11));
    expect(
      world.chunks.keys.every((index) => (index - center).abs() <= 5),
      isTrue,
    );
    expect(world.chunks.containsKey(0), isFalse);
    expect(identical(startingPlatforms, world.platforms), isFalse);
    expect(
      world.platformById(world.platforms.first.id),
      same(world.platforms.first),
    );
  });

  test('projectile sweep detects a hitbox crossed between updates', () {
    final enemyHitbox = Rect.fromLTWH(100, 100, 48, 48);

    expect(
      segmentIntersectsRect(
        const Offset(70, 120),
        const Offset(180, 120),
        enemyHitbox,
      ),
      isTrue,
    );
    expect(
      segmentIntersectsRect(
        const Offset(70, 80),
        const Offset(180, 80),
        enemyHitbox,
      ),
      isFalse,
    );
  });

  test('locked arrow explains its upgrade and checkpoint requirements', () {
    final simulation = Simulation(
      world: World(),
      input: InputController(),
      tuning: Tuning(230, 470, 1080, 5.5, 1),
      saved: null,
      events: Events(),
    );

    simulation.selectArrow(1);

    expect(simulation.state.toast.text, contains('PANAH API BELUM TERBUKA'));
    expect(simulation.state.toast.text, contains('UPGRADE 1250M / POS 1800M'));
    expect(simulation.state.toast.abovePlayer, isTrue);
  });

  test('entering a new area sets its entrance as the checkpoint', () {
    final input = InputController();
    final simulation = Simulation(
      world: World(),
      input: input,
      tuning: Tuning(230, 470, 1080, 5.5, 1),
      saved: null,
      events: Events(),
    );
    simulation.state.shopOpen = false;
    final player = simulation.state.player
      ..x = 520
      ..y = 1799
      ..vy = 220
      ..grounded = false;
    input.engaged = true;

    simulation.update(0.02);

    expect(simulation.state.zone, 1);
    expect(player.checkpoint.height, 1800);
    expect(player.checkpoint.x, 900);
  });

  test('swinging keeps the player attached at the rope endpoint', () {
    final simulation = Simulation(
      world: World(),
      input: InputController(),
      tuning: Tuning(230, 470, 1080, 5.5, 1),
      saved: null,
      events: Events(),
    );
    final rope = Rope('test-rope', 500, 400, 120, 0.35, 0, false, 10, false);
    final player = simulation.state.player..grabbedRope = rope;

    simulation.updateRope(player, 0, false);

    expect(
      player.y + 20,
      closeTo(rope.y - math.cos(rope.angle) * rope.length, 1e-9),
    );
  });

  test(
    'respawn resets the fall threshold without losing the run high score',
    () {
      final simulation = Simulation(
        world: World(),
        input: InputController(),
        tuning: Tuning(230, 470, 1080, 5.5, 1),
        saved: null,
        events: Events(),
      );
      final player = simulation.state.player
        ..checkpoint = Checkpoint(900, 1837, 1800)
        ..highest = 3000;

      simulation.respawn();

      expect(player.highestSinceRespawn, 1837);
      expect(player.highest, 3000);
      simulation.input.engaged = true;
      simulation.update(1 / 60);
      expect(player.deathTimer, 0);
    },
  );

  test('only the first four skins are free; others must be bought', () {
    final simulation = Simulation(
      world: World(),
      input: InputController(),
      tuning: Tuning(230, 470, 1080, 5.5, 1),
      saved: {'selectedSkin': 10},
      events: Events(),
    );
    final state = simulation.state;
    expect(state.ownedSkins, skins.take(4).map((s) => s.id).toList());
    expect(state.selectedSkin, 0);

    expect(simulation.selectSkin(4), isFalse);
    state.coins = skins[4].price - 1;
    expect(simulation.buySkin(4), isFalse);
    state.coins = skins[4].price;
    expect(simulation.buySkin(4), isTrue);
    expect(state.coins, 0);
    expect(state.ownedSkins, contains(skins[4].id));

    final restored = Simulation(
      world: World(),
      input: InputController(),
      tuning: Tuning(230, 470, 1080, 5.5, 1),
      saved: simulation.saveData(),
      events: Events(),
    );
    expect(restored.state.ownedSkins, contains(skins[4].id));
    expect(restored.state.selectedSkin, 4);
  });

  test('areas unlock for teleport only after being reached', () {
    final simulation = Simulation(
      world: World(),
      input: InputController(),
      tuning: Tuning(230, 470, 1080, 5.5, 1),
      saved: null,
      events: Events(),
    );
    expect(simulation.isZoneUnlocked(0), isTrue);
    expect(simulation.isZoneUnlocked(1), isFalse);

    simulation.teleportTo(3);
    expect(simulation.state.zone, 0);

    simulation.state.player.y = areaHeight * 2 + 10;
    simulation.update(0.001);
    expect(simulation.state.highestZone, 2);
    expect(simulation.isZoneUnlocked(2), isTrue);

    simulation.teleportTo(1);
    expect(simulation.state.zone, 1);
    expect(simulation.saveData()['highestZone'], 2);
  });
}
