import 'dart:math' as math;
import 'dart:ui';

import 'constants.dart';
import 'input_state.dart';
import 'world.dart';

double clamp(double v, double min, double max) =>
    math.max(min, math.min(max, v));

double hypot(double x, double y) => math.sqrt(x * x + y * y);

bool overlaps(Rect a, Rect b) =>
    a.left < b.right &&
    a.right > b.left &&
    a.top < b.bottom &&
    a.bottom > b.top;

bool segmentIntersectsRect(Offset start, Offset end, Rect rect) {
  var minT = 0.0;
  var maxT = 1.0;
  final dx = end.dx - start.dx;
  final dy = end.dy - start.dy;

  bool clip(double origin, double delta, double min, double max) {
    if (delta.abs() < 1e-9) return origin >= min && origin <= max;
    var near = (min - origin) / delta;
    var far = (max - origin) / delta;
    if (near > far) (near, far) = (far, near);
    minT = math.max(minT, near);
    maxT = math.min(maxT, far);
    return minT <= maxT;
  }

  return clip(start.dx, dx, rect.left, rect.right) &&
      clip(start.dy, dy, rect.top, rect.bottom);
}

class Particle {
  double x;
  double y;
  double vx;
  double vy;
  double life;
  final String color;
  final double size;
  Particle(this.x, this.y, this.vx, this.vy, this.life, this.color, this.size);
}

class Effect {
  final String name;
  final double x;
  final double y;
  double age = 0;
  final double duration;
  final double size;
  Effect(this.name, this.x, this.y, this.size, this.duration);
}

class GameArrow {
  double x;
  double y;
  double previousX;
  double previousY;
  double vx;
  double vy;
  final String type;
  final int skinIndex;
  double life;
  double rotation;
  GameArrow(
    this.x,
    this.y,
    this.previousX,
    this.previousY,
    this.vx,
    this.vy,
    this.type,
    this.skinIndex,
    this.life,
    this.rotation,
  );
}

class EnemyShot {
  double x;
  double y;
  double vx;
  double vy;
  double life;
  bool dead = false;
  final String color;
  final bool meteor;
  final bool star;
  EnemyShot(
    this.x,
    this.y,
    this.vx,
    this.vy,
    this.life,
    this.color, {
    this.meteor = false,
    this.star = false,
  });
}

class Unlocks {
  bool normal = true;
  bool fire = false;
  bool ice = false;
  bool rope = false;
  bool cape = false;
}

class Checkpoint {
  double x;
  double y;
  double height;
  Checkpoint(this.x, this.y, this.height);
}

class Player {
  double x;
  double y;
  double previousY = 0;
  double vx = 0;
  double vy = 0;
  final double w = 34;
  final double h = 62;
  bool grounded = true;
  bool airJumpUsed = false;
  double coyote = 0.1;
  bool climbing = false;
  Rope? grabbedRope;
  double ropeCooldown = 0;
  double ladderCooldown = 0;
  int facing = 1;
  int hearts;
  int maxHearts;
  double energy;
  final double maxEnergy;
  int selectedArrow = 0;
  final Unlocks unlocks = Unlocks();
  late Checkpoint checkpoint;
  double invulnerable = 0;
  double hurt = 0;
  double shootTimer = 0;
  double deathTimer = 0;
  double jumpTapAge = 9;
  int killChain = 0;
  int shotCount = 0;
  double highest;
  double highestSinceRespawn;
  String anim = "idle";

  int get hp => hearts;

  set hp(int value) => hearts = value.clamp(0, maxHearts).toInt();

  Player(
    this.x,
    this.y,
    this.hearts,
    this.maxHearts,
    this.energy,
    this.maxEnergy,
    this.highest,
  ) : highestSinceRespawn = y {
    previousY = y;
  }
}

class Tuning {
  double playerSpeed;
  double jumpVelocity;
  double gravity;
  double cameraSmooth;
  double effectsIntensity;
  Tuning(
    this.playerSpeed,
    this.jumpVelocity,
    this.gravity,
    this.cameraSmooth,
    this.effectsIntensity,
  );
}

class Toast {
  String text;
  double time;
  final bool abovePlayer;
  Toast(this.text, this.time, {this.abovePlayer = false});
}

class Events {
  final void Function(String)? sfx;
  final void Function(dynamic)? haptic;
  final void Function(GameState)? save;
  final void Function(int)? zone;
  final void Function(GameState)? win;
  final void Function(String)? music;
  Events({this.sfx, this.haptic, this.save, this.zone, this.win, this.music});
}

class GameState {
  double time = 0;
  bool started = false;
  bool shopOpen = true;
  bool mapOpen = false;
  bool won = false;
  int zone = 0;
  int previousZone = 0;

  /// Area tertinggi yang pernah dicapai; area di atasnya terkunci di peta.
  int highestZone = 0;
  final List<GameArrow> arrows = [];
  final List<EnemyShot> enemyShots = [];
  final List<Particle> particles = [];
  final List<Effect> effects = [];
  double shake = 0;
  double flash = 0;
  late Toast toast;
  int coins = 0;
  List<String> ownedSkins = [];
  int selectedSkin = 0;
  double meteorTimer = 1.4;
  double crownTimer = 1.2;
  double trailTimer = 0;
  late Player player;
}

class Simulation {
  final World world;
  final InputController input;
  final Tuning tuning;
  final Map<String, dynamic>? saved;
  final Events events;
  final GameState state = GameState();
  String? _announcedBoss;
  String? _announcedMini;

  Simulation({
    required this.world,
    required this.input,
    required this.tuning,
    required this.saved,
    required this.events,
  }) {
    final savedHeight = clamp(
      (saved?['checkpoint']?['height'] as num?)?.toDouble() ?? 0,
      0,
      maxHeight,
    );
    final startX = clamp(
      (saved?['checkpoint']?['x'] as num?)?.toDouble() ?? 900,
      80,
      worldWidth - 80,
    );
    final startY = savedHeight + 35;
    state.coins = math.max(0, (saved?['coins'] as num?)?.toInt() ?? 0);
    // Skin gratis (harga 0) selalu terbuka; sisanya harus dibeli dengan koin.
    final savedOwned = (saved?['ownedSkins'] as List?)?.whereType<String>();
    state.ownedSkins = [
      for (final s in skins)
        if (s.price == 0 || (savedOwned?.contains(s.id) ?? false)) s.id,
    ];
    final savedSelected = clamp(
      (saved?['selectedSkin'] as num?)?.toDouble() ?? 0.0,
      0.0,
      (skins.length - 1).toDouble(),
    ).toInt();
    state.selectedSkin = state.ownedSkins.contains(skins[savedSelected].id)
        ? savedSelected
        : 0;
    state.zone = zoneAt(savedHeight);
    state.previousZone = zoneAt(savedHeight);
    state.highestZone = math.max(
      state.zone,
      ((saved?['highestZone'] as num?)?.toInt() ?? 0).clamp(
        0,
        zones.length - 1,
      ),
    );
    state.toast = Toast("TAP TARGET UNTUK MENEMBAK", 3);
    final player = Player(
      startX,
      startY,
      (saved?['maxHearts'] as num?)?.toInt() ?? 3,
      (saved?['maxHearts'] as num?)?.toInt() ?? 3,
      (saved?['maxEnergy'] as num?)?.toDouble() ?? 100,
      (saved?['maxEnergy'] as num?)?.toDouble() ?? 100,
      math.max(savedHeight, (saved?['bestHeight'] as num?)?.toDouble() ?? 0),
    );
    player.unlocks.fire = (saved?['unlocks']?['fire'] as bool?) ?? false;
    player.unlocks.ice = (saved?['unlocks']?['ice'] as bool?) ?? false;
    player.unlocks.rope = (saved?['unlocks']?['rope'] as bool?) ?? false;
    player.unlocks.cape = (saved?['unlocks']?['cape'] as bool?) ?? false;
    player.checkpoint = Checkpoint(startX, startY, savedHeight);
    state.player = player;
    world.ensure(startY);
  }

  void toast(String text, [double duration = 1.8]) =>
      state.toast = Toast(text, duration);

  void toastAbovePlayer(String text, [double duration = 1.8]) =>
      state.toast = Toast(text, duration, abovePlayer: true);

  int _awardCoins(int amount, {Skin? skin}) {
    final reward =
        skin?.id == "nomad" ||
            (skin == null && skins[state.selectedSkin].id == "nomad")
        ? (amount * 1.25).round()
        : amount;
    state.coins += reward;
    return reward;
  }

  void _defeatEnemy(Enemy enemy, Skin skin) {
    if (!enemy.alive) return;
    enemy.alive = false;
    final baseReward = enemy.miniBoss
        ? 60 + (enemy.zoneIndex ?? 0) * 12
        : 10 + zoneAt(enemy.y) * 3;
    final reward = _awardCoins(baseReward, skin: skin);
    if (skin.id == "raven") {
      state.player.energy = math.min(
        state.player.maxEnergy,
        state.player.energy + 12,
      );
    }
    if (skin.id == "bloodmoon") {
      state.player.killChain++;
      if (state.player.killChain % 4 == 0) {
        state.player.hearts = math.min(
          state.player.maxHearts,
          state.player.hearts + 1,
        );
      }
    } else {
      state.player.killChain = 0;
    }
    effect("coin_collect", enemy.x, enemy.y + 42, 54);
    if (enemy.miniBoss) toast("${enemy.name} TUMBANG · +$reward KOIN", 2.8);
    events.save?.call(state);
    events.sfx?.call(enemy.miniBoss ? "boss_die" : "enemy_die");
    burst(enemy.x, enemy.y + 25, skin.color, 11);
  }

  void burst(double x, double y, String color, [int count = 8]) {
    for (int i = 0; i < count; i++) {
      final angle = math.Random().nextDouble() * math.pi * 2;
      final speed = 45 + math.Random().nextDouble() * 150;
      state.particles.add(
        Particle(
          x,
          y,
          math.cos(angle) * speed,
          math.sin(angle) * speed,
          0.35 + math.Random().nextDouble() * 0.45,
          color,
          2 + math.Random().nextDouble() * 4,
        ),
      );
    }
  }

  void effect(String name, double x, double y, [double size = 60]) =>
      state.effects.add(Effect(name, x, y, size, 0.42));

  void damagePlayer(double sourceX, [String reason = "unknown"]) {
    final player = state.player;
    if (player.invulnerable > 0 || player.deathTimer > 0 || state.won) return;
    final before = player.hp;
    // ignore: avoid_print
    print(
      "[DAMAGE] reason=$reason sourceX=${sourceX.toStringAsFixed(0)} "
      "playerX=${player.x.toStringAsFixed(0)} playerY=${player.y.toStringAsFixed(0)} "
      "zone=${state.zone} hp=$before -> ${before - 1}",
    );
    final skin = skins[state.selectedSkin];
    if (skin.id == "sakura" && math.Random().nextDouble() < 0.15) {
      effect(
        skin.effect ?? "skin14_hit",
        player.x,
        player.y + player.h / 2,
        64,
      );
      player.invulnerable = 0.18;
      toast("DODGE!", 0.65);
      return;
    }
    player.hp = before - 1;
    player.killChain = 0;
    player.invulnerable = skin.id == "solar" ? 1.6 : 1.2;
    player.hurt = 0.35;
    player.vx = player.x < sourceX ? -260 : 260;
    player.vy = 260;
    state.shake = 0.35;
    state.flash = 0.18;
    events.sfx?.call("hurt");
    events.haptic?.call([35, 30, 45]);
    if (player.hp <= 0) {
      player.deathTimer = 0.85;
      events.sfx?.call("die");
    }
  }

  void respawn() {
    final player = state.player;
    world.resetAround(player.checkpoint.y);
    player.x = player.checkpoint.x;
    player.y = player.checkpoint.y;
    player.previousY = player.y;
    player.highestSinceRespawn = player.y;
    player.vx = 0;
    player.vy = 0;
    player.grounded = false;
    player.climbing = false;
    player.coyote = 0;
    player.airJumpUsed = false;
    // Keep the remaining HP visible after a fall; a full refill happens at a
    // checkpoint instead of immediately hiding the damage during respawn.
    if (player.hp <= 0) player.hp = player.maxHearts;
    player.energy = player.maxEnergy;
    player.deathTimer = 0;
    player.invulnerable = 1;
    player.grabbedRope = null;
    state.arrows.clear();
    state.enemyShots.clear();
    toast("KEMBALI KE BENDERA");
  }

  void selectArrow(int index) {
    if (index < 0 || index >= arrows.length) return;
    final arrow = arrows[index];
    if (arrow.id != "normal" && !_unlocked(arrow.id)) {
      final requirement = switch (arrow.id) {
        "fire" => "UPGRADE 1250M / POS 1800M",
        "ice" => "UPGRADE 3050M / POS 3600M",
        "rope" => "UPGRADE 3950M / POS 4500M",
        _ => "CARI UPGRADE DI PERJALANAN",
      };
      toastAbovePlayer(
        "PANAH ${arrow.label.toUpperCase()} BELUM TERBUKA\n$requirement",
        2.8,
      );
      return;
    }
    state.player.selectedArrow = index;
    events.sfx?.call("pickup");
  }

  bool _unlocked(String id) {
    if (id == "normal") return true;
    return (state.player.unlocks)._get(id);
  }

  bool _enemyIsInCurrentArea(Enemy enemy) => zoneAt(enemy.y) >= state.zone;

  void fireArrow(AimTarget aim) {
    final player = state.player;
    final skin = skins[state.selectedSkin];
    final arrowType = arrows[player.selectedArrow];
    final cost =
        arrowType.cost.toDouble() *
        (skin.id == "ember" && arrowType.id == "fire" ? 0.7 : 1.0);
    if (player.energy < cost) {
      toast("ENERGI KURANG");
      return;
    }
    player.energy -= cost;
    if (aim.target != null) {
      final dx = aim.target!.dx - player.x;
      if (dx.abs() > 4) player.facing = dx.sign.toInt();
    } else if (aim.direction?.dx != null && aim.direction!.dx != 0) {
      player.facing = aim.direction!.dx.sign.toInt();
    }
    final origin = Offset(player.x + player.facing * 24, player.y + 42);
    Offset? direction = aim.direction;
    if (aim.target != null) {
      final dx = aim.target!.dx - origin.dx;
      final dy = aim.target!.dy - origin.dy;
      final length = math.max(1, hypot(dx, dy));
      direction = Offset(dx / length, dy / length);
    }
    direction ??= Offset(player.facing.toDouble(), 0);
    final speed = skin.id == "storm" ? 984.0 : 820.0;
    player.shotCount++;
    final spread = skin.id == "emperor" && player.shotCount % 3 == 0
        ? [-0.16, 0.0, 0.16]
        : [0.0];
    final baseAngle = math.atan2(direction.dy, direction.dx);
    for (final offset in spread) {
      final angle = baseAngle + offset;
      state.arrows.add(
        GameArrow(
          origin.dx,
          origin.dy,
          origin.dx,
          origin.dy,
          math.cos(angle) * speed,
          math.sin(angle) * speed,
          arrowType.id,
          state.selectedSkin,
          3.2,
          angle,
        ),
      );
    }
    player.shootTimer = 0.35;
    events.sfx?.call(
      arrowType.id == "fire"
          ? "shoot_fire"
          : arrowType.id == "ice"
          ? "shoot_ice"
          : arrowType.id == "rope"
          ? "shoot_rope"
          : "shoot",
    );
    events.haptic?.call(12);
  }

  void activateFlag(Flag flag) {
    final player = state.player;
    if (flag.active && player.checkpoint.height >= flag.height) return;
    for (final it in world.flags) {
      if (it.height == flag.height) it.active = true;
    }
    flag.animStart = state.time;
    player.checkpoint = Checkpoint(flag.x, flag.y + 2, flag.height);
    player.highestSinceRespawn = player.y;
    final checkpointBonus = skins[state.selectedSkin].id == "scarab"
        ? _awardCoins(25)
        : 0;
    if (flag.height >= 1800) player.unlocks.fire = true;
    if (flag.height >= 2700) player.unlocks.cape = true;
    if (flag.height >= 3600) player.unlocks.ice = true;
    if (flag.height >= 4500) player.unlocks.rope = true;
    player.hearts = player.maxHearts;
    player.energy = player.maxEnergy;
    events.sfx?.call("checkpoint");
    events.haptic?.call([20, 40, 20]);
    toast(
      "CHECKPOINT ${flag.height.toInt()} m${checkpointBonus > 0 ? ' · +$checkpointBonus KOIN' : ''}",
      2.2,
    );
    events.save?.call(state);
  }

  void collect(Pickup item) {
    final player = state.player;
    if (item.collected) return;
    item.collected = true;
    if (item.type == "coin") {
      final reward = _awardCoins(item.value);
      effect("coin_collect", item.x, item.y, 46);
      toast("+$reward KOIN", 0.8);
      events.save?.call(state);
    } else if (item.type == "crystal") {
      player.energy = math.min(player.maxEnergy, player.energy + 45);
      if (skins[state.selectedSkin].id == "bloom" &&
          player.hearts < player.maxHearts) {
        player.hearts++;
        toast("ENERGI +45 · HATI +1");
      } else {
        toast("ENERGI +45");
      }
    } else {
      player.unlocks._set(item.type, true);
      if (item.type != "cape")
        player.selectedArrow = arrows.indexWhere((a) => a.id == item.type);
      toast(item.label, 2.5);
      events.save?.call(state);
    }
    burst(item.x, item.y, "#76ecff", 14);
    events.sfx?.call(
      item.type == "coin"
          ? "coin"
          : item.type == "crystal"
          ? "crystal"
          : "upgrade",
    );
    events.haptic?.call(18);
  }

  bool updateRope(Player player, double dt, bool jumpPressed) {
    final rope = player.grabbedRope;
    if (rope == null) return false;
    rope.omega +=
        (-math.sin(rope.angle) * 8 +
            ((input.state.right ? 1 : 0) - (input.state.left ? 1 : 0)) * 5) *
        dt;
    rope.omega *= math.pow(0.995, dt * 60);
    rope.angle = clamp(rope.angle + rope.omega * dt, -1.25, 1.25);
    player.x = rope.x + math.sin(rope.angle) * rope.length;
    player.y = rope.y - math.cos(rope.angle) * rope.length - 20;
    player.vx = math.cos(rope.angle) * rope.length * rope.omega;
    player.vy = math.sin(rope.angle) * rope.length * rope.omega;
    if (player.vx.abs() > 12) player.facing = player.vx.sign.toInt();
    player.anim = "swing";
    if (jumpPressed) {
      player.grabbedRope = null;
      player.ropeCooldown = 0.48;
      player.vx *= 1.55;
      player.vy += tuning.jumpVelocity * 0.82;
      effect("perfect_bounce", player.x, player.y + 12, 72);
      burst(player.x, player.y + 18, skins[state.selectedSkin].color, 12);
      toast("SLING BOOST!", 0.7);
      events.sfx?.call("jump");
      events.haptic?.call([14, 18, 24]);
    }
    return true;
  }

  void updatePlayer(double dt) {
    final player = state.player;
    final jumpPressed = input.consumeJump();
    if (jumpPressed)
      player.jumpTapAge = 0;
    else
      player.jumpTapAge += dt;
    final arrowRequest = input.consumeArrowRequest();
    if (arrowRequest != null) selectArrow(arrowRequest);
    final shot = input.consumeShot();
    if (shot != null) fireArrow(shot);
    if (!state.started && input.state.engaged) state.started = true;
    if (!state.started || state.shopOpen || player.deathTimer > 0 || state.won)
      return;

    player.previousY = player.y;
    if (input.state.aim?.target != null) {
      final dx = input.state.aim!.target!.dx - player.x;
      if (dx.abs() > 4) player.facing = dx.sign.toInt();
    } else if (input.state.aim?.direction != null &&
        input.state.aim!.direction!.dx != 0) {
      player.facing = input.state.aim!.direction!.dx.sign.toInt();
    }
    player.invulnerable = math.max(0, player.invulnerable - dt);
    player.ropeCooldown = math.max(0, player.ropeCooldown - dt);
    player.ladderCooldown = math.max(0, player.ladderCooldown - dt);
    player.hurt = math.max(0, player.hurt - dt);
    player.shootTimer = math.max(0, player.shootTimer - dt);
    player.coyote = player.grounded ? 0.11 : math.max(0, player.coyote - dt);

    if (updateRope(player, dt, jumpPressed)) return;

    final ladder = world.ladders.where((item) {
      return player.x > item.x - 8 &&
          player.x < item.x + item.w + 8 &&
          player.y > item.y - 10 &&
          player.y < item.y + item.h + 25;
    }).firstOrNull;
    player.climbing =
        player.ladderCooldown <= 0 &&
        ladder != null &&
        (input.state.up ||
            input.state.down ||
            input.state.jump ||
            player.climbing);
    if (player.climbing && ladder != null) {
      player.x += (ladder.x + ladder.w / 2 - player.x) * math.min(1, dt * 10);
      player.vy =
          (((input.state.up || input.state.jump) ? 1 : 0) -
              (input.state.down ? 1 : 0)) *
          155;
      player.vx *= 0.7;
      player.grounded = false;
      final top = ladder.y + ladder.h;
      if ((input.state.up || input.state.jump) && player.y >= top - 7) {
        player.y = top + 4;
        player.previousY = player.y;
        player.vy = 22;
        player.climbing = false;
        player.grounded = true;
        player.ladderCooldown = 0.32;
      }
    } else {
      final axis = (input.state.right ? 1 : 0) - (input.state.left ? 1 : 0);
      final target = axis * tuning.playerSpeed;
      player.vx +=
          (target - player.vx) * math.min(1, dt * (player.grounded ? 15 : 7));
      if (axis != 0) player.facing = axis.sign.toInt();
      if (jumpPressed && player.coyote > 0) {
        player.vy = tuning.jumpVelocity;
        player.grounded = false;
        player.coyote = 0;
        events.sfx?.call("jump");
      } else if (jumpPressed &&
          skins[state.selectedSkin].id == "rabbit" &&
          !player.grounded &&
          !player.airJumpUsed) {
        player.vy = tuning.jumpVelocity * 0.78;
        player.airJumpUsed = true;
        effect("perfect_bounce", player.x, player.y + player.h, 54);
        events.sfx?.call("jump");
      }
      final currentZone = zoneAt(player.y);
      double gravity = currentZone == 4 ? tuning.gravity * 0.5 : tuning.gravity;
      if (currentZone == 16)
        gravity *= 0.35 + ((math.sin(state.time * 1.8) + 1) / 2) * 0.75;
      player.vy -= gravity * dt;
    }

    final inWind = world.winds.any(
      (wind) =>
          player.x > wind.x &&
          player.x < wind.x + wind.w &&
          player.y > wind.y &&
          player.y < wind.y + wind.h,
    );
    if (inWind && player.unlocks.cape && input.state.jump) {
      player.vy = math.min(330, player.vy + 1050 * dt);
      player.anim = "cape";
    }

    player.x = clamp(player.x + player.vx * dt, 24, worldWidth - 24);
    player.y += player.vy * dt;
    final guardingBoss = world.boss;
    if (guardingBoss != null &&
        guardingBoss.alive &&
        zoneAt(guardingBoss.y) >= state.zone &&
        player.y > guardingBoss.y + 78) {
      player.y = guardingBoss.y + 78;
      player.vy = math.min(0, player.vy);
    }
    final guardingMini = world.miniBoss;
    if (guardingMini != null &&
        guardingMini.alive &&
        _enemyIsInCurrentArea(guardingMini) &&
        player.y > guardingMini.y + 105) {
      player.y = guardingMini.y + 105;
      player.vy = math.min(0, player.vy);
    }
    final wasGrounded = player.grounded;
    player.grounded = false;

    if (player.vy <= 0) {
      Platform? landing;
      for (final item in world.platforms) {
        if (item.disabled) continue;
        final crossed = player.previousY >= item.y && player.y <= item.y;
        final horizontal =
            player.x + player.w * 0.42 > item.x &&
            player.x - player.w * 0.42 < item.x + item.w;
        if (crossed && horizontal && (landing == null || item.y > landing.y))
          landing = item;
      }
      for (final enemy in world.enemies) {
        if (!enemy.alive ||
            !_enemyIsInCurrentArea(enemy) ||
            enemy.frozen <= 0) {
          continue;
        }
        if (player.previousY >= enemy.y + 42 &&
            player.y <= enemy.y + 42 &&
            (player.x - enemy.x).abs() < 36) {
          landing = Platform(
            'frozen',
            enemy.x - 36,
            enemy.y + 42,
            72,
            'frozen-enemy',
            enemy.x - 36,
            enemy.y + 42,
          );
        }
      }
      if (landing != null) {
        player.y = landing.y;
        player.vy = 0;
        player.grounded = true;
        player.airJumpUsed = false;
        // Saat berdiri, pendaratan terdeteksi ulang setiap frame; bunyikan
        // hanya ketika benar-benar baru mendarat.
        if (!landing.mushroom && !wasGrounded) events.sfx?.call("land");
        if (landing.mushroom) {
          final perfect = player.jumpTapAge < 0.18;
          player.vy = tuning.jumpVelocity * (perfect ? 1.72 : 1.28);
          player.grounded = false;
          landing.bounceAt = state.time;
          effect("perfect_bounce", player.x, landing.y + 4, perfect ? 92 : 60);
          toast(perfect ? "PERFECT BOUNCE!" : "PANTUL!", 0.8);
          events.sfx?.call("bounce");
          events.haptic?.call(perfect ? [20, 20, 30] : 14);
        } else if (landing.type == "anti") {
          player.vy = tuning.jumpVelocity * 0.9;
          player.grounded = false;
          toast("ANTI-GRAVITASI", 0.75);
        } else if (landing.type == "thorn") {
          damagePlayer(landing.x + landing.w / 2, "thorn_platform");
          player.vy = tuning.jumpVelocity * 0.65;
          player.grounded = false;
        } else if (landing.type == "heat" &&
            math.sin(state.time * 4 + landing.phase) > 0.25) {
          damagePlayer(landing.x + landing.w / 2, "heat_platform");
          player.vy = tuning.jumpVelocity * 0.75;
          player.grounded = false;
        } else if (landing.type == "rail") {
          player.vx = player.facing * 430;
          player.vy = tuning.jumpVelocity * 0.72;
          player.grounded = false;
          effect("perfect_bounce", player.x, landing.y + 4, 64);
        } else if (landing.type == "comet") {
          player.vy = tuning.jumpVelocity * 1.05;
          player.grounded = false;
          burst(player.x, landing.y + 8, "#ff9a48", 8);
        }
        if (landing.type == "crumble" ||
            landing.type == "cloud" ||
            landing.type == "glass") {
          landing.timer += dt;
          final limit = landing.type == "glass"
              ? 0.85
              : landing.type == "cloud"
              ? 1.5
              : 3;
          if (landing.timer >= limit) {
            landing.disabled = true;
            landing.timer = landing.type == "cloud" ? 3 : 4;
            events.sfx?.call("crumble");
          }
        }
      }
    }

    if (!player.grounded && !player.climbing && player.ropeCooldown <= 0) {
      final endpoint = world.ropes.where((rope) {
        final endX = rope.x + math.sin(rope.angle) * rope.length;
        final endY = rope.y - math.cos(rope.angle) * rope.length;
        return hypot(player.x - endX, player.y + 20 - endY) < 34;
      }).firstOrNull;
      if (endpoint != null) {
        player.grabbedRope = endpoint;
        player.x = endpoint.x + math.sin(endpoint.angle) * endpoint.length;
        player.y = endpoint.y - math.cos(endpoint.angle) * endpoint.length - 20;
        player.vx = 0;
        player.vy = 0;
        events.sfx?.call("rope");
        events.haptic?.call(10);
      }
    }

    for (final flag in world.flags) {
      if ((player.x - flag.x).abs() < 38 && (player.y - flag.y).abs() < 65)
        activateFlag(flag);
    }
    final pickupRange = skins[state.selectedSkin].id == "verdant" ? 60 : 48;
    for (final item in world.pickups) {
      if (!item.collected &&
          hypot(player.x - item.x, player.y + 28 - item.y) < pickupRange)
        collect(item);
    }
    for (final enemy in world.enemies) {
      if (!enemy.alive || !_enemyIsInCurrentArea(enemy) || enemy.frozen > 0) {
        continue;
      }
      final radius = enemy.miniBoss ? 46 : 24;
      final enemyBox = Rect.fromLTWH(
        enemy.x - radius,
        enemy.y,
        radius * 2,
        enemy.miniBoss ? 82 : 48,
      );
      final box = Rect.fromLTWH(
        player.x - player.w / 2,
        player.y,
        player.w,
        player.h,
      );
      if (overlaps(box, enemyBox)) damagePlayer(enemy.x, "enemy_body");
    }
    for (final projectile in state.enemyShots) {
      if (!projectile.dead &&
          hypot(projectile.x - player.x, projectile.y - (player.y + 30)) < 27) {
        projectile.dead = true;
        damagePlayer(projectile.x, "enemy_projectile");
      }
    }
    for (final hazard in world.hazards) {
      final active =
          math.sin(
            state.time * (hazard.type == "storm" ? 5 : 4) + hazard.phase,
          ) >
          0.72;
      if (!active) continue;
      final hazardBox = Rect.fromLTWH(hazard.x, hazard.y, hazard.w, hazard.h);
      final box = Rect.fromLTWH(
        player.x - player.w / 2,
        player.y,
        player.w,
        player.h,
      );
      if (overlaps(box, hazardBox)) {
        damagePlayer(hazard.x + hazard.w / 2, "active_hazard:${hazard.type}");
      }
    }

    player.highest = math.max(player.highest, player.y);
    player.highestSinceRespawn = math.max(player.highestSinceRespawn, player.y);
    final energyRegen =
        skins[state.selectedSkin].id == "witch" && !player.grounded ? 9.0 : 4.5;
    player.energy = math.min(
      player.maxEnergy,
      player.energy + dt * energyRegen,
    );
    if (player.y < player.checkpoint.y - 280 ||
        player.y < player.highestSinceRespawn - 720) {
      // ignore: avoid_print
      print(
        "[DEATH] fall: playerY=${player.y.toStringAsFixed(0)} "
        "checkpointY=${player.checkpoint.y.toStringAsFixed(0)} "
        "highestSinceRespawn=${player.highestSinceRespawn.toStringAsFixed(0)} "
        "hp=${player.hp}",
      );
      damagePlayer(player.x, "fall");
      player.deathTimer = math.max(player.deathTimer, 0.7);
    }

    if (player.hurt > 0)
      player.anim = "hurt";
    else if (player.shootTimer > 0)
      player.anim = "shoot";
    else if (input.state.aim != null)
      player.anim = "aim";
    else if (player.climbing)
      player.anim = "climb";
    else if (!player.grounded)
      player.anim = player.vy >= 0 ? "jump" : "fall";
    else if (player.vx.abs() > 25)
      player.anim = "run";
    else
      player.anim = "idle";

    state.trailTimer -= dt;
    if (state.trailTimer <= 0 &&
        (player.vx.abs() > 70 || player.vy.abs() > 180)) {
      final skin = skins[state.selectedSkin];
      state.particles.add(
        Particle(
          player.x - player.facing * 15,
          player.y + 28,
          -player.vx * 0.1,
          25,
          0.35,
          skin.color,
          3.5,
        ),
      );
      state.trailTimer = 0.075;
    }
  }

  void updateEnemies(double dt) {
    final player = state.player;
    for (final enemy in world.enemies) {
      if (!enemy.alive || !_enemyIsInCurrentArea(enemy)) continue;
      enemy.hurt = math.max(0, enemy.hurt - dt);
      enemy.frozen = math.max(0, enemy.frozen - dt);
      if (enemy.burnTimer > 0) {
        enemy.burnTimer -= dt;
        enemy.burnTick -= dt;
        if (enemy.burnTick <= 0) {
          enemy.hp -= 1;
          enemy.burnTick += 1;
          enemy.hurt = 0.2;
          if (enemy.hp <= 0) {
            _defeatEnemy(enemy, skins[enemy.burnSkinIndex]);
            continue;
          }
        }
      }
      if (enemy.frozen > 0) continue;
      enemy.cooldown -= dt;
      final priorAttack = enemy.attackTimer;
      enemy.attackTimer = math.max(0, enemy.attackTimer - dt);
      final distanceX = player.x - enemy.x;
      final distanceY = player.y - enemy.y;
      enemy.facing = distanceX < 0 ? -1 : 1;
      final platform = world.platformById(enemy.platformId);
      if (platform != null && enemy.attackTimer <= 0) {
        enemy.homeX = platform.x + enemy.platformOffset;
        enemy.y = platform.y;
        enemy.x =
            enemy.homeX +
            math.sin(state.time * 1.5 + enemy.id.length) *
                math.min(42, platform.w * 0.22);
      }
      final rangeX = enemy.miniBoss ? 540 : 390;
      const rangeY = 600.0;
      if (enemy.cooldown <= 0 &&
          distanceX.abs() < rangeX &&
          distanceY.abs() < rangeY) {
        enemy.attackTimer = 0.55;
        enemy.cooldown =
            (enemy.miniBoss ? 1.45 : 2.2) + math.Random().nextDouble() * 0.8;
      }
      if (priorAttack > 0 && enemy.attackTimer <= 0) {
        final length = math.max(1, hypot(distanceX, distanceY));
        final speed = enemy.miniBoss
            ? 330
            : enemy.type == "harpy"
            ? 300
            : 250;
        state.enemyShots.add(
          EnemyShot(
            enemy.x,
            enemy.y + 30,
            distanceX / length * speed,
            distanceY / length * speed,
            3,
            enemy.type == "sentinel" ? "#58f4ff" : "#ffc45a",
          ),
        );
      }
    }

    final boss = world.boss;
    if (boss != null &&
        boss.alive &&
        zoneAt(boss.y) >= state.zone &&
        (player.y - boss.y).abs() < 600) {
      boss.hurt = math.max(0, boss.hurt - dt);
      boss.cooldown -= dt;
      final arenaY = boss.homeY;
      boss.x = 900 + math.sin(state.time * 0.7) * 230;
      boss.y = arenaY + math.sin(state.time * 1.2) * 42;
      boss.facing = player.x < boss.x ? -1 : 1;
      final healthRatio = boss.hp / boss.maxHp;
      boss.phase = healthRatio > 0.6
          ? 1
          : healthRatio > 0.25
          ? 2
          : 3;
      if (boss.cooldown <= 0) {
        boss.attackTimer = boss.phase == 3 ? 0.85 : 0.55;
        boss.cooldown = math.max(0.75, 1.65 - boss.phase * 0.2);
      }
      if (boss.attackTimer > 0) {
        boss.attackTimer -= dt;
        if (boss.attackTimer <= 0) {
          final shots = boss.phase + 1;
          for (int i = 0; i < shots; i++) {
            final base = math.atan2(player.y + 25 - boss.y, player.x - boss.x);
            final angle = base + (i - (shots - 1) / 2) * 0.18;
            state.enemyShots.add(
              EnemyShot(
                boss.x,
                boss.y,
                math.cos(angle) * 340,
                math.sin(angle) * 340,
                4,
                "#f8dd7b",
              ),
            );
          }
        }
      }
    }

    if ((state.zone == 5 || state.zone == 12) &&
        !state.shopOpen &&
        state.started) {
      state.meteorTimer -= dt;
      if (state.meteorTimer <= 0) {
        final x = clamp(
          player.x + (math.Random().nextDouble() - 0.5) * 360,
          30,
          worldWidth - 30,
        );
        state.enemyShots.add(
          EnemyShot(
            x,
            player.y + 620,
            (player.x - x) * 0.18,
            -410,
            3,
            "#ff8b44",
            meteor: true,
          ),
        );
        state.meteorTimer = 1.05 + math.Random().nextDouble() * 0.65;
      }
    }
    if ((state.zone == 9 || state.zone == 19) &&
        !state.shopOpen &&
        state.started) {
      state.crownTimer -= dt;
      if (state.crownTimer <= 0) {
        final fromLeft = math.Random().nextDouble() > 0.5;
        state.enemyShots.add(
          EnemyShot(
            fromLeft ? 0 : worldWidth,
            player.y + 80 + math.Random().nextDouble() * 220,
            fromLeft ? 360 : -360,
            -80 - math.Random().nextDouble() * 80,
            5,
            "#ffe683",
            star: true,
          ),
        );
        state.crownTimer = 0.9 + math.Random().nextDouble() * 0.6;
      }
    }
  }

  void hitEnemy(Enemy enemy, GameArrow arrow, {bool chained = false}) {
    if ((enemy.y - state.player.y).abs() > 600) {
      effect("ice_hit", arrow.x, arrow.y, 54);
      burst(arrow.x, arrow.y, "#78e8ff", 5);
      return;
    }
    final skin = skins[arrow.skinIndex];
    final hitName = arrow.type == "normal" && skin.effect != null
        ? skin.effect!
        : "${arrow.type}_hit";
    effect(
      hitName,
      arrow.x,
      arrow.y,
      arrow.type == "fire" || enemy.miniBoss ? 82 : 64,
    );
    if (arrow.type == "ice") {
      enemy.frozen = skin.id == "frost" ? 7 : 5;
      events.sfx?.call("freeze");
    } else {
      enemy.hp -=
          (arrow.type == "fire" ? 2 : 1) +
          (enemy.miniBoss && skin.id == "ascendant" ? 1 : 0);
      enemy.hurt = 0.35;
      if (skin.id == "drake" && arrow.type == "fire") {
        enemy.burnTimer = 3;
        enemy.burnTick = 1;
        enemy.burnSkinIndex = arrow.skinIndex;
        events.sfx?.call("burn");
      }
      if (skin.id == "venom") enemy.cooldown += 1.2;
      if (enemy.hp <= 0) {
        _defeatEnemy(enemy, skin);
      }
    }
    if (skin.id == "lion" && !chained) {
      final nearby = world.enemies
          .where((other) => other.alive && other.id != enemy.id)
          .toList();
      Enemy? target;
      for (final other in nearby) {
        if (hypot(other.x - enemy.x, other.y - enemy.y) > 170) continue;
        if (target == null ||
            hypot(other.x - enemy.x, other.y - enemy.y) <
                hypot(target.x - enemy.x, target.y - enemy.y)) {
          target = other;
        }
      }
      if (target != null) hitEnemy(target, arrow, chained: true);
    }
    events.sfx?.call("hit");
    events.haptic?.call(8);
  }

  void updateProjectiles(double dt) {
    for (final arrow in state.arrows) {
      arrow.previousX = arrow.x;
      arrow.previousY = arrow.y;
      arrow.x += arrow.vx * dt;
      arrow.y += arrow.vy * dt;
      arrow.rotation = math.atan2(arrow.vy, arrow.vx);
      arrow.life -= dt;
      if (arrow.type == "ice" && skins[arrow.skinIndex].id == "tide") {
        for (final shot in state.enemyShots) {
          if (shot.dead) continue;
          final shotBox = Rect.fromCircle(
            center: Offset(shot.x, shot.y),
            radius: 15,
          );
          if (segmentIntersectsRect(
            Offset(arrow.previousX, arrow.previousY),
            Offset(arrow.x, arrow.y),
            shotBox,
          )) {
            shot.dead = true;
            arrow.life = 0;
            effect("ice_hit", arrow.x, arrow.y, 54);
            break;
          }
        }
      }
      for (final enemy in world.enemies) {
        if (arrow.life <= 0 || !enemy.alive || !_enemyIsInCurrentArea(enemy)) {
          continue;
        }
        final radius = enemy.miniBoss ? 46.0 : 24.0;
        final hitbox = Rect.fromLTRB(
          enemy.x - radius - 6,
          enemy.y - 6,
          enemy.x + radius + 6,
          enemy.y + (enemy.miniBoss ? 82 : 48) + 6,
        );
        if (segmentIntersectsRect(
          Offset(arrow.previousX, arrow.previousY),
          Offset(arrow.x, arrow.y),
          hitbox,
        )) {
          hitEnemy(enemy, arrow);
          arrow.life = 0;
        }
      }
      final boss = world.boss;
      final skin = skins[arrow.skinIndex];
      if (arrow.life > 0 &&
          boss != null &&
          boss.alive &&
          zoneAt(boss.y) >= state.zone &&
          hypot(arrow.x - boss.x, arrow.y - boss.y) < 72) {
        arrow.life = 0;
        effect(
          (boss.y - state.player.y).abs() > 600
              ? "ice_hit"
              : arrow.type == "normal" && skin.effect != null
              ? skin.effect!
              : "${arrow.type}_hit",
          arrow.x,
          arrow.y,
          (boss.y - state.player.y).abs() > 600 ? 54 : 92,
        );
        if ((boss.y - state.player.y).abs() > 600) {
          burst(arrow.x, arrow.y, "#78e8ff", 5);
        } else {
          boss.hp -=
              (arrow.type == "fire" ? 2 : 1) + (skin.id == "ascendant" ? 1 : 0);
          boss.hurt = 0.32;
          events.sfx?.call("hit");
          state.shake = 0.2;
          if (boss.hp <= 0) {
            boss.alive = false;
            burst(boss.x, boss.y, "#fff0a0", 40);
            if (boss.kind != "zenith") {
              final rewards = {
                "gravemaw": 250,
                "astrael": 450,
                "chronotitan": 700,
              };
              final reward = _awardCoins(rewards[boss.kind] ?? 250, skin: skin);
              toast("${boss.name} TUMBANG · +$reward KOIN", 3.5);
              events.save?.call(state);
            } else {
              _awardCoins(1200, skin: skin);
              state.won = true;
              toast("JANTUNG LANGIT DIREBUT!", 99);
              events.win?.call(state);
            }
          }
        }
      }
      for (final platform in world.platforms) {
        if (arrow.life <= 0 || platform.disabled) continue;
        final crossed = arrow.previousY >= platform.y && arrow.y <= platform.y;
        if (crossed &&
            arrow.x >= platform.x &&
            arrow.x <= platform.x + platform.w) {
          if (arrow.type == "rope") {
            final isValkyrie = skins[arrow.skinIndex].id == "valkyrie";
            world.addRope(
              arrow.x,
              platform.y + 118,
              length: isValkyrie ? 160 : 125,
              life: isValkyrie ? 24 : 16,
            );
            effect("rope_shot", arrow.x, platform.y, 68);
            events.sfx?.call("rope");
          } else {
            effect("${arrow.type}_hit", arrow.x, platform.y, 46);
          }
          arrow.life = 0;
        }
      }
      if (arrow.x < 0 || arrow.x > worldWidth || arrow.y < -100) arrow.life = 0;
    }
    state.arrows.removeWhere((a) => a.life <= 0);

    for (final shot in state.enemyShots) {
      shot.x += shot.vx * dt;
      shot.y += shot.vy * dt;
      shot.life -= dt;
    }
    state.enemyShots.removeWhere((s) => s.life <= 0 || s.dead);
  }

  void updateFeedback(double dt) {
    state.toast.time = math.max(0, state.toast.time - dt);
    state.shake = math.max(0, state.shake - dt);
    state.flash = math.max(0, state.flash - dt);
    for (final particle in state.particles) {
      particle.x += particle.vx * dt;
      particle.y += particle.vy * dt;
      particle.vy -= 320 * dt;
      particle.life -= dt;
    }
    state.particles.removeWhere((p) => p.life <= 0);
    for (final item in state.effects) item.age += dt;
    state.effects.removeWhere((e) => e.age < e.duration ? false : true);
  }

  void update(double dt) {
    state.time += dt;
    input.pollGamepad();
    world.ensure(state.player.y);
    world.update(dt, state.time);
    updatePlayer(dt);
    updateEnemies(dt);
    updateProjectiles(dt);
    updateFeedback(dt);
    if (state.player.deathTimer > 0) {
      state.player.deathTimer -= dt;
      state.player.anim = "defeat";
      if (state.player.deathTimer <= 0) respawn();
    }
    state.previousZone = state.zone;
    state.zone = zoneAt(state.player.y);
    if (state.zone > state.highestZone) {
      state.highestZone = state.zone;
      events.save?.call(state);
    }
    if (state.zone > state.previousZone) {
      state.enemyShots.clear();
      final boundary = zones[state.zone].min;
      final flags = world.flags.where((flag) => flag.height == boundary);
      if (flags.isNotEmpty) {
        final flag = flags.reduce(
          (closest, candidate) =>
              (candidate.x - state.player.x).abs() <
                  (closest.x - state.player.x).abs()
              ? candidate
              : closest,
        );
        activateFlag(flag);
      }
    }
    if (state.zone != state.previousZone) {
      toast(
        "${state.zone + 1} · ${zones[state.zone].name.toUpperCase()} · ${zones[state.zone].mechanic.toUpperCase()}",
        3.2,
      );
      events.zone?.call(state.zone);
    }
    final activeBoss = world.boss;
    if (activeBoss != null && activeBoss.alive) {
      if (_announcedBoss != activeBoss.kind) {
        _announcedBoss = activeBoss.kind;
        events.sfx?.call("boss_appear");
        events.music?.call("bgm_boss");
      }
    } else {
      if (_announcedBoss != null) {
        _announcedBoss = null;
        events.zone?.call(state.zone);
      }
    }
    final activeMini = world.miniBoss;
    if (activeMini != null && activeMini.alive) {
      if (_announcedMini != activeMini.id) {
        _announcedMini = activeMini.id;
        events.sfx?.call("mini_boss_appear");
      }
    } else {
      if (_announcedMini != null) {
        _announcedMini = null;
        events.zone?.call(state.zone);
      }
    }
    if (state.player.y > maxHeight) state.player.highest = maxHeight;
  }

  List<Offset> trajectory() {
    final aim = input.state.aim;
    if (aim == null) return [];
    final player = state.player;
    var facing = player.facing;
    if (aim.target != null && (aim.target!.dx - player.x).abs() > 4) {
      facing = (aim.target!.dx - player.x).sign.toInt();
    } else if (aim.direction?.dx != null && aim.direction!.dx != 0) {
      facing = aim.direction!.dx.sign.toInt();
    }
    final origin = Offset(player.x + facing * 24, player.y + 42);
    Offset direction;
    if (aim.target != null) {
      final dx = aim.target!.dx - origin.dx;
      final dy = aim.target!.dy - origin.dy;
      final length = math.max(1, hypot(dx, dy));
      direction = Offset(dx / length, dy / length);
    } else if (aim.direction != null) {
      direction = aim.direction!;
    } else {
      direction = Offset(player.facing.toDouble(), 0);
    }
    final points = <Offset>[];
    for (int i = 0; i < 14; i++) {
      final distance = i * 34;
      points.add(
        Offset(
          origin.dx + direction.dx * distance,
          origin.dy + direction.dy * distance,
        ),
      );
    }
    return points;
  }

  Offset? aimTarget() => input.state.aim?.target;

  bool selectSkin(int index) {
    if (index < 0 || index >= skins.length) return false;
    if (!state.ownedSkins.contains(skins[index].id)) return false;
    state.selectedSkin = index;
    state.shopOpen = false;
    events.save?.call(state);
    return true;
  }

  bool buySkin(int index) {
    if (index < 0 || index >= skins.length) return false;
    final skin = skins[index];
    if (state.ownedSkins.contains(skin.id)) return selectSkin(index);
    if (state.coins < skin.price) return false;
    state.coins -= skin.price;
    events.sfx?.call("shop_buy");
    state.ownedSkins.add(skin.id);
    state.selectedSkin = index;
    state.shopOpen = false;
    events.save?.call(state);
    return true;
  }

  /// Data progres yang disimpan permanen (koin & skin yang sudah dibeli).
  Map<String, dynamic> saveData() => {
    'coins': state.coins,
    'ownedSkins': List<String>.of(state.ownedSkins),
    'selectedSkin': state.selectedSkin,
    'highestZone': state.highestZone,
  };

  bool isZoneUnlocked(int zoneIndex) =>
      zoneIndex >= 0 && zoneIndex <= state.highestZone;

  void openShop() {
    state.shopOpen = true;
    events.sfx?.call("shop_open");
  }

  void teleportTo(int zoneIndex) {
    if (zoneIndex < 0 || zoneIndex >= zones.length) return;
    if (!isZoneUnlocked(zoneIndex)) return;
    final z = zones[zoneIndex];
    final player = state.player;
    player.x = worldWidth / 2;
    player.y = z.min + 60;
    player.previousY = player.y;
    player.vx = 0;
    player.vy = 0;
    player.grounded = false;
    player.airJumpUsed = false;
    player.climbing = false;
    player.grabbedRope = null;
    player.checkpoint = Checkpoint(player.x, player.y, z.min);
    player.highestSinceRespawn = player.y;
    player.hearts = player.maxHearts;
    player.energy = player.maxEnergy;
    player.deathTimer = 0;
    player.invulnerable = 1;
    player.hurt = 0;
    state.arrows.clear();
    state.enemyShots.clear();
    state.shopOpen = false;
    state.mapOpen = false;
    world.resetAround(player.y);
    state.zone = zoneIndex;
    state.previousZone = zoneIndex;
    events.zone?.call(zoneIndex);
    toast("${z.name.toUpperCase()} · ${z.mechanic.toUpperCase()}", 2.4);
  }
}

extension _UnlocksExt on Unlocks {
  bool _get(String id) {
    switch (id) {
      case "fire":
        return fire;
      case "ice":
        return ice;
      case "rope":
        return rope;
      case "cape":
        return cape;
      default:
        return false;
    }
  }

  void _set(String id, bool v) {
    switch (id) {
      case "fire":
        fire = v;
      case "ice":
        ice = v;
      case "rope":
        rope = v;
      case "cape":
        cape = v;
    }
  }
}
