import 'dart:math' as math;

import 'constants.dart';

class Platform {
  final String id;
  double x;
  double y;
  final double w;
  double h = 24;
  String type;
  double timer = 0;
  bool disabled = false;
  double phase = 0;
  double baseX;
  double baseY;
  bool mushroom = false;
  double? bounceAt;

  Platform(this.id, this.x, this.y, this.w, this.type, this.baseX, this.baseY);
}

class Ladder {
  final double x;
  final double y;
  final double w;
  final double h;
  Ladder(this.x, this.y, this.w, this.h);
}

class Rope {
  final String id;
  double x;
  double y;
  final double length;
  double angle;
  double omega;
  final bool temporary;
  double life;
  final bool required;

  Rope(
    this.id,
    this.x,
    this.y,
    this.length,
    this.angle,
    this.omega,
    this.temporary,
    this.life,
    this.required,
  );
}

class Flag {
  final String id;
  final double x;
  final double y;
  final double height;
  bool active = false;
  double animStart = 0;
  Flag(this.id, this.x, this.y, this.height);
}

class Pickup {
  final String id;
  double x;
  double y;
  final String type;
  final String label;
  bool collected = false;
  final int value;
  Pickup(this.id, this.x, this.y, this.type, this.label, this.value);
}

class Enemy {
  final String id;
  String type;
  double x;
  double y;
  double homeX;
  final double platformOffset;
  final String platformId;
  int hp;
  int maxHp;
  bool alive = true;
  int facing;
  double cooldown = 0;
  double attackTimer = 0;
  double frozen = 0;
  double hurt = 0;
  double burnTimer = 0;
  double burnTick = 0;
  int burnSkinIndex = 0;
  final bool miniBoss;
  final String? name;
  final int? zoneIndex;

  Enemy({
    required this.id,
    required this.type,
    required this.x,
    required this.y,
    required this.homeX,
    required this.platformOffset,
    required this.platformId,
    required this.hp,
    required this.maxHp,
    required this.facing,
    this.cooldown = 0,
    this.miniBoss = false,
    this.name,
    this.zoneIndex,
  });
}

class Wind {
  final double x;
  final double y;
  final double w;
  final double h;
  Wind(this.x, this.y, this.w, this.h);
}

class Hazard {
  final String id;
  final String type;
  final double x;
  final double y;
  final double w;
  final double h;
  final double phase;
  Hazard(this.id, this.type, this.x, this.y, this.w, this.h, this.phase);
}

class Boss {
  final String kind;
  final String name;
  double y;
  final double homeY;
  double x;
  final int maxHp;
  int hp;
  bool alive = true;
  double cooldown = 1.1;
  double attackTimer = 0;
  int phase = 1;
  double hurt = 0;
  int facing = -1;
  Boss(this.kind, this.name, this.y, this.homeY, this.x, this.maxHp, this.hp);
}

class Chunk {
  final int index;
  final List<Platform> platforms;
  final List<Ladder> ladders;
  final List<Rope> ropes;
  final List<Flag> flags;
  final List<Pickup> pickups;
  final List<Enemy> enemies;
  final List<Wind> winds;
  final List<Hazard> hazards;

  Chunk(
    this.index,
    this.platforms,
    this.ladders,
    this.ropes,
    this.flags,
    this.pickups,
    this.enemies,
    this.winds,
    this.hazards,
  );
}

Platform makePlatform(String id, double x, double y, double w, String type) =>
    Platform(id, x, y, w, type, x, y);

int _imul(int a, int b) {
  final aLow = a & 0xffff;
  final aHigh = a >> 16;
  final bLow = b & 0xffff;
  final bHigh = b >> 16;
  return (aLow * bLow + (((aLow * bHigh + aHigh * bLow) & 0xffff) << 16)) &
      0xffffffff;
}

double Function() _randomFor(int seed) {
  var value = seed & 0xffffffff;
  return () {
    value = (value + 0x6d2b79f5) & 0xffffffff;
    final first = _imul(value ^ (value >> 15), 1 | value);
    final second = _imul(first ^ (first >> 7), 61 | first);
    final result = ((first + second) & 0xffffffff) ^ first;
    return ((result ^ (result >> 14)) & 0xffffffff) / 4294967296;
  };
}

Chunk makeChunk(int index) {
  final rnd = _randomFor(9127 + index * 1013);
  final base = index * chunkHeight;
  final platforms = <Platform>[];
  final ladders = <Ladder>[];
  final ropes = <Rope>[];
  final flags = <Flag>[];
  final pickups = <Pickup>[];
  final enemies = <Enemy>[];
  final winds = <Wind>[];
  final hazards = <Hazard>[];
  final rowYs = [base + 35, base + 108, base + 181, base + 254, base + 327];

  for (int laneIndex = 0; laneIndex < lanes.length; laneIndex++) {
    final lane = lanes[laneIndex];
    Platform? previous;
    for (int row = 0; row < rowYs.length; row++) {
      final y = rowYs[row];
      final width = (145 + rnd() * 95).floorToDouble();
      final center = lane + (rnd() - 0.5) * 130;
      String type = "solid";
      final zone = zoneAt(y);
      if ((row + laneIndex + index) % 7 == 4) type = "moving";
      if ((row * 3 + laneIndex + index) % 11 == 6) type = "crumble";
      if (zone == 1 && (row + laneIndex + index) % 6 == 2) type = "thorn";
      if (zone == 2 && (row + laneIndex) % 5 == 2) type = "cloud";
      if (zone == 3 && (row + laneIndex + index) % 5 == 3) type = "storm";
      if (zone == 6 && (row + laneIndex + index) % 5 == 3) type = "anti";
      if (zone == 7 && (row + laneIndex + index) % 4 == 2) type = "phase";
      if (zone == 8 && (row + laneIndex + index) % 5 == 1) type = "heat";
      if (zone == 10 && (row + laneIndex + index) % 4 == 1) type = "rail";
      if (zone == 11 && (row + laneIndex + index) % 4 == 2) type = "orbit";
      if (zone == 12 && (row + laneIndex + index) % 5 == 2) type = "comet";
      if (zone == 13 && (row + laneIndex + index) % 3 == 1) type = "phase";
      if (zone == 14 && (row + laneIndex + index) % 5 == 2) type = "thorn";
      if (zone == 15 && (row + laneIndex + index) % 4 == 1) type = "heat";
      if (zone == 16 && (row + laneIndex + index) % 4 == 2) type = "anti";
      if (zone == 17 && (row + laneIndex + index) % 3 == 2) type = "glass";
      if (zone == 18 && (row + laneIndex + index) % 4 == 1) type = "beam";
      if (zone == 19 && (row + laneIndex + index) % 4 == 2) type = "storm";
      final item = makePlatform(
        'p-$index-$laneIndex-$row',
        center - width / 2,
        y,
        width,
        type,
      );
      item.phase = rnd() * math.pi * 2;
      platforms.add(item);

      if (previous != null && (row + laneIndex + index) % 4 == 1) {
        ladders.add(
          Ladder(
            item.x + width * 0.5 - 18,
            previous.y,
            36,
            item.y - previous.y,
          ),
        );
      }
      if (previous != null && (row + laneIndex + index) % 5 == 2) {
        ropes.add(
          Rope(
            'r-$index-$laneIndex-$row',
            item.x + width * 0.5,
            item.y + 92,
            92,
            0.18 * (laneIndex - 1),
            0,
            false,
            16,
            false,
          ),
        );
      }
      if (zone == 0 && (row + laneIndex + index) % 7 == 3) item.mushroom = true;
      if (zone == 2 && (row + laneIndex) % 5 == 1)
        winds.add(Wind(item.x, item.y + 5, item.w, 155));
      if (type == "storm")
        hazards.add(
          Hazard(
            'storm-${item.id}',
            "storm",
            item.x,
            item.y + 10,
            item.w,
            125,
            rnd() * 4,
          ),
        );
      if (type == "heat")
        hazards.add(
          Hazard(
            'heat-${item.id}',
            "heat",
            item.x,
            item.y + 8,
            item.w,
            120,
            rnd() * 4,
          ),
        );
      if (type == "beam")
        hazards.add(
          Hazard(
            'beam-${item.id}',
            "beam",
            item.x,
            item.y + 8,
            item.w,
            170,
            rnd() * 4,
          ),
        );

      final enemyRoll = (row * 5 + laneIndex + index) % 8;
      if (index > 0 && (enemyRoll == 3 || (lanes.length == 1 && row == 0))) {
        String enemyType = zones[zone].enemy;
        if (zone == 0) {
          final m = (row + laneIndex + index) % 3;
          enemyType = m == 0
              ? "spider"
              : m == 1
              ? "crow"
              : "goblin";
        }
        final hp = scaledEnemyHp(2 + (zone / 3).floor(), zone);
        enemies.add(
          Enemy(
            id: 'e-$index-$laneIndex-$row',
            type: enemyType,
            x: item.x + item.w * 0.55,
            y: item.y,
            homeX: item.x + item.w * 0.55,
            platformOffset: item.w * 0.55,
            platformId: item.id,
            hp: hp,
            maxHp: hp,
            facing: laneIndex == 2 ? -1 : 1,
            cooldown: 0.8 + rnd(),
          ),
        );
      }
      previous = item;
    }
  }

  for (int zoneIndex = 0; zoneIndex < zones.length; zoneIndex++) {
    final zoneData = zones[zoneIndex];
    final miniHeight = zoneData.min + areaHeight / 2;
    if (miniHeight < base || miniHeight >= base + chunkHeight) continue;
    final hp = scaledEnemyHp(8 + (zoneIndex / 2).floor(), zoneIndex);
    final arena = makePlatform(
      'mini-arena-$zoneIndex',
      650,
      miniHeight,
      500,
      "solid",
    );
    platforms.add(arena);
    enemies.add(
      Enemy(
        id: 'mini-${(zoneIndex + 1).toString().padLeft(2, '0')}',
        type: 'mini_${(zoneIndex + 1).toString().padLeft(2, '0')}',
        name: miniBossNames[zoneIndex],
        miniBoss: true,
        zoneIndex: zoneIndex,
        x: 900,
        y: miniHeight,
        homeX: 900,
        platformOffset: 250,
        platformId: arena.id,
        hp: hp,
        maxHp: hp,
        facing: -1,
        cooldown: 0.8,
      ),
    );
  }

  if (index > 0 && index % 3 == 1) {
    final laneIndex = index % lanes.length;
    final gapId = 'p-$index-$laneIndex-2';
    final lower = platforms
        .where((it) => it.id == 'p-$index-$laneIndex-1')
        .firstOrNull;
    final upper = platforms
        .where((it) => it.id == 'p-$index-$laneIndex-3')
        .firstOrNull;
    final gapIndex = platforms.indexWhere((it) => it.id == gapId);
    if (gapIndex >= 0 && lower != null && upper != null) {
      platforms.removeAt(gapIndex);
      enemies.removeWhere((e) => e.platformId == gapId);
      ladders.removeWhere((l) => l.y >= lower.y && l.y <= upper.y);
      final anchorY = upper.y + 105;
      ropes.add(
        Rope(
          'required-rope-$index',
          upper.x + upper.w * 0.5,
          anchorY,
          anchorY - lower.y - 34,
          -0.38,
          0,
          false,
          16,
          true,
        ),
      );
    }
  }

  for (double height = 0; height <= maxHeight; height += areaHeight) {
    if (height < base || height >= base + chunkHeight) continue;
    for (int laneIndex = 0; laneIndex < lanes.length; laneIndex++) {
      final lane = lanes[laneIndex];
      final checkpoint = makePlatform(
        'checkpoint-$height-$laneIndex',
        lane - 155,
        height + 35,
        310,
        "checkpoint",
      );
      platforms.add(checkpoint);
      flags.add(Flag('f-$height-$laneIndex', lane, checkpoint.y, height));
    }
  }

  final upgrades = [
    {'height': 1250.0, 'type': 'fire', 'label': 'PANAH API'},
    {'height': 2150.0, 'type': 'cape', 'label': 'JUBAH ANGIN'},
    {'height': 3050.0, 'type': 'ice', 'label': 'PANAH ES'},
    {'height': 3950.0, 'type': 'rope', 'label': 'PANAH TALI'},
  ];
  for (final upgrade in upgrades) {
    if ((upgrade['height'] as double) < base ||
        (upgrade['height'] as double) >= base + chunkHeight)
      continue;
    final target = upgrade['height'] as double;
    Platform? closest = platforms.first;
    for (final it in platforms) {
      if ((it.y - target).abs() < (closest!.y - target).abs()) closest = it;
    }
    pickups.add(
      Pickup(
        'upgrade-${upgrade['type']}',
        closest!.x + closest.w * 0.5,
        closest.y + 44,
        upgrade['type'] as String,
        upgrade['label'] as String,
        0,
      ),
    );
  }

  if (index > 0 && index % 2 == 1) {
    final candidates = platforms.where((it) => it.type == "solid").toList();
    if (candidates.isNotEmpty) {
      final it = candidates[(rnd() * candidates.length).floor()];
      pickups.add(
        Pickup(
          'crystal-$index',
          it.x + it.w * 0.5,
          it.y + 38,
          "crystal",
          "KRISTAL",
          0,
        ),
      );
    }
  }

  final coinPlatforms = platforms
      .where((it) => !["thorn", "heat", "beam"].contains(it.type))
      .toList();
  final coinCount = math.min(index == 0 ? 7 : 4, coinPlatforms.length);
  for (int i = 0; i < coinCount; i++) {
    final it = coinPlatforms[(rnd() * coinPlatforms.length).floor()];
    pickups.add(
      Pickup(
        'coin-$index-$i',
        it.x + it.w * (0.3 + rnd() * 0.4),
        it.y + 40,
        "coin",
        "KOIN",
        6 + zoneAt(it.y) * 2,
      ),
    );
  }
  if (index == 0) {
    final start = platforms.where((it) => it.id == "p-0-1-0").firstOrNull;
    if (start != null) {
      for (int i = 0; i < 5; i++) {
        pickups.add(
          Pickup(
            'starter-coin-$i',
            start.x + 35 + i * 30,
            start.y + 42,
            "coin",
            "KOIN",
            5,
          ),
        );
      }
    }
  }

  return Chunk(
    index,
    platforms,
    ladders,
    ropes,
    flags,
    pickups,
    enemies,
    winds,
    hazards,
  );
}

class World {
  final Map<int, Chunk> chunks = {};
  final List<Rope> temporaryRopes = [];
  final List<Boss> bosses = [];
  List<Platform> _platforms = [];
  List<Ladder> _ladders = [];
  List<Rope> _ropes = [];
  List<Rope> _allRopes = [];
  List<Flag> _flags = [];
  List<Pickup> _pickups = [];
  List<Enemy> _enemies = [];
  List<Wind> _winds = [];
  List<Hazard> _hazards = [];
  final Map<String, Platform> _platformsById = {};
  int? _chunkCenter;
  double currentHeight = 0;

  final List<Boss> bossSpecs = [
    Boss(
      "gravemaw",
      "GRAVEMAW",
      areaHeight * 5 - 110,
      areaHeight * 5 - 110,
      900,
      scaledEnemyHp(22, 4),
      scaledEnemyHp(22, 4),
    ),
    Boss(
      "astrael",
      "ASTRAEL",
      areaHeight * 10 - 110,
      areaHeight * 10 - 110,
      900,
      scaledEnemyHp(30, 9),
      scaledEnemyHp(30, 9),
    ),
    Boss(
      "chronotitan",
      "CHRONOTITAN",
      areaHeight * 15 - 110,
      areaHeight * 15 - 110,
      900,
      scaledEnemyHp(38, 14),
      scaledEnemyHp(38, 14),
    ),
    Boss(
      "zenith",
      "ZENITH SERAPH",
      areaHeight * 20 - 110,
      areaHeight * 20 - 110,
      900,
      scaledEnemyHp(50, 19),
      scaledEnemyHp(50, 19),
    ),
  ];

  void ensure(double height) {
    currentHeight = height;
    final center = math.max(0, (height / chunkHeight).floor());
    var chunksChanged = false;
    if (_chunkCenter != center) {
      _chunkCenter = center;
      for (
        int index = math.max(0, center - 2);
        index <= (maxHeight / chunkHeight).ceil() && index <= center + 4;
        index++
      ) {
        if (!chunks.containsKey(index)) {
          chunks[index] = makeChunk(index);
          chunksChanged = true;
        }
      }
      final keys = chunks.keys.toList();
      for (final index in keys) {
        if ((index - center).abs() > 5) {
          chunks.remove(index);
          chunksChanged = true;
        }
      }
    }
    if (chunksChanged) {
      _refreshCollections();
    }
    for (final spec in bossSpecs) {
      if (height > spec.y - 520 && !bosses.any((b) => b.kind == spec.kind)) {
        bosses.add(
          Boss(
              spec.kind,
              spec.name,
              spec.y,
              spec.homeY,
              900,
              spec.maxHp,
              spec.hp,
            )
            ..cooldown = 1.1
            ..attackTimer = 0
            ..phase = 1
            ..hurt = 0
            ..facing = -1,
        );
      }
    }
  }

  void _refreshCollections() {
    _platforms = chunks.values
        .expand((chunk) => chunk.platforms)
        .toList(growable: false);
    _ladders = chunks.values
        .expand((chunk) => chunk.ladders)
        .toList(growable: false);
    _ropes = chunks.values
        .expand((chunk) => chunk.ropes)
        .toList(growable: false);
    _allRopes = [..._ropes, ...temporaryRopes];
    _flags = chunks.values
        .expand((chunk) => chunk.flags)
        .toList(growable: false);
    _pickups = chunks.values
        .expand((chunk) => chunk.pickups)
        .toList(growable: false);
    _enemies = chunks.values
        .expand((chunk) => chunk.enemies)
        .toList(growable: false);
    _winds = chunks.values
        .expand((chunk) => chunk.winds)
        .toList(growable: false);
    _hazards = chunks.values
        .expand((chunk) => chunk.hazards)
        .toList(growable: false);
    _platformsById
      ..clear()
      ..addEntries(
        _platforms.map((platform) => MapEntry(platform.id, platform)),
      );
  }

  Platform? platformById(String id) => _platformsById[id];

  void resetAround(double height) {
    chunks.clear();
    temporaryRopes.clear();
    _chunkCenter = null;
    ensure(height);
  }

  List<Platform> get platforms => _platforms;
  List<Ladder> get ladders => _ladders;
  List<Rope> get ropes => _allRopes;
  List<Flag> get flags => _flags;
  List<Pickup> get pickups => _pickups;
  List<Enemy> get enemies => _enemies;
  List<Wind> get winds => _winds;
  List<Hazard> get hazards => _hazards;

  Enemy? get miniBoss => enemies
      .where(
        (e) =>
            e.miniBoss &&
            e.alive &&
            zoneAt(e.y) >= zoneAt(currentHeight) &&
            (e.y - currentHeight).abs() < 520,
      )
      .firstOrNull;
  Boss? get boss => bosses
      .where(
        (b) =>
            b.alive &&
            zoneAt(b.y) >= zoneAt(currentHeight) &&
            (b.y - currentHeight).abs() < 720,
      )
      .firstOrNull;

  void addRope(double x, double y, {double length = 125, double life = 16}) {
    temporaryRopes.add(
      Rope(
        'temp-${temporaryRopes.length}',
        x,
        y,
        length,
        0,
        0,
        true,
        life,
        false,
      ),
    );
    _allRopes = [..._ropes, ...temporaryRopes];
  }

  void update(double dt, double time) {
    for (final item in platforms) {
      if (item.type == "moving")
        item.x = item.baseX + math.sin(time * 1.25 + item.phase) * 72;
      if (item.type == "storm" || item.type == "rail") {
        item.x =
            item.baseX +
            math.sin(time * (item.type == "rail" ? 3 : 2.25) + item.phase) *
                (item.type == "rail" ? 118 : 92);
      }
      if (item.type == "orbit") {
        item.x = item.baseX + math.sin(time * 1.5 + item.phase) * 82;
        item.y = item.baseY + math.cos(time * 1.5 + item.phase) * 28;
      }
      if (item.type == "phase")
        item.disabled = math.sin(time * 1.6 + item.phase) < -0.48;
      if (item.disabled && item.type != "phase") {
        item.timer -= dt;
        if (item.timer <= 0) {
          item.disabled = false;
          item.timer = 0;
        }
      }
    }
    var ropesChanged = false;
    for (int i = temporaryRopes.length - 1; i >= 0; i--) {
      temporaryRopes[i].life -= dt;
      if (temporaryRopes[i].life <= 0) {
        temporaryRopes.removeAt(i);
        ropesChanged = true;
      }
    }
    if (ropesChanged) {
      _allRopes = [..._ropes, ...temporaryRopes];
    }
  }
}
