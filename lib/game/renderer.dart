import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/painting.dart';

import 'asset_bundle.dart';
import 'constants.dart';
import 'simulation.dart';
import 'world.dart';

class Camera {
  double x = worldWidth / 2;
  double bottom = 0;
  double scale = 1;
  double width = 0;
  double height = 0;
}

class Renderer {
  static const Set<String> _moveAttackEnemyTypes = {
    "thorn_imp",
    "storm_drone",
    "meteor_beetle",
    "eclipse_wraith",
  };
  static const Set<String> _upperEnemyTypesA = {
    "rail_specter",
    "clock_mite",
    "comet_ape",
    "prism_manta",
  };
  static const Set<String> _upperEnemyTypesB = {
    "bone_hound",
    "flare_salamander",
    "dream_jelly",
    "glass_deacon",
  };
  static const Set<String> _upperEnemyTypesC = {"throne_guard", "crown_archon"};
  static const Set<String> _tintedPlatformTypes = {
    "thorn",
    "storm",
    "phase",
    "heat",
    "rail",
    "orbit",
    "comet",
    "glass",
    "beam",
  };
  static const Map<String, Color> _platformOverlayColors = {
    "storm": Color.fromARGB(107, 83, 173, 255),
    "phase": Color.fromARGB(107, 202, 74, 255),
    "heat": Color.fromARGB(122, 255, 120, 37),
    "rail": Color.fromARGB(102, 75, 255, 213),
    "orbit": Color.fromARGB(102, 255, 191, 79),
    "comet": Color.fromARGB(97, 255, 112, 43),
    "glass": Color.fromARGB(89, 255, 118, 210),
    "beam": Color.fromARGB(102, 255, 226, 119),
  };

  static const List<String> _miniBossSheets = [
    "MINIBOSSES_01_04",
    "MINIBOSSES_05_08",
    "MINIBOSSES_09_12",
    "MINIBOSSES_13_16",
    "MINIBOSSES_17_20",
  ];
  static const Map<int, String> _bossSheetByZone = {
    4: "GRAVEMAW_BOSS_SHEET",
    9: "ASTRAEL_BOSS_SHEET",
    14: "CHRONOTITAN_BOSS_SHEET",
    19: "ZENITH_SERAPH_BOSS_SHEET",
  };
  static const Set<String> _commonSheets = {
    "PROPS_ATLAS",
    "INTERACTIVES_SHEET",
    "COIN_SHEET",
    "AREA_PLATFORM_ATLAS",
    "PROJECTILE_ARROWS_ATLAS",
    "SIGNATURE_WEAPONS_ATLAS",
    "ARROW_HIT_EFFECTS",
    "ELEMENTAL_EFFECTS_SHEET",
  };

  static Set<String> _enemySheets(String type) {
    if (type == "harpy" || type == "robot") return {"SKY_SPACE_ENEMIES_SHEET"};
    if (type == "sentinel" || type == "knight") {
      return {"MOON_PALACE_ENEMIES_SHEET"};
    }
    if (_moveAttackEnemyTypes.contains(type)) {
      return {"NEW_ENEMIES_MOVE", "NEW_ENEMIES_ATTACK"};
    }
    if (_upperEnemyTypesA.contains(type)) {
      return {"UPPER_ENEMIES_A_MOVE", "UPPER_ENEMIES_A_ATTACK"};
    }
    if (_upperEnemyTypesB.contains(type)) {
      return {"UPPER_ENEMIES_B_MOVE", "UPPER_ENEMIES_B_ATTACK"};
    }
    if (_upperEnemyTypesC.contains(type)) return {"UPPER_ENEMIES_C"};
    return {"FOREST_ENEMIES_SHEET"};
  }

  /// Sheet yang dibutuhkan untuk menggambar satu area.
  static Set<String> sheetsForZone(int zone) => {
    zones[zone].backdrop,
    ..._enemySheets(zones[zone].enemy),
    _miniBossSheets[zone ~/ 4],
    ?_bossSheetByZone[zone],
    if (zone >= 10) "UPPER_HAZARDS_ATLAS",
  };

  /// Sheet resolusi penuh yang perlu ada di memori: aset umum, skin aktif,
  /// serta area sebelumnya, saat ini, dan berikutnya. Area lain dibuang.
  static Set<String> residentSheets(int zone, int skinIndex) {
    final skin = skins[skinIndex];
    return {
      ..._commonSheets,
      skin.sheet,
      ?skin.effectSheet,
      for (int z = zone - 1; z <= zone + 1; z++)
        if (z >= 0 && z < zones.length) ...sheetsForZone(z),
    };
  }

  /// Pratinjau resolusi kecil untuk layar toko (skin) dan peta (backdrop).
  static Set<String> previewSheets({required bool shop, required bool map}) => {
    if (shop) ...skins.map((s) => s.sheet),
    if (map) ...zones.map((z) => z.backdrop),
  };

  final GameAssets assets;
  final World world;
  final Simulation simulation;
  final Tuning tuning;
  final Camera camera = Camera();
  late double cssWidth;
  late double cssHeight;
  final Paint paint = Paint()..filterQuality = FilterQuality.none;

  Renderer({
    required this.assets,
    required this.world,
    required this.simulation,
    required this.tuning,
  });

  Offset toScreen(double x, double y) => Offset(
    (x - camera.x) * camera.scale + cssWidth / 2,
    cssHeight - (y - camera.bottom) * camera.scale,
  );

  Offset toWorld(Offset p) => Offset(
    camera.x + (p.dx - cssWidth / 2) / camera.scale,
    camera.bottom + (cssHeight - p.dy) / camera.scale,
  );

  bool _isVerticallyVisible(double minY, double maxY, {double margin = 160}) {
    return maxY >= camera.bottom - margin &&
        minY <= camera.bottom + camera.height + margin;
  }

  void updateCamera(double dt) {
    final player = simulation.state.player;
    final half = camera.width / 2;
    final targetX = clamp(player.x, half, worldWidth - half);
    camera.x += (targetX - camera.x) * math.min(1.0, dt * tuning.cameraSmooth);
    final targetBottom = math.max(0.0, player.y - camera.height * 0.34);
    if (player.y < camera.bottom - 130) {
      camera.bottom = math.max(0.0, targetBottom);
    } else if (targetBottom > camera.bottom) {
      camera.bottom +=
          (targetBottom - camera.bottom) *
          math.min(1.0, dt * tuning.cameraSmooth * 0.75);
    } else {
      camera.bottom = math.max(targetBottom, camera.bottom - 45 * dt);
    }
  }

  Paint makePaint([double alpha = 1]) {
    if (alpha >= 1) return paint;
    return Paint()
      ..filterQuality = FilterQuality.none
      ..color = Color.fromARGB((alpha * 255).round(), 255, 255, 255);
  }

  final Paint _previewPaint = Paint()..filterQuality = FilterQuality.low;
  final Map<String, TextPainter> _textCache = {};

  /// Pratinjau beresolusi rendah diperhalus agar tidak terlihat kotak-kotak.
  Paint _paintFor(SheetImage image, [double alpha = 1]) {
    if (image.scale == 1) return makePaint(alpha);
    if (alpha >= 1) return _previewPaint;
    return Paint()
      ..filterQuality = FilterQuality.low
      ..color = Color.fromARGB((alpha * 255).round(), 255, 255, 255);
  }

  void _drawSheet(
    SheetImage image,
    Rect src,
    Rect dst, [
    double alpha = 1,
    Paint? paintOverride,
  ]) {
    canvas.drawImageRect(
      image.image,
      image.map(src),
      dst,
      paintOverride ?? _paintFor(image, alpha),
    );
  }

  void drawImageRect(String key, Rect src, Rect dst, [double alpha = 1]) {
    final image = assets.imageOf(key);
    if (image == null) return;
    _drawSheet(image, src, dst, alpha);
  }

  void drawAnchored(
    String key,
    String name,
    double x,
    double y,
    double targetHeight,
    int facing,
    double speed, [
    double offset = 0,
    FrameRect? frameOverride,
    double alpha = 1,
  ]) {
    final frames = assets.animation(key, name);
    if (frames.isEmpty) return;
    final image = assets.imageOf(key);
    if (image == null) return;
    final idx = ((simulation.state.time + offset) * speed).floor();
    final frame =
        frameOverride ??
        frames[((idx % frames.length) + frames.length) % frames.length];
    final crop = frame.content;
    final largest = assets.largestHeight(key, name);
    final drawScale = (targetHeight * camera.scale) / largest;
    final point = toScreen(x, y);
    canvas.save();
    canvas.translate(point.dx, 0);
    canvas.scale(facing.toDouble(), 1);
    final dstX = -(frame.anchor.dx - crop.left) * drawScale;
    final dstY = point.dy - (frame.anchor.dy - crop.top) * drawScale;
    final dst = Rect.fromLTWH(
      dstX,
      dstY,
      crop.width * drawScale,
      crop.height * drawScale,
    );
    _drawSheet(image, crop, dst, alpha);
    canvas.restore();
  }

  void drawAnchoredOnScreen(
    String key,
    String name,
    double x,
    double baselineY,
    double targetHeight,
    double speed,
  ) {
    final frames = assets.animation(key, name);
    if (frames.isEmpty) return;
    final image = assets.previewOf(key);
    if (image == null) return;
    final index = (simulation.state.time * speed).floor() % frames.length;
    final frame = frames[index];
    final crop = frame.content;
    final drawScale = targetHeight / assets.largestHeight(key, name);
    canvas.save();
    canvas.translate(x, 0);
    final dst = Rect.fromLTWH(
      -(frame.anchor.dx - crop.left) * drawScale,
      baselineY - (frame.anchor.dy - crop.top) * drawScale,
      crop.width * drawScale,
      crop.height * drawScale,
    );
    _drawSheet(image, crop, dst);
    canvas.restore();
  }

  void drawFrameAt(
    String key,
    FrameRect? frame,
    double x,
    double y,
    double worldW,
    double worldH, [
    double alpha = 1,
  ]) {
    if (frame == null) return;
    final image = assets.imageOf(key);
    if (image == null) return;
    final crop = frame.content;
    final factor = math.min(
      worldW * camera.scale / crop.width,
      worldH * camera.scale / crop.height,
    );
    final point = toScreen(x, y);
    final dst = Rect.fromLTWH(
      point.dx - crop.width * factor / 2,
      point.dy - crop.height * factor,
      crop.width * factor,
      crop.height * factor,
    );
    _drawSheet(image, crop, dst, alpha);
  }

  void drawBackdrop(String key, [double alpha = 1]) {
    final sheet = assets.imageOf(key);
    if (sheet == null) return;
    final image = sheet.image;
    final canvasAspect = cssWidth / cssHeight;
    final imageAspect = image.width / image.height;
    double sw = image.width.toDouble();
    double sh = image.height.toDouble();
    if (imageAspect > canvasAspect) {
      sw = image.height * canvasAspect;
    } else {
      sh = image.width / canvasAspect;
    }
    final xProgress = clamp(camera.x / worldWidth, 0.0, 1.0);
    final sx = clamp((image.width - sw) * xProgress, 0.0, image.width - sw);
    final zone = zones.where((z) => z.backdrop == key).firstOrNull;
    final zoneSpan = zone != null && zone.max.isFinite
        ? zone.max - zone.min
        : 500;
    final yProgress = clamp(
      (simulation.state.player.y - (zone?.min ?? 0)) / zoneSpan,
      0.0,
      1.0,
    );
    final sy = clamp(
      (image.height - sh) * (1 - yProgress) * 0.65,
      0.0,
      image.height - sh,
    );
    final src = Rect.fromLTWH(sx, sy, sw, sh);
    final dst = Rect.fromLTWH(0, 0, cssWidth, cssHeight);
    canvas.drawImageRect(image, src, dst, _paintFor(sheet, alpha));
  }

  void drawBackground() {
    final player = simulation.state.player;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, cssWidth, cssHeight),
      Paint()..color = const Color(0xff05090f),
    );
    final zoneIndex = zoneAt(player.y);
    drawBackdrop(zones[zoneIndex].backdrop, 1);
    if (zoneIndex > 0) {
      final blend = clamp((player.y - zones[zoneIndex].min) / 90, 0.0, 1.0);
      if (blend < 1) drawBackdrop(zones[zoneIndex - 1].backdrop, 1 - blend);
    }
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color.fromRGBO(5, 9, 18, 0.05), Color.fromRGBO(4, 8, 12, 0.35)],
    ).createShader(Rect.fromLTWH(0, 0, cssWidth, cssHeight));
    canvas.drawRect(
      Rect.fromLTWH(0, 0, cssWidth, cssHeight),
      Paint()..shader = gradient,
    );
  }

  void drawPlatform(Platform item) {
    if (item.disabled) return;
    final left = toScreen(item.x, item.y);
    final width = item.w * camera.scale;
    if (left.dx + width < -50 ||
        left.dx > cssWidth + 50 ||
        left.dy < -80 ||
        left.dy > cssHeight + 100)
      return;
    if (item.type == "cloud") {
      final frames = assets.animation("INTERACTIVES_SHEET", "cloud_fade");
      final index = ((item.timer / 1.5) * 5).floor().clamp(0, 4);
      drawFrameAt(
        "INTERACTIVES_SHEET",
        frames.isEmpty ? null : frames[index],
        item.x + item.w / 2,
        item.y + 5,
        item.w,
        65,
        0.94,
      );
      return;
    }
    if (item.type == "crumble") {
      final frames = assets.animation("INTERACTIVES_SHEET", "platform_crumble");
      final index = ((item.timer / 3) * 5).floor().clamp(0, 4);
      drawFrameAt(
        "INTERACTIVES_SHEET",
        frames.isEmpty ? null : frames[index],
        item.x + item.w / 2,
        item.y + 4,
        item.w,
        65,
      );
      return;
    }
    final zone = zoneAt(item.y);
    final tile = assets.atlasFrame("AREA_PLATFORM_ATLAS", zones[zone].platform);
    if (tile == null) return;
    final atlas = assets.imageOf("AREA_PLATFORM_ATLAS");
    if (atlas == null) return;
    final crop = tile.content;
    final h = 35 * camera.scale;
    final factor = h / crop.height;
    final repeatW = crop.width * factor;
    final tilePaint = _platformPaint(item.type, zone);
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(left.dx, left.dy, width, h + 2));
    double drawX = left.dx;
    while (drawX < left.dx + width) {
      _drawSheet(
        atlas,
        tile.content,
        Rect.fromLTWH(drawX, left.dy, repeatW, h),
        1,
        tilePaint,
      );
      drawX += repeatW - 1;
    }
    canvas.restore();
    if (item.type == "moving") {
      canvas.drawRect(
        Rect.fromLTWH(
          left.dx + 10,
          left.dy + h - 3,
          math.max(8, width - 20),
          3,
        ),
        Paint()..color = Color.fromARGB(217, 255, 221, 102),
      );
    }
  }

  final Map<String, Paint> _platformPaints = {};

  /// Tint platform dulu digambar sebagai rect dengan BlendMode.screen/multiply
  /// di atas tile. Blend mode "advanced" seperti itu memaksa GPU menyalin isi
  /// layar untuk setiap platform setiap frame (sangat berat di HP, terutama
  /// area 5+ di mana semua platform diberi tint). Sekarang tint diterapkan
  /// sebagai ColorFilter matriks pada tile itu sendiri: hasil warnanya sama,
  /// tapi hanya operasi shader biasa.
  Paint _platformPaint(String type, int zone) {
    final Color? screen = type == "anti"
        ? const Color.fromARGB(89, 66, 245, 234)
        : _tintedPlatformTypes.contains(type)
        ? (type == "thorn" ? _thornColor(zone) : _platformOverlayColors[type]!)
        : null;
    final Color? multiply = screen == null && zone >= 4
        ? (zone >= 8
              ? const Color.fromARGB(56, 255, 244, 205)
              : const Color.fromARGB(61, 72, 90, 170))
        : null;
    if (screen == null && multiply == null) return paint;
    final cacheKey = '$type/${screen?.toARGB32() ?? multiply!.toARGB32()}';
    return _platformPaints.putIfAbsent(cacheKey, () {
      final List<double> matrix;
      if (screen != null) {
        // screen: c' = c * (1 - a*s) + a*s
        final a = screen.a;
        final r = a * screen.r, g = a * screen.g, b = a * screen.b;
        matrix = [
          1 - r, 0, 0, 0, r * 255, //
          0, 1 - g, 0, 0, g * 255, //
          0, 0, 1 - b, 0, b * 255, //
          0, 0, 0, 1, 0, //
        ];
      } else {
        // multiply: c' = c * (1 - a + a*m)
        final a = multiply!.a;
        matrix = [
          1 - a + a * multiply.r, 0, 0, 0, 0, //
          0, 1 - a + a * multiply.g, 0, 0, 0, //
          0, 0, 1 - a + a * multiply.b, 0, 0, //
          0, 0, 0, 1, 0, //
        ];
      }
      return Paint()
        ..filterQuality = FilterQuality.none
        ..colorFilter = ColorFilter.matrix(matrix);
    });
  }

  Color _thornColor(int zone) {
    const colors = [
      Color(0xff7ed648), // Rootwild
      Color(0xff72d64e), // Kuil Duri
      Color(0xff70e8e2), // Lautan Awan
      Color(0xff5d9cff), // Tempa Badai
      Color(0xff8c79d9), // Kuburan Orbit
      Color(0xffff934d), // Taman Meteor
      Color(0xffff5fc8), // Bulan Neon
      Color(0xffd96bff), // Gerhana Kristal
      Color(0xffffc75a), // Menara Matahari
      Color(0xffff83bd), // Mahkota Selestial
      Color(0xff62e5d2), // Rel Aurora
      Color(0xffffc45c), // Halo Jam
      Color(0xffff8b4d), // Kebun Komet
      Color(0xffef82e8), // Jurang Prisma
      Color(0xffd9d2c2), // Tulang Titan
      Color(0xffff704d), // Lautan Surya
      Color(0xffa77bff), // Nebula Mimpi
      Color(0xffff91cf), // Katedral Starfall
      Color(0xffffe08a), // Jalan Takhta
      Color(0xffffd15c), // Mahkota Zenith
    ];
    return colors[zone.clamp(0, colors.length - 1).toInt()];
  }

  void drawLadder(Ladder ladder) {
    final frame = assets.atlasFrame("PROPS_ATLAS", "ladder");
    if (frame == null) return;
    final segmentH = 56;
    for (double y = ladder.y; y < ladder.y + ladder.h; y += segmentH) {
      drawFrameAt(
        "PROPS_ATLAS",
        frame,
        ladder.x + ladder.w / 2,
        math.min(y + segmentH, ladder.y + ladder.h),
        ladder.w,
        segmentH + 5,
      );
    }
  }

  void drawWind(Wind wind) {
    final bottom = toScreen(wind.x, wind.y);
    final top = toScreen(wind.x + wind.w, wind.y + wind.h);
    final gradient =
        LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Color.fromARGB(66, 104, 232, 255),
            Color.fromRGBO(104, 232, 255, 0),
          ],
        ).createShader(
          Rect.fromLTWH(
            bottom.dx,
            top.dy,
            wind.w * camera.scale,
            bottom.dy - top.dy,
          ),
        );
    canvas.drawRect(
      Rect.fromLTWH(
        bottom.dx,
        top.dy,
        wind.w * camera.scale,
        bottom.dy - top.dy,
      ),
      Paint()..shader = gradient,
    );
    final stroke = Paint()
      ..color = Color.fromARGB(140, 190, 251, 255)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (int i = 0; i < 3; i++) {
      final x = bottom.dx + ((i + 1) / 4) * wind.w * camera.scale;
      final phase =
          (simulation.state.time * 80 + i * 47) %
          math.max(40, bottom.dy - top.dy);
      canvas.drawLine(
        Offset(x, bottom.dy - phase),
        Offset(
          x + math.sin(simulation.state.time * 4 + i) * 8,
          bottom.dy - phase - 24,
        ),
        stroke,
      );
    }
  }

  void drawText(
    String text,
    Offset pos,
    double size,
    Color color, {
    TextAlign align = TextAlign.center,
  }) {
    // Layout teks mahal; HUD menggambar teks yang sama setiap frame.
    final cacheKey = '$text|$size|${color.toARGB32()}|${align.index}';
    var painter = _textCache.remove(cacheKey);
    if (painter == null) {
      painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: color,
            fontSize: size,
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
          ),
        ),
        textAlign: align,
        textDirection: TextDirection.ltr,
      );
      painter.layout();
      if (_textCache.length >= 160) {
        _textCache.remove(_textCache.keys.first)?.dispose();
      }
    }
    _textCache[cacheKey] = painter;
    painter.paint(
      canvas,
      align == TextAlign.center
          ? pos - Offset(painter.width / 2, painter.height / 2)
          : pos,
    );
  }

  void drawWorldProps() {
    for (final wind in world.winds) {
      if (_isVerticallyVisible(wind.y, wind.y + wind.h)) drawWind(wind);
    }
    for (final hazard in world.hazards) {
      if (!_isVerticallyVisible(hazard.y, hazard.y + hazard.h)) continue;
      final active =
          math.sin(
            simulation.state.time * (hazard.type == "storm" ? 5 : 4) +
                hazard.phase,
          ) >
          0.72;
      if (!active) continue;
      final bottom = toScreen(hazard.x, hazard.y);
      final top = toScreen(hazard.x + hazard.w, hazard.y + hazard.h);
      final hazardColor = switch (hazard.type) {
        "storm" => const Color(0xff65d6ff),
        "beam" => const Color(0xffffe891),
        _ => const Color(0xffff7a2c),
      };
      final gradient =
          LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              hazardColor.withValues(alpha: 0.68),
              hazardColor.withValues(alpha: 0),
            ],
          ).createShader(
            Rect.fromLTWH(
              bottom.dx,
              top.dy,
              hazard.w * camera.scale,
              bottom.dy - top.dy,
            ),
          );
      canvas.drawRect(
        Rect.fromLTWH(
          bottom.dx,
          top.dy,
          hazard.w * camera.scale,
          bottom.dy - top.dy,
        ),
        Paint()..shader = gradient,
      );
      if (zoneAt(hazard.y) >= 10) {
        final names = [
          "aurora_booster",
          "clock_pendulum",
          "comet_fruit",
          "prism_switch",
          "bone_spike",
          "solar_vent",
          "gravity_orb",
          "glass_bell",
          "beam_eye",
          "zenith_rune",
        ];
        final frame = assets.atlasFrame(
          "UPPER_HAZARDS_ATLAS",
          names[zoneAt(hazard.y) - 10],
        );
        drawFrameAt(
          "UPPER_HAZARDS_ATLAS",
          frame,
          hazard.x + hazard.w / 2,
          hazard.y + 18,
          42,
          52,
        );
      }
    }
    for (final ladder in world.ladders) {
      if (_isVerticallyVisible(ladder.y, ladder.y + ladder.h)) {
        drawLadder(ladder);
      }
    }
    for (final item in world.platforms) drawPlatform(item);

    for (final rope in world.ropes) {
      final endX = rope.x + math.sin(rope.angle) * rope.length;
      final endY = rope.y - math.cos(rope.angle) * rope.length;
      if (!_isVerticallyVisible(
        math.min(rope.y, endY),
        math.max(rope.y, endY),
      )) {
        continue;
      }
      final start = toScreen(rope.x, rope.y);
      final end = toScreen(endX, endY);
      final width = math.max(3.0, (rope.required ? 7 : 5) * camera.scale);
      final middleX =
          (start.dx + end.dx) / 2 +
          math.sin(simulation.state.time * 2 + rope.x) * 3 * camera.scale;
      final middleY = (start.dy + end.dy) / 2 + 5 * camera.scale;
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..quadraticBezierTo(middleX, middleY, end.dx, end.dy);
      final ropeColor = rope.required
          ? Color.fromARGB(255, 211, 163, 76)
          : rope.temporary
          ? Color.fromARGB(255, 177, 126, 76)
          : Color.fromARGB(255, 105, 67, 38);
      canvas.drawPath(
        path,
        Paint()
          ..color = Color.fromARGB(180, 26, 20, 17)
          ..strokeWidth = width + 3 * camera.scale
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = ropeColor
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = Color.fromARGB(170, 238, 194, 126)
          ..strokeWidth = math.max(1.0, width * 0.22)
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke,
      );

      final metrics = path.computeMetrics();
      for (final metric in metrics) {
        final spacing = math.max(5.0, width * 1.3);
        final wraps = Path();
        for (
          double distance = spacing;
          distance < metric.length - spacing;
          distance += spacing
        ) {
          final tangent = metric.getTangentForOffset(distance);
          if (tangent == null) continue;
          final point = tangent.position;
          final normal = Offset(-tangent.vector.dy, tangent.vector.dx);
          final diagonal = tangent.vector * (width * 0.34);
          final across = normal * (width * 0.42);
          wraps
            ..moveTo(
              point.dx - across.dx - diagonal.dx,
              point.dy - across.dy - diagonal.dy,
            )
            ..lineTo(
              point.dx + across.dx + diagonal.dx,
              point.dy + across.dy + diagonal.dy,
            );
        }
        canvas.drawPath(
          wraps,
          Paint()
            ..color = Color.fromARGB(210, 69, 43, 27)
            ..strokeWidth = math.max(1.0, width * 0.2)
            ..strokeCap = StrokeCap.round
            ..style = PaintingStyle.stroke,
        );
      }

      drawFrameAt(
        "PROPS_ATLAS",
        assets.atlasFrame("PROPS_ATLAS", "rope_knot"),
        rope.x,
        rope.y + 7,
        18,
        25,
      );
      drawFrameAt(
        "PROPS_ATLAS",
        assets.atlasFrame("PROPS_ATLAS", "rope_knot"),
        endX,
        endY + 8,
        21,
        29,
      );
    }

    for (final item in world.platforms) {
      if (!item.mushroom ||
          item.disabled ||
          !_isVerticallyVisible(item.y - 60, item.y + 60)) {
        continue;
      }
      final frames = assets.animation("INTERACTIVES_SHEET", "mushroom_bounce");
      final age = item.bounceAt != null
          ? simulation.state.time - item.bounceAt!
          : 99;
      final index = age < 0.45 ? (age / 0.09).floor().clamp(0, 4) : 0;
      drawFrameAt(
        "INTERACTIVES_SHEET",
        frames.isEmpty ? null : frames[index],
        item.x + item.w * 0.5,
        item.y + 2,
        58,
        58,
      );
    }

    for (final flag in world.flags) {
      if (!_isVerticallyVisible(flag.y - 105, flag.y + 10)) continue;
      final frames = assets.animation("INTERACTIVES_SHEET", "flag_raise");
      final elapsed = simulation.state.time - flag.animStart;
      final index = flag.active ? (elapsed / 0.11).floor().clamp(0, 4) : 0;
      drawFrameAt(
        "INTERACTIVES_SHEET",
        frames.isEmpty ? null : frames[index],
        flag.x,
        flag.y + 5,
        74,
        105,
        flag.active ? 1 : 0.72,
      );
    }

    for (final item in world.pickups) {
      if (item.collected || !_isVerticallyVisible(item.y - 50, item.y + 65)) {
        continue;
      }
      final bob = math.sin(simulation.state.time * 3 + item.x) * 6;
      if (item.type == "coin") {
        final frames = assets.animation("COIN_SHEET", "spin");
        final frame = frames.isEmpty
            ? null
            : frames[((simulation.state.time * 10 + item.x) % frames.length)
                  .floor()];
        drawFrameAt("COIN_SHEET", frame, item.x, item.y + bob, 30, 34);
        continue;
      }
      final frameName = item.type == "fire"
          ? "arrow_fire"
          : item.type == "ice"
          ? "arrow_ice"
          : item.type == "rope"
          ? "arrow_rope"
          : "crystal";
      drawFrameAt(
        "PROPS_ATLAS",
        assets.atlasFrame("PROPS_ATLAS", frameName),
        item.x,
        item.y + bob,
        42,
        48,
      );
      final point = toScreen(item.x, item.y + 60 + bob);
      canvas.drawRect(
        Rect.fromLTWH(point.dx - 40, point.dy - 11, 80, 18),
        Paint()..color = Color.fromARGB(199, 10, 17, 19),
      );
      drawText(
        item.label,
        point,
        math.max(9, 10 * camera.scale),
        Color.fromARGB(255, 255, 244, 186),
      );
    }
  }

  void drawDistanceShield(double x, double y, double width, double height) {
    final center = toScreen(x, y);
    final scale = camera.scale;
    final phase = (math.sin(simulation.state.time * 3 + x * 0.01) + 1) / 2;
    final shieldRect = Rect.fromCenter(
      center: center,
      width: width * scale,
      height: height * scale,
    );
    canvas.drawOval(
      shieldRect,
      Paint()..color = Color.fromARGB((18 + phase * 12).round(), 74, 216, 255),
    );
    canvas.drawOval(
      shieldRect,
      Paint()
        ..color = Color.fromARGB((150 + phase * 80).round(), 113, 229, 255)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, 2 * scale),
    );

    final iconCenter = Offset(center.dx, shieldRect.top + 11 * scale);
    final icon = Path()
      ..moveTo(iconCenter.dx, iconCenter.dy - 7 * scale)
      ..lineTo(iconCenter.dx + 6 * scale, iconCenter.dy - 4 * scale)
      ..lineTo(iconCenter.dx + 5 * scale, iconCenter.dy + 2 * scale)
      ..lineTo(iconCenter.dx, iconCenter.dy + 7 * scale)
      ..lineTo(iconCenter.dx - 5 * scale, iconCenter.dy + 2 * scale)
      ..lineTo(iconCenter.dx - 6 * scale, iconCenter.dy - 4 * scale)
      ..close();
    canvas.drawPath(
      icon,
      Paint()
        ..color = const Color(0xffb8f4ff)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, 1.7 * scale),
    );
    canvas.drawLine(
      Offset(iconCenter.dx - 2 * scale, iconCenter.dy),
      Offset(iconCenter.dx + 2 * scale, iconCenter.dy),
      Paint()
        ..color = const Color(0xffb8f4ff)
        ..strokeWidth = math.max(1.0, scale),
    );
  }

  void drawEnemies() {
    for (final enemy in world.enemies) {
      if (!enemy.alive ||
          zoneAt(enemy.y) < simulation.state.zone ||
          !_isVerticallyVisible(enemy.y - 30, enemy.y + 180)) {
        continue;
      }
      String key = "FOREST_ENEMIES_SHEET";
      String move = "goblin_move";
      String attack = "goblin_attack";
      double height = 52;
      if (enemy.miniBoss) {
        final group = (enemy.zoneIndex ?? 0) ~/ 4;
        const groups = [
          "MINIBOSSES_01_04",
          "MINIBOSSES_05_08",
          "MINIBOSSES_09_12",
          "MINIBOSSES_13_16",
          "MINIBOSSES_17_20",
        ];
        key = groups[group];
        move =
            "mini_${((enemy.zoneIndex ?? 0) + 1).toString().padLeft(2, '0')}";
        attack = move;
        height = 118;
      }
      if (enemy.type == "spider") {
        move = "spider_crawl";
        attack = "spider_crawl";
        height = 40;
      }
      if (enemy.type == "crow") {
        move = "crow_fly";
        attack = "crow_fly";
        height = 48;
      }
      if (enemy.type == "harpy") {
        key = "SKY_SPACE_ENEMIES_SHEET";
        move = "harpy_fly";
        attack = "harpy_attack";
        height = 64;
      }
      if (enemy.type == "robot") {
        key = "SKY_SPACE_ENEMIES_SHEET";
        move = "robot_move";
        attack = "robot_attack";
        height = 60;
      }
      if (enemy.type == "sentinel") {
        key = "MOON_PALACE_ENEMIES_SHEET";
        move = "sentinel_move";
        attack = "sentinel_attack";
        height = 64;
      }
      if (enemy.type == "knight") {
        key = "MOON_PALACE_ENEMIES_SHEET";
        move = "knight_move";
        attack = "knight_attack";
        height = 72;
      }
      if (_moveAttackEnemyTypes.contains(enemy.type)) {
        key = enemy.attackTimer > 0 ? "NEW_ENEMIES_ATTACK" : "NEW_ENEMIES_MOVE";
        move = "${enemy.type}_${enemy.attackTimer > 0 ? "attack" : "move"}";
        attack = move;
        height = enemy.type == "eclipse_wraith" ? 70 : 58;
      }
      if (_upperEnemyTypesA.contains(enemy.type)) {
        key = enemy.attackTimer > 0
            ? "UPPER_ENEMIES_A_ATTACK"
            : "UPPER_ENEMIES_A_MOVE";
        move = "${enemy.type}_${enemy.attackTimer > 0 ? "attack" : "move"}";
        attack = move;
        height = enemy.type == "comet_ape" ? 68 : 58;
      }
      if (_upperEnemyTypesB.contains(enemy.type)) {
        key = enemy.attackTimer > 0
            ? "UPPER_ENEMIES_B_ATTACK"
            : "UPPER_ENEMIES_B_MOVE";
        move = "${enemy.type}_${enemy.attackTimer > 0 ? "attack" : "move"}";
        attack = move;
        height = enemy.type == "glass_deacon" ? 76 : 60;
      }
      if (_upperEnemyTypesC.contains(enemy.type)) {
        key = "UPPER_ENEMIES_C";
        move = "${enemy.type}_move";
        attack = "${enemy.type}_attack";
        height = enemy.type == "throne_guard" ? 76 : 70;
      }
      final point = toScreen(enemy.x, enemy.y + 50);
      if (enemy.frozen > 0) {
        canvas.drawRect(
          Rect.fromLTWH(
            point.dx - 28 * camera.scale,
            point.dy - 54 * camera.scale,
            56 * camera.scale,
            56 * camera.scale,
          ),
          Paint()..color = Color.fromARGB(115, 82, 229, 255),
        );
      }
      final name = enemy.attackTimer > 0 ? attack : move;
      drawAnchored(
        key,
        name,
        enemy.x,
        enemy.y,
        height,
        enemy.facing,
        enemy.attackTimer > 0 ? 10 : 7,
        enemy.x * 0.01,
      );
      if (enemy.attackTimer > 0.18) {
        final alert = toScreen(enemy.x, enemy.y + height + 10);
        drawText(
          "!",
          alert,
          math.max(12, 16 * camera.scale),
          Color.fromARGB(255, 255, 90, 79),
        );
      }
      if (enemy.hurt > 0) {
        canvas.drawRect(
          Rect.fromLTWH(point.dx - 25, point.dy - 52, 50, 52),
          Paint()
            ..color = Color.fromARGB(204, 255, 245, 190)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
      if ((enemy.y - simulation.state.player.y).abs() > 600) {
        drawDistanceShield(
          enemy.x,
          enemy.y + height / 2,
          math.max(70, height * 1.15),
          height + 24,
        );
      }
      if (enemy.miniBoss) {
        final bar = toScreen(enemy.x, enemy.y + 112);
        final width = 104 * camera.scale;
        canvas.drawRect(
          Rect.fromLTWH(bar.dx - width / 2, bar.dy, width, 7),
          Paint()..color = Color.fromARGB(209, 12, 12, 20),
        );
        final tint = zones[enemy.zoneIndex ?? 0].platform == "zenith_crown"
            ? Color.fromARGB(255, 255, 214, 101)
            : Color.fromARGB(255, 255, 214, 101);
        canvas.drawRect(
          Rect.fromLTWH(
            bar.dx - width / 2 + 1,
            bar.dy + 1,
            (width - 2) * math.max(0.0, enemy.hp / enemy.maxHp),
            5,
          ),
          Paint()..color = tint,
        );
      }
    }
  }

  void drawBoss() {
    final boss = world.boss;
    if (boss == null || !boss.alive || zoneAt(boss.y) < simulation.state.zone) {
      return;
    }
    final anim = boss.hurt > 0
        ? "hurt"
        : boss.attackTimer > 0
        ? (boss.phase >= 2 ? "special" : "attack")
        : "idle";
    const keys = {
      "gravemaw": "GRAVEMAW_BOSS_SHEET",
      "astrael": "ASTRAEL_BOSS_SHEET",
      "chronotitan": "CHRONOTITAN_BOSS_SHEET",
      "zenith": "ZENITH_SERAPH_BOSS_SHEET",
    };
    final key = keys[boss.kind] ?? "ASTRAEL_BOSS_SHEET";
    drawAnchored(
      key,
      anim,
      boss.x,
      boss.y - 95,
      (boss.kind == "gravemaw" || boss.kind == "chronotitan") ? 172 : 158,
      boss.facing,
      anim == "idle" ? 5 : 9,
    );
    if ((boss.y - simulation.state.player.y).abs() > 600) {
      drawDistanceShield(boss.x, boss.y, 230, 205);
    }
  }

  void drawPlayer() {
    final player = simulation.state.player;
    final key = skins[simulation.state.selectedSkin].sheet;
    const mapping = {
      "idle": "idle",
      "run": "run",
      "jump": "jump",
      "fall": "jump",
      "climb": "run",
      "swing": "jump",
      "aim": "shoot",
      "shoot": "shoot",
      "cape": "jump",
      "hurt": "shoot",
      "defeat": "jump",
      "grab": "jump",
    };
    final name = mapping[player.anim] ?? "idle";
    double alpha = 1;
    if (player.invulnerable > 0 &&
        (simulation.state.time * 16).floor() % 2 == 1)
      alpha = 0.45;
    drawAnchored(
      key,
      name,
      player.x,
      player.y,
      70,
      player.facing,
      name == "idle" ? 5 : 10,
      0,
      null,
      alpha,
    );
  }

  void drawArrow(GameArrow arrow) {
    final skin = skins[arrow.skinIndex];
    final signature = arrow.type == "normal" && skin.weapon != null;
    final key = signature
        ? "SIGNATURE_WEAPONS_ATLAS"
        : "PROJECTILE_ARROWS_ATLAS";
    final frameName = signature ? skin.weapon! : arrow.type;
    final frame = assets.atlasFrame(key, frameName);
    if (frame == null) return;
    final image = assets.imageOf(key);
    if (image == null) return;
    final point = toScreen(arrow.x, arrow.y);
    final factor = (52 * camera.scale) / frame.content.width;
    canvas.save();
    canvas.translate(point.dx, point.dy);
    canvas.rotate(-arrow.rotation);
    _drawSheet(
      image,
      frame.content,
      Rect.fromLTWH(
        -frame.content.width * factor / 2,
        -frame.content.height * factor / 2,
        frame.content.width * factor,
        frame.content.height * factor,
      ),
    );
    canvas.restore();
  }

  String effectSheet(String name) {
    if (name.endsWith("_hit")) {
      final m = RegExp(r'^skin(\d+)_hit$').firstMatch(name);
      if (m != null) {
        final n = int.parse(m.group(1)!);
        return n <= 14
            ? "SIGNATURE_EFFECTS_A"
            : n <= 18
            ? "SIGNATURE_EFFECTS_B"
            : "SIGNATURE_EFFECTS_C";
      }
      return "ARROW_HIT_EFFECTS";
    }
    if (name == "coin_collect") return "COIN_SHEET";
    return "ELEMENTAL_EFFECTS_SHEET";
  }

  void drawEffects() {
    for (final item in simulation.state.effects) {
      final key = effectSheet(item.name);
      final animName = item.name == "coin_collect" ? "collect" : item.name;
      final frames = assets.animation(key, animName);
      final index = ((item.age / item.duration) * 5).floor().clamp(0, 4);
      drawFrameAt(
        key,
        frames.isEmpty ? null : frames[index],
        item.x,
        item.y + item.size / 2,
        item.size,
        item.size,
      );
    }
    for (final particle in simulation.state.particles) {
      final point = toScreen(particle.x, particle.y);
      final alpha = clamp(particle.life * 2, 0, 1);
      final size = particle.size * camera.scale;
      canvas.drawRect(
        Rect.fromLTWH(
          point.dx - size / 2,
          point.dy - size / 2,
          size.ceilToDouble(),
          size.ceilToDouble(),
        ),
        Paint()..color = _parseColor(particle.color, alpha),
      );
    }
  }

  Color _parseColor(String hex, double alpha) {
    final h = hex.replaceFirst('#', '');
    final r = int.parse(h.substring(0, 2), radix: 16);
    final g = int.parse(h.substring(2, 4), radix: 16);
    final b = int.parse(h.substring(4, 6), radix: 16);
    return Color.fromARGB((alpha * 255).round(), r, g, b);
  }

  void drawTrajectory() {
    final points = simulation.trajectory();
    for (int i = 0; i < points.length; i++) {
      final screen = toScreen(points[i].dx, points[i].dy);
      final radius = math.max(2.0, (5 - i * 0.16) * camera.scale);
      canvas.drawCircle(
        screen,
        radius,
        Paint()
          ..color = Color.fromARGB(
            ((0.85 - i * 0.04) * 255).round(),
            255,
            239,
            150,
          ),
      );
    }
    final target = simulation.aimTarget();
    if (target != null) {
      final screen = toScreen(target.dx, target.dy);
      final size = clamp(14 * camera.scale, 10, 20);
      final stroke = Paint()
        ..color = Color.fromARGB(242, 255, 244, 158)
        ..strokeWidth = 2;
      canvas.drawCircle(screen, size, stroke);
      canvas.drawLine(
        Offset(screen.dx - size - 6, screen.dy),
        Offset(screen.dx - size / 2, screen.dy),
        stroke,
      );
      canvas.drawLine(
        Offset(screen.dx + size / 2, screen.dy),
        Offset(screen.dx + size + 6, screen.dy),
        stroke,
      );
      canvas.drawLine(
        Offset(screen.dx, screen.dy - size - 6),
        Offset(screen.dx, screen.dy - size / 2),
        stroke,
      );
      canvas.drawLine(
        Offset(screen.dx, screen.dy + size / 2),
        Offset(screen.dx, screen.dy + size + 6),
        stroke,
      );
    }
  }

  void drawForeground() {
    for (final shot in simulation.state.enemyShots) {
      final point = toScreen(shot.x, shot.y);
      final gradient = RadialGradient(
        colors: [_parseColor(shot.color, 1), Color.fromARGB(0, 255, 255, 255)],
      ).createShader(Rect.fromLTWH(point.dx - 12, point.dy - 12, 24, 24));
      canvas.drawRect(
        Rect.fromLTWH(point.dx - 12, point.dy - 12, 24, 24),
        Paint()..shader = gradient,
      );
    }
    for (final arrow in simulation.state.arrows) drawArrow(arrow);
    drawEffects();
    drawTrajectory();
    if (simulation.state.flash > 0) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, cssWidth, cssHeight),
        Paint()
          ..color = Color.fromARGB(
            (simulation.state.flash * 1.8 * 255).round(),
            255,
            245,
            215,
          ),
      );
    }
  }

  late Canvas canvas;

  List<Rect> shopCardRects = [];
  Rect shopCloseRect = Rect.zero;
  Rect shopGridViewport = Rect.zero;
  Rect coinBadgeRect = Rect.zero;
  Rect characterBadgeRect = Rect.zero;
  Rect mapButtonRect = Rect.zero;
  List<Rect> mapCardRects = [];
  Rect replayRect = Rect.zero;
  double shopScrollOffset = 0;
  double shopMaxScroll = 0;
  Offset? _shopPointerStart;
  double _shopOffsetAtPointerStart = 0;
  bool _shopPointerDragged = false;
  void Function()? onReplay;
  int? _pendingBuy;
  double _pendingBuyAt = 0;
  int? _deniedSkin;
  double _deniedAt = 0;
  int? _deniedZone;
  double _deniedZoneAt = 0;

  void drawHud() {
    final state = simulation.state;
    final player = state.player;
    final hudScale = clamp(cssWidth / 390, 0.72, 1.0);
    final pad = 20 + 8 * hudScale + 20;
    final gap = 4 * hudScale;
    final rowH = 40 * hudScale;
    final heightW = 66 * hudScale;
    final zoneW = 56 * hudScale;
    final heartsW = 42 * hudScale;
    final energyW = 52 * hudScale;
    final coinW = 62 * hudScale;
    final mapW = 36 * hudScale;
    final characterW = 36 * hudScale;
    final totalWidth =
        heightW +
        zoneW +
        heartsW +
        energyW +
        coinW +
        mapW +
        characterW +
        gap * 6;
    final outerRect = Rect.fromLTWH(
      (cssWidth - totalWidth - 16 * hudScale) / 2,
      pad,
      totalWidth + 16 * hudScale,
      rowH,
    );
    final outerShape = RRect.fromRectAndRadius(
      outerRect,
      Radius.circular(14 * hudScale),
    );
    canvas.drawRRect(
      outerShape,
      Paint()..color = const Color.fromARGB(215, 8, 15, 25),
    );
    canvas.drawRRect(
      outerShape,
      Paint()
        ..color = const Color.fromARGB(85, 197, 220, 240)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    var x = outerRect.left + 8 * hudScale;
    var itemCount = 0;

    void drawPanel(Rect rect) {
      final shape = RRect.fromRectAndRadius(
        rect,
        Radius.circular(10 * hudScale),
      );
      canvas.drawRRect(
        shape,
        Paint()..color = const Color.fromARGB(45, 242, 209, 139),
      );
    }

    Rect nextPanel(double width) {
      final rect = Rect.fromLTWH(x, pad, width, rowH);
      x += width;
      itemCount++;
      if (itemCount < 7) {
        final dividerX = x + gap / 2;
        canvas.drawLine(
          Offset(dividerX, pad + 10 * hudScale),
          Offset(dividerX, pad + rowH - 10 * hudScale),
          Paint()
            ..color = const Color.fromARGB(72, 205, 222, 239)
            ..strokeWidth = 1,
        );
      }
      x += gap;
      return rect;
    }

    final heightRect = nextPanel(heightW);
    drawText(
      "${math.max(0.0, player.y.floor())}m",
      Offset(heightRect.center.dx, heightRect.center.dy),
      13 * hudScale,
      const Color(0xfff4f7fa),
    );

    final zoneRect = nextPanel(zoneW);
    drawText(
      zones[state.zone].short,
      Offset(zoneRect.center.dx, zoneRect.center.dy),
      9 * hudScale,
      const Color(0xffa9d9ed),
    );

    final heartsRect = nextPanel(heartsW);
    drawText(
      "♥ x${player.hp}",
      Offset(heartsRect.center.dx, heartsRect.center.dy),
      11 * hudScale,
      const Color(0xffff7185),
    );

    final energyRect = nextPanel(energyW);
    drawText(
      "⚡",
      Offset(energyRect.left + 9 * hudScale, energyRect.center.dy),
      10 * hudScale,
      const Color(0xff78e6ff),
    );
    final energyTrack = Rect.fromCenter(
      center: Offset(energyRect.right - 18 * hudScale, energyRect.center.dy),
      width: 30 * hudScale,
      height: 5 * hudScale,
    );
    final trackShape = RRect.fromRectAndRadius(
      energyTrack,
      Radius.circular(energyTrack.height / 2),
    );
    canvas.drawRRect(trackShape, Paint()..color = const Color(0xff253642));
    final energyRatio = clamp(player.energy / player.maxEnergy, 0.0, 1.0);
    final fillRect = Rect.fromLTWH(
      energyTrack.left,
      energyTrack.top,
      energyTrack.width * energyRatio,
      energyTrack.height,
    );
    if (fillRect.width > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(fillRect, Radius.circular(fillRect.height / 2)),
        Paint()..color = const Color(0xff78e6ff),
      );
    }

    coinBadgeRect = nextPanel(coinW);
    drawText(
      "${state.coins} ●",
      Offset(coinBadgeRect.center.dx, coinBadgeRect.center.dy),
      10 * hudScale,
      const Color(0xffffdfa0),
    );

    mapButtonRect = nextPanel(mapW);
    drawPanel(mapButtonRect.deflate(2 * hudScale));
    drawText(
      "▦",
      Offset(mapButtonRect.center.dx, mapButtonRect.center.dy),
      18 * hudScale,
      const Color(0xfff2d28b),
    );

    characterBadgeRect = nextPanel(characterW);
    drawPanel(characterBadgeRect.deflate(2 * hudScale));
    drawText(
      "➶",
      Offset(characterBadgeRect.center.dx, characterBadgeRect.center.dy),
      20 * hudScale,
      const Color(0xfff2d28b),
    );

    if (state.toast.time > 0) {
      final lines = state.toast.text.split("\n");
      final longestLine = lines.reduce(
        (longest, line) => line.length > longest.length ? line : longest,
      );
      final toastSize = math.min(
        13 * hudScale,
        (cssWidth - 48) / math.max(1, longestLine.length * 0.62),
      );
      final toastWidth = math.min(
        cssWidth - 24,
        math.max(140 * hudScale, longestLine.length * toastSize * 0.62 + 24),
      );
      final toastHeight = lines.length * toastSize * 1.55 + 12;
      var toastCenter = Offset(cssWidth / 2, cssHeight - 132 * hudScale);
      if (state.toast.abovePlayer) {
        final head = toScreen(player.x, player.y + player.h + 48);
        final minY = pad + rowH + toastHeight / 2 + 8;
        final maxY = math.max(
          minY,
          cssHeight - toastHeight / 2 - 96 * hudScale,
        );
        toastCenter = Offset(
          clamp(head.dx, toastWidth / 2 + 8, cssWidth - toastWidth / 2 - 8),
          clamp(head.dy, minY, maxY),
        );
      }
      final toastRect = Rect.fromCenter(
        center: toastCenter,
        width: toastWidth,
        height: toastHeight,
      );
      drawPanel(toastRect);
      drawText(
        state.toast.text,
        Offset(toastRect.center.dx, toastRect.center.dy),
        toastSize,
        const Color(0xfff4f7fa),
      );
    }

    final bossB = world.boss;
    final bossM = world.miniBoss;
    final showBossBar =
        (bossB != null && bossB.alive && player.y > bossB.y - 400) ||
        (bossM != null && bossM.alive && player.y > bossM.y - 400);
    if (showBossBar) {
      final name = bossB?.name ?? bossM?.name ?? '';
      final hp = bossB != null ? bossB.hp : bossM!.hp;
      final maxHp = bossB != null ? bossB.maxHp : bossM!.maxHp;
      final bw = 240.0;
      final bx = (cssWidth - bw) / 2;
      final by = pad + rowH + 12 * hudScale;
      drawText(
        name,
        Offset(cssWidth / 2, by + 4),
        14,
        Color.fromARGB(255, 255, 220, 220),
      );
      canvas.drawRect(
        Rect.fromLTWH(bx, by + 22, bw, 9),
        Paint()..color = Color.fromARGB(210, 12, 12, 20),
      );
      final ratio = (hp / maxHp).clamp(0, 1);
      canvas.drawRect(
        Rect.fromLTWH(bx + 1, by + 23, (bw - 2) * ratio, 7),
        Paint()..color = Color.fromARGB(255, 255, 90, 90),
      );
    }
  }

  void drawImageCover(String key, Rect dst) {
    final sheet = assets.previewOf(key);
    if (sheet == null) {
      canvas.drawRect(dst, Paint()..color = const Color(0xff12202e));
      return;
    }
    final image = sheet.image;
    final iw = image.width.toDouble();
    final ih = image.height.toDouble();
    final s = math.max(dst.width / iw, dst.height / ih);
    final sw = dst.width / s;
    final sh = dst.height / s;
    final sx = (iw - sw) / 2;
    final sy = (ih - sh) / 2;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(sx, sy, sw, sh),
      dst,
      _paintFor(sheet),
    );
  }

  void drawMap() {
    const mapTopInset = 20.0;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, cssWidth, cssHeight),
      Paint()..color = const Color.fromARGB(240, 4, 8, 14),
    );
    drawText(
      "PILIH AREA",
      Offset(cssWidth / 2, 34 + mapTopInset),
      20,
      const Color(0xfff4f7ff),
    );
    drawText(
      "KETUK AREA UNTUK TELEPORT",
      Offset(cssWidth / 2, 60 + mapTopInset),
      11,
      const Color(0xff9fb4c8),
    );

    final cols = cssWidth < 520 ? 4 : 5;
    final count = zones.length;
    final rows = (count / cols).ceil();
    const double margin = 22.0;
    const double gap = 12.0;
    const double top = 84.0 + mapTopInset;
    const double bottomPad = 28.0;
    final availH = cssHeight - top - bottomPad;
    final cardW = (cssWidth - margin * 2 - gap * (cols - 1)) / cols;
    final cardH = (availH - gap * (rows - 1)) / rows;
    mapCardRects = List.filled(count, Rect.zero);

    for (int i = 0; i < count; i++) {
      final r = i ~/ cols;
      final c = i % cols;
      final x = margin + c * (cardW + gap);
      final y = top + r * (cardH + gap);
      final rect = Rect.fromLTWH(x, y, cardW, cardH);
      mapCardRects[i] = rect;
      final zone = zones[i];

      final unlocked = simulation.isZoneUnlocked(i);
      final current = simulation.state.zone == i;
      drawImageCover(zone.backdrop, rect);
      canvas.drawRect(
        rect,
        Paint()
          ..color = unlocked
              ? const Color.fromARGB(96, 4, 8, 14)
              : const Color.fromARGB(205, 4, 8, 14),
      );
      if (!unlocked) {
        final denied =
            _deniedZone == i && simulation.state.time - _deniedZoneAt < 1.4;
        _drawPadlock(
          Offset(rect.center.dx, rect.center.dy - 8),
          math.min(20.0, cardW * 0.28),
          (denied ? const Color(0xffff7b7b) : const Color(0xffe8edf3))
              .withValues(alpha: 0.85),
        );
        if (denied) {
          drawText(
            "CAPAI DULU",
            Offset(rect.center.dx, rect.center.dy + 14),
            math.min(8.0, (cardW - 8) / (10 * 0.6)),
            const Color(0xffff9b9b),
          );
        }
      }
      final shape = RRect.fromRectAndRadius(rect, Radius.circular(10));
      canvas.drawRRect(
        shape,
        Paint()
          ..color = current
              ? const Color(0xff54ff8a)
              : unlocked
              ? const Color.fromARGB(150, 120, 220, 240)
              : const Color.fromARGB(60, 160, 180, 200)
          ..style = PaintingStyle.stroke
          ..strokeWidth = current ? 2 : 1.2,
      );
      drawText("${i + 1}", Offset(x + 10, y + 14), 9, const Color(0xffe4ebf5));
      drawText(
        zone.short,
        Offset(x + cardW / 2, y + cardH - 30),
        10,
        const Color(0xfff4f7fa),
      );
      drawText(
        zone.name,
        Offset(x + cardW / 2, y + cardH - 14),
        math.min(9.0, (cardW - 8) / (zone.name.length * 0.6)),
        const Color(0xfff2d28b),
      );
    }
  }

  /// Warna kelangkaan mengikuti harga: gratis, umum, langka, epik, legendaris.
  Color _skinRarityColor(int index) {
    final price = skins[index].price;
    if (price == 0) return const Color(0xff65e58a);
    if (price <= 500) return const Color(0xff62b9ff);
    if (price <= 750) return const Color(0xffb07cff);
    if (price <= 1000) return const Color(0xffff9a45);
    return const Color(0xffffd45f);
  }

  void _drawPadlock(Offset center, double size, Color color) {
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: center.translate(0, size * 0.18),
        width: size,
        height: size * 0.78,
      ),
      Radius.circular(size * 0.18),
    );
    canvas.drawArc(
      Rect.fromCenter(
        center: center.translate(0, -size * 0.2),
        width: size * 0.62,
        height: size * 0.7,
      ),
      math.pi,
      math.pi,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = size * 0.14,
    );
    canvas.drawLine(
      center.translate(-size * 0.31, -size * 0.2),
      center.translate(-size * 0.31, -size * 0.02),
      Paint()
        ..color = color
        ..strokeWidth = size * 0.14,
    );
    canvas.drawLine(
      center.translate(size * 0.31, -size * 0.2),
      center.translate(size * 0.31, -size * 0.02),
      Paint()
        ..color = color
        ..strokeWidth = size * 0.14,
    );
    canvas.drawRRect(body, Paint()..color = color);
    canvas.drawCircle(
      center.translate(0, size * 0.16),
      size * 0.09,
      Paint()..color = const Color(0xff0b121b),
    );
  }

  void drawShop() {
    const shopTopInset = 20.0;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, cssWidth, cssHeight),
      Paint()..color = const Color.fromARGB(238, 5, 9, 18),
    );
    final aura =
        RadialGradient(
          colors: [
            const Color(0xff327c91).withValues(alpha: 0.24),
            const Color(0xff101b35).withValues(alpha: 0.08),
            const Color(0xff050912).withValues(alpha: 0),
          ],
          stops: const [0, 0.48, 1],
        ).createShader(
          Rect.fromLTWH(
            -cssWidth * 0.2,
            -cssHeight * 0.12,
            cssWidth * 1.4,
            cssHeight * 1.2,
          ),
        );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, cssWidth, cssHeight),
      Paint()..shader = aura,
    );
    drawText(
      "PILIH PEMANAH",
      Offset(cssWidth / 2, 36 + shopTopInset),
      20,
      const Color(0xfff4f7ff),
    );
    drawText(
      "${simulation.state.coins} KOIN",
      Offset(cssWidth / 2, 64 + shopTopInset),
      12,
      const Color(0xffe5cb8d),
    );

    final cols = cssWidth < 600 ? 3 : 5;
    final cardW = math.min(120.0, (cssWidth - 60) / cols - 10);
    final cardH = cardW + 52;
    final gap = 10.0;
    final totalW = cols * cardW + (cols - 1) * gap;
    final startX = (cssWidth - totalW) / 2;
    final startY = 92.0 + shopTopInset;
    final footerHeight = 40.0;
    final footerTop = cssHeight - 56;
    shopCloseRect = Rect.fromLTWH(
      (cssWidth - math.min(220.0, cssWidth - 40)) / 2,
      footerTop,
      math.min(220.0, cssWidth - 40),
      footerHeight,
    );
    shopGridViewport = Rect.fromLTWH(
      0,
      startY,
      cssWidth,
      math.max(1, shopCloseRect.top - startY - 12),
    );
    final rows = (skins.length / cols).ceil();
    final contentHeight = rows * (cardH + gap) - gap;
    shopMaxScroll = math.max(0, contentHeight - shopGridViewport.height);
    shopScrollOffset = clamp(shopScrollOffset, 0, shopMaxScroll);
    shopCardRects = List.filled(skins.length, Rect.zero);

    canvas.save();
    canvas.clipRect(shopGridViewport);
    for (int i = 0; i < skins.length; i++) {
      final row = i ~/ cols;
      final col = i % cols;
      final x = startX + col * (cardW + gap);
      final y = startY + row * (cardH + gap) - shopScrollOffset;
      final rect = Rect.fromLTWH(x, y, cardW, cardH);
      shopCardRects[i] = rect;
      if (!rect.overlaps(shopGridViewport)) continue;

      final owned = simulation.state.ownedSkins.contains(skins[i].id);
      final selected = simulation.state.selectedSkin == i;
      final skinColor = _parseColor(skins[i].color, 1);
      final rarityColor = _skinRarityColor(i);
      final pulse = (math.sin(simulation.state.time * 2.1 + i * 0.8) + 1) / 2;
      final cardShape = RRect.fromRectAndRadius(
        rect,
        const Radius.circular(12),
      );
      if (selected) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect.inflate(3), const Radius.circular(15)),
          Paint()
            ..color = rarityColor.withValues(alpha: 0.3 + pulse * 0.2)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 13),
        );
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(1.5), const Radius.circular(13)),
        Paint()
          ..color = rarityColor.withValues(alpha: selected ? 0.2 : 0.08)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      canvas.drawRRect(
        cardShape,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: selected
                ? [rarityColor.withValues(alpha: 0.32), const Color(0xff111e2b)]
                : owned
                ? [rarityColor.withValues(alpha: 0.16), const Color(0xff101824)]
                : [rarityColor.withValues(alpha: 0.1), const Color(0xff0e131d)],
          ).createShader(rect),
      );
      final avatarCenter = Offset(rect.center.dx, rect.top + cardH * 0.4);
      final auraBounds = Rect.fromCenter(
        center: avatarCenter,
        width: cardW * 0.94,
        height: cardH * 0.58,
      );
      final aura = RadialGradient(
        colors: [
          skinColor.withValues(
            alpha: (selected ? 0.3 : 0.17) * (0.78 + pulse * 0.22),
          ),
          skinColor.withValues(alpha: 0),
        ],
      ).createShader(auraBounds);
      canvas.save();
      canvas.clipRRect(cardShape);
      canvas.drawRect(rect, Paint()..shader = aura);
      canvas.drawOval(
        Rect.fromCenter(
          center: avatarCenter,
          width: cardW * 0.7,
          height: cardH * 0.42,
        ),
        Paint()
          ..color = skinColor.withValues(
            alpha: (selected ? 0.56 : 0.25) + pulse * 0.12,
          )
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 1.4 : 1,
      );
      final orbitPoint = Offset(
        avatarCenter.dx + math.cos(simulation.state.time + i) * cardW * 0.35,
        avatarCenter.dy + math.sin(simulation.state.time + i) * cardH * 0.2,
      );
      canvas.drawCircle(
        orbitPoint,
        selected ? 2.2 : 1.6,
        Paint()..color = skinColor.withValues(alpha: 0.55 + pulse * 0.35),
      );
      canvas.restore();
      canvas.drawRRect(
        cardShape,
        Paint()
          ..color = selected
              ? rarityColor.withValues(alpha: 0.95)
              : rarityColor.withValues(alpha: owned ? 0.48 : 0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 1.4 : 1,
      );
      canvas.save();
      canvas.clipRRect(cardShape);
      drawAnchoredOnScreen(
        skins[i].sheet,
        "idle",
        x + cardW / 2,
        y + cardH - 48,
        cardH - 62,
        5,
      );
      if (!owned) {
        // Skin terkunci: avatar digelapkan dan diberi gembok.
        canvas.drawRect(
          rect,
          Paint()..color = const Color(0xff050912).withValues(alpha: 0.55),
        );
        _drawPadlock(
          Offset(avatarCenter.dx, avatarCenter.dy + 4),
          18,
          const Color(0xffe8edf3).withValues(alpha: 0.85),
        );
      }
      canvas.restore();
      final indexRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(rect.left + 7, rect.top + 7, 25, 14),
        const Radius.circular(6),
      );
      canvas.drawRRect(
        indexRect,
        Paint()..color = const Color(0xff080e17).withValues(alpha: 0.72),
      );
      drawText(
        (i + 1).toString().padLeft(2, '0'),
        Offset(indexRect.outerRect.center.dx, indexRect.outerRect.center.dy),
        7,
        const Color(0xffe4ebf5),
      );
      final gemCenter = Offset(rect.right - 13, rect.top + 14);
      final gem = Path()
        ..moveTo(gemCenter.dx, gemCenter.dy - 4)
        ..lineTo(gemCenter.dx + 3.5, gemCenter.dy)
        ..lineTo(gemCenter.dx, gemCenter.dy + 4)
        ..lineTo(gemCenter.dx - 3.5, gemCenter.dy)
        ..close();
      canvas.drawPath(
        gem,
        Paint()..color = rarityColor.withValues(alpha: 0.92),
      );
      drawText(
        skins[i].name,
        Offset(x + cardW / 2, y + cardH - 40),
        math.min(9.0, (cardW - 10) / (skins[i].name.length * 0.62)),
        const Color(0xfff0f3f8),
      );
      drawText(
        skins[i].perk,
        Offset(x + cardW / 2, y + cardH - 25),
        math.min(7.0, (cardW - 10) / (skins[i].perk.length * 0.62)),
        skinColor.withValues(alpha: 0.9),
      );
      final coins = simulation.state.coins;
      final affordable = coins >= skins[i].price;
      final time = simulation.state.time;
      final pending = _pendingBuy == i && time - _pendingBuyAt < 3;
      final denied = _deniedSkin == i && time - _deniedAt < 1.4;
      if (pending) {
        canvas.drawRRect(
          cardShape,
          Paint()
            ..color = const Color(
              0xff54ff8a,
            ).withValues(alpha: 0.55 + pulse * 0.4)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
      drawText(
        owned
            ? (selected ? "DIPAKAI" : "MILIKMU")
            : pending
            ? "KETUK LAGI = BELI"
            : denied
            ? "KURANG ${skins[i].price - coins} ●"
            : "${skins[i].price}  ●",
        Offset(x + cardW / 2, y + cardH - 9),
        7,
        selected
            ? skinColor
            : owned
            ? const Color(0xffe5cb8d)
            : pending
            ? const Color(0xff7dffa6)
            : denied || !affordable
            ? const Color(0xffff7b7b)
            : const Color(0xffffd76a),
      );
    }
    canvas.restore();

    if (shopMaxScroll > 0) {
      final track = Rect.fromLTWH(
        cssWidth - 7,
        shopGridViewport.top + 4,
        2,
        shopGridViewport.height - 8,
      );
      final thumbHeight = math.max(
        24.0,
        track.height * shopGridViewport.height / contentHeight,
      );
      final thumbTop =
          track.top +
          (track.height - thumbHeight) * (shopScrollOffset / shopMaxScroll);
      canvas.drawRRect(
        RRect.fromRectAndRadius(track, const Radius.circular(2)),
        Paint()..color = const Color(0xffb2c6d8).withValues(alpha: 0.15),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(track.left, thumbTop, track.width, thumbHeight),
          const Radius.circular(2),
        ),
        Paint()..color = const Color(0xff9cebdc).withValues(alpha: 0.72),
      );
    }

    final footerShape = RRect.fromRectAndRadius(
      shopCloseRect,
      const Radius.circular(13),
    );
    canvas.drawRRect(
      footerShape,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xff3d877f), Color(0xff285a64)],
        ).createShader(shopCloseRect),
    );
    canvas.drawRRect(
      footerShape,
      Paint()
        ..color = const Color(0xff9cebdc).withValues(alpha: 0.58)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    drawText(
      "LANJUT MENDAKI",
      Offset(shopCloseRect.center.dx, shopCloseRect.center.dy),
      13,
      const Color(0xfff3fffc),
    );
  }

  void drawWin() {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, cssWidth, cssHeight),
      Paint()..color = Color.fromARGB(230, 6, 10, 18),
    );
    drawText(
      "PUNCAK DITAKLUKKAN",
      Offset(cssWidth / 2, cssHeight / 2 - 80),
      22,
      Color.fromARGB(255, 255, 240, 160),
    );
    drawText(
      "JANTUNG LANGIT",
      Offset(cssWidth / 2, cssHeight / 2 - 40),
      30,
      Color.fromARGB(255, 255, 255, 255),
    );
    drawText(
      "REBUT KEMBALI",
      Offset(cssWidth / 2, cssHeight / 2 - 4),
      22,
      Color.fromARGB(255, 255, 255, 255),
    );
    drawText(
      "${simulation.state.player.highest.floor()} m",
      Offset(cssWidth / 2, cssHeight / 2 + 40),
      26,
      Color.fromARGB(255, 180, 230, 255),
    );
    final rw = 180.0;
    replayRect = Rect.fromLTWH((cssWidth - rw) / 2, cssHeight / 2 + 70, rw, 40);
    canvas.drawRect(
      replayRect,
      Paint()..color = Color.fromARGB(230, 60, 120, 90),
    );
    drawText(
      "NAIK LAGI",
      Offset(replayRect.left + rw / 2, replayRect.top + 8),
      18,
      Color.fromARGB(255, 255, 255, 255),
    );
  }

  void render(Canvas c, double dt, double width, double height) {
    cssWidth = width;
    cssHeight = height;
    camera.scale = (height / 700) * 0.7;
    camera.height = height / camera.scale;
    camera.width = width / camera.scale;
    canvas = c;
    updateCamera(dt);
    canvas.save();
    final shakeAmount = simulation.state.shake > 0
        ? tuning.effectsIntensity * simulation.state.shake * 9
        : 0;
    if (shakeAmount > 0)
      canvas.translate(
        (math.Random().nextDouble() - 0.5) * shakeAmount,
        (math.Random().nextDouble() - 0.5) * shakeAmount,
      );
    drawBackground();
    drawWorldProps();
    drawEnemies();
    drawBoss();
    drawPlayer();
    drawForeground();
    drawHud();
    if (simulation.state.shopOpen) drawShop();
    if (simulation.state.mapOpen) drawMap();
    if (simulation.state.won) drawWin();
    canvas.restore();
  }

  void scrollShop(double delta) {
    if (!simulation.state.shopOpen) return;
    shopScrollOffset = clamp(shopScrollOffset + delta, 0, shopMaxScroll);
  }

  void handleShopPointerDown(Offset screen) {
    _shopPointerStart = shopGridViewport.contains(screen) ? screen : null;
    _shopOffsetAtPointerStart = shopScrollOffset;
    _shopPointerDragged = false;
  }

  void handleShopPointerMove(Offset screen) {
    final start = _shopPointerStart;
    if (start == null) return;
    final distance = start.dy - screen.dy;
    if (distance.abs() > 6) _shopPointerDragged = true;
    if (_shopPointerDragged) {
      shopScrollOffset = clamp(
        _shopOffsetAtPointerStart + distance,
        0,
        shopMaxScroll,
      );
    }
  }

  void handleShopPointerUp(Offset screen) {
    final dragged = _shopPointerDragged;
    _shopPointerStart = null;
    _shopPointerDragged = false;
    if (!dragged) handleTap(screen);
  }

  void handleShopPointerCancel() {
    _shopPointerStart = null;
    _shopPointerDragged = false;
  }

  void handleTap(Offset screen) {
    if (simulation.state.won) {
      if (replayRect.contains(screen)) onReplay?.call();
      return;
    }
    if (simulation.state.shopOpen) {
      if (shopCloseRect.contains(screen)) {
        simulation.selectSkin(simulation.state.selectedSkin);
        return;
      }
      if (shopGridViewport.contains(screen)) {
        for (int i = 0; i < shopCardRects.length; i++) {
          if (shopCardRects[i].contains(screen)) {
            _tapSkinCard(i);
            return;
          }
        }
      }
      return;
    }
    if (coinBadgeRect.contains(screen) || characterBadgeRect.contains(screen)) {
      simulation.openShop();
    }
  }

  /// Skin terkunci butuh dua ketukan (konfirmasi) supaya koin tidak
  /// terpakai karena salah pencet.
  void _tapSkinCard(int i) {
    final state = simulation.state;
    if (state.ownedSkins.contains(skins[i].id)) {
      _pendingBuy = null;
      simulation.selectSkin(i);
      return;
    }
    if (state.coins < skins[i].price) {
      _pendingBuy = null;
      _deniedSkin = i;
      _deniedAt = state.time;
      simulation.events.sfx?.call("error");
      return;
    }
    if (_pendingBuy == i && state.time - _pendingBuyAt < 3) {
      _pendingBuy = null;
      simulation.buySkin(i);
      return;
    }
    _pendingBuy = i;
    _pendingBuyAt = state.time;
    simulation.events.sfx?.call("click");
  }

  void handleMapTap(Offset screen) {
    for (int i = 0; i < mapCardRects.length; i++) {
      if (mapCardRects[i].contains(screen)) {
        if (!simulation.isZoneUnlocked(i)) {
          _deniedZone = i;
          _deniedZoneAt = simulation.state.time;
          simulation.events.sfx?.call("error");
          return;
        }
        simulation.teleportTo(i);
        return;
      }
    }
    simulation.state.mapOpen = false;
  }
}
