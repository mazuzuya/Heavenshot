import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'asset_bundle.dart';
import 'audio.dart';
import 'constants.dart';
import 'input_state.dart';
import 'renderer.dart';
import 'simulation.dart';
import 'world.dart';

class HeavenshotGame extends FlameGame {
  late GameAssets gameAssets;
  late World gameWorld;
  late Simulation simulation;
  late Renderer renderer;
  final GameAudio audio = GameAudio();
  final InputController input = InputController();
  final Tuning tuning = Tuning(230, 470, 1080, 5.5, 1);
  final ValueNotifier<bool> hudVisible = ValueNotifier(false);
  final ValueNotifier<int> selectedArrow = ValueNotifier(0);

  /// Bitmask panah yang sudah terbuka: bit 0 biasa, 1 api, 2 es, 3 tali.
  final ValueNotifier<int> unlockedArrows = ValueNotifier(1);
  bool isLoaded = false;
  double lastDt = 0;
  String? _residentKey;

  static const String _progressKey = 'heavenshot.progress.v1';
  Map<String, dynamic>? _progress;
  bool _saveDirty = false;
  double _saveCooldown = 0;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    gameAssets = await GameAssets.load();
    _progress = await _readProgress();
    _build();
    await _syncResidentAssets();
    isLoaded = true;
    audio.setArea(0);
  }

  /// Hanya area sebelumnya, saat ini, dan berikutnya (plus aset umum & skin
  /// aktif) yang disimpan di memori. Dipanggil tiap frame tapi hanya bekerja
  /// saat area/skin/menu berubah.
  Future<void> _syncResidentAssets() {
    final state = simulation.state;
    final key =
        '${state.zone}|${state.selectedSkin}|${state.shopOpen}|${state.mapOpen}';
    if (key == _residentKey) return Future.value();
    _residentKey = key;
    return gameAssets.setResident(
      Renderer.residentSheets(state.zone, state.selectedSkin),
      Renderer.previewSheets(shop: state.shopOpen, map: state.mapOpen),
    );
  }

  Future<Map<String, dynamic>?> _readProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_progressKey);
      if (raw == null) return null;
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Koin & skin disimpan permanen. `events.save` bisa terpanggil tiap koin
  /// diambil, jadi penulisan ke disk dikumpulkan maksimal sekali per detik.
  Future<void> _flushProgress() async {
    if (!_saveDirty) return;
    _saveDirty = false;
    _progress = simulation.saveData();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_progressKey, jsonEncode(_progress));
    } catch (_) {
      _saveDirty = true;
    }
  }

  @override
  void lifecycleStateChange(AppLifecycleState state) {
    super.lifecycleStateChange(state);
    if (isLoaded &&
        (state == AppLifecycleState.paused ||
            state == AppLifecycleState.inactive ||
            state == AppLifecycleState.detached)) {
      unawaited(_flushProgress());
    }
  }

  void _build() {
    gameWorld = World();
    simulation = Simulation(
      world: gameWorld,
      input: input,
      tuning: tuning,
      saved: _progress,
      events: Events(
        sfx: (name) => audio.playSfx(name),
        haptic: (_) {},
        save: (_) => _saveDirty = true,
        zone: (z) {
          audio.setArea(z);
          audio.playSfx('zone_change');
        },
        win: (s) {
          audio.playSfx('win');
          audio.setArea(s.zone);
        },
        music: (name) => audio.playBgm(name),
      ),
    );
    renderer = Renderer(
      assets: gameAssets,
      world: gameWorld,
      simulation: simulation,
      tuning: tuning,
    );
    renderer.onReplay = restart;
  }

  void restart() {
    _progress = simulation.saveData();
    _build();
  }

  @override
  void update(double dt) {
    if (!isLoaded) return;
    lastDt = dt;
    simulation.update(math.min(1 / 30, math.max(0.001, dt)));
    unawaited(_syncResidentAssets());
    _saveCooldown -= dt;
    if (_saveDirty && _saveCooldown <= 0) {
      _saveCooldown = 1;
      unawaited(_flushProgress());
    }
    final shouldShow =
        !(simulation.state.shopOpen ||
            simulation.state.won ||
            simulation.state.mapOpen);
    if (hudVisible.value != shouldShow) hudVisible.value = shouldShow;
    if (selectedArrow.value != simulation.state.player.selectedArrow)
      selectedArrow.value = simulation.state.player.selectedArrow;
    final unlocks = simulation.state.player.unlocks;
    final mask =
        1 |
        (unlocks.fire ? 2 : 0) |
        (unlocks.ice ? 4 : 0) |
        (unlocks.rope ? 8 : 0);
    if (unlockedArrows.value != mask) unlockedArrows.value = mask;
  }

  @override
  void render(Canvas canvas) {
    if (!isLoaded) return;
    renderer.render(canvas, lastDt, size.x, size.y);
  }

  void onPointerDown(Offset p) {
    if (!isLoaded) return;
    audio.unlock();
    if (simulation.state.mapOpen) return;
    if (simulation.state.shopOpen) {
      renderer.handleShopPointerDown(p);
      return;
    }
    if (simulation.state.won) return;
    input.engaged = true;
    input.aim = AimTarget(target: renderer.toWorld(p));
  }

  void onPointerMove(Offset p) {
    if (!isLoaded) return;
    if (simulation.state.shopOpen) {
      renderer.handleShopPointerMove(p);
      return;
    }
    if (simulation.state.won) return;
    input.aim = AimTarget(target: renderer.toWorld(p));
  }

  void onPointerUp(Offset p) {
    if (!isLoaded) return;
    if (simulation.state.mapOpen) {
      renderer.handleMapTap(p);
      return;
    }
    if (simulation.state.shopOpen) {
      renderer.handleShopPointerUp(p);
      return;
    }
    if (simulation.state.won) {
      renderer.handleTap(p);
      return;
    }
    if (renderer.coinBadgeRect.contains(p) ||
        renderer.characterBadgeRect.contains(p)) {
      simulation.openShop();
      input.aim = null;
      return;
    }
    if (renderer.mapButtonRect.contains(p)) {
      simulation.state.mapOpen = true;
      input.aim = null;
      return;
    }
    input.shot = input.aim;
    input.aim = null;
  }

  void onPointerCancel(Offset p) {
    if (!isLoaded) return;
    if (simulation.state.shopOpen) {
      renderer.handleShopPointerCancel();
      return;
    }
    input.aim = null;
  }

  void onPointerScroll(double delta) {
    if (!isLoaded || !simulation.state.shopOpen) return;
    renderer.scrollShop(delta);
  }

  void onKeyDown(LogicalKeyboardKey k) {
    if (!isLoaded) return;
    audio.unlock();
    input.engaged = true;
    if (k == LogicalKeyboardKey.keyA || k == LogicalKeyboardKey.arrowLeft) {
      input.left = true;
    } else if (k == LogicalKeyboardKey.keyD ||
        k == LogicalKeyboardKey.arrowRight) {
      input.right = true;
    } else if (k == LogicalKeyboardKey.keyW ||
        k == LogicalKeyboardKey.arrowUp) {
      input.up = true;
    } else if (k == LogicalKeyboardKey.keyS ||
        k == LogicalKeyboardKey.arrowDown) {
      input.down = true;
    } else if (k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.keyZ) {
      if (!input.jump) input.jumpPressed = true;
      input.jump = true;
    } else if (k == LogicalKeyboardKey.digit1) {
      input.arrowRequest = 0;
    } else if (k == LogicalKeyboardKey.digit2) {
      input.arrowRequest = 1;
    } else if (k == LogicalKeyboardKey.digit3) {
      input.arrowRequest = 2;
    } else if (k == LogicalKeyboardKey.digit4) {
      input.arrowRequest = 3;
    }
  }

  void onKeyUp(LogicalKeyboardKey k) {
    if (!isLoaded) return;
    if (k == LogicalKeyboardKey.keyA || k == LogicalKeyboardKey.arrowLeft) {
      input.left = false;
    } else if (k == LogicalKeyboardKey.keyD ||
        k == LogicalKeyboardKey.arrowRight) {
      input.right = false;
    } else if (k == LogicalKeyboardKey.keyW ||
        k == LogicalKeyboardKey.arrowUp) {
      input.up = false;
    } else if (k == LogicalKeyboardKey.keyS ||
        k == LogicalKeyboardKey.arrowDown) {
      input.down = false;
    } else if (k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.keyZ) {
      input.jump = false;
    }
  }
}
