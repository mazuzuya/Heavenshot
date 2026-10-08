import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

class GameAudio {
  final AudioPlayer _bgmPlayer = AudioPlayer();
  bool _enabled = true;
  bool _bgmStarted = false;
  int _area = 0;
  String? _playingBgm;
  double volume = 0.6;
  double bgmVolume = 0.4;

  // Nama efek yang dipanggil simulasi tapi file-nya bernama lain.
  static const Map<String, String> _sfxAliases = {
    'hit': 'enemy_hit',
    'boss_die': 'explosion',
  };
  static const int _maxActiveSfx = 8;
  static const int _minRepeatMs = 60;
  final Set<String> _available = {};
  final Set<String> _missing = {};
  final Map<String, int> _lastPlayed = {};
  int _activeSfx = 0;

  AudioContext _noFocusContext() => AudioContext(
    android: AudioContextAndroid(
      isSpeakerphoneOn: false,
      stayAwake: false,
      contentType: AndroidContentType.music,
      usageType: AndroidUsageType.media,
      audioFocus: AndroidAudioFocus.none,
    ),
    iOS: AudioContextIOS(
      category: AVAudioSessionCategory.playback,
      options: const <AVAudioSessionOptions>{
        AVAudioSessionOptions.mixWithOthers,
      },
    ),
  );

  void unlock() {
    _enabled = true;
    if (!_bgmStarted) unawaited(_setBgm('bgm${(_area ~/ 4) + 1}.mp3'));
  }

  void setArea(int area) {
    _area = area.clamp(0, 19).toInt();
    if (_bgmStarted) {
      unawaited(_setBgm('bgm${(_area ~/ 4) + 1}.mp3'));
    }
  }

  Future<void> _setBgm(String track) async {
    if (_playingBgm == track) return;
    if (_missing.contains(track) || !await _exists(track)) return;
    _bgmStarted = true;
    try {
      await _bgmPlayer.setAudioContext(_noFocusContext());
      await _bgmPlayer.stop();
      await _bgmPlayer.setReleaseMode(ReleaseMode.loop);
      await _bgmPlayer.setVolume(bgmVolume);
      await _bgmPlayer.play(AssetSource('audio/$track'));
      _playingBgm = track;
    } catch (_) {
      _bgmStarted = false;
    }
  }

  /// Cek sekali apakah file audio ada di bundle; hasilnya diingat supaya
  /// suara yang file-nya tidak ada tidak membuat AudioPlayer baru terus-menerus.
  Future<bool> _exists(String filename) async {
    if (_available.contains(filename)) return true;
    if (_missing.contains(filename)) return false;
    try {
      await rootBundle.load('assets/audio/$filename');
      _available.add(filename);
      return true;
    } catch (_) {
      _missing.add(filename);
      return false;
    }
  }

  Future<void> _play(String filename, {double volumeScale = 1}) async {
    if (!_enabled || _activeSfx >= _maxActiveSfx) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _lastPlayed[filename];
    if (last != null && now - last < _minRepeatMs) return;
    _lastPlayed[filename] = now;
    if (!await _exists(filename)) return;
    _activeSfx++;
    final player = AudioPlayer();
    var released = false;
    void release() {
      if (released) return;
      released = true;
      _activeSfx--;
      unawaited(player.dispose());
    }

    try {
      await player.setAudioContext(_noFocusContext());
      await player.setVolume((volume * volumeScale).clamp(0, 1).toDouble());
      player.onPlayerComplete.listen((_) => release());
      await player.play(AssetSource('audio/$filename'));
    } catch (_) {
      // Audio is optional and should never interrupt gameplay.
      release();
    }
  }

  Future<void> playSfx(String name) =>
      _play('${_sfxAliases[name] ?? name}.mp3');

  Future<void> playBgm(String name) => _setBgm('$name.mp3');

  Future<void> stopBgm() async {
    try {
      await _bgmPlayer.stop();
    } catch (_) {}
    _playingBgm = null;
  }

  Future<void> setMuted(bool value) async {
    _enabled = !value;
    if (value) {
      await stopBgm();
    } else {
      unlock();
    }
  }

  void dispose() {
    _bgmPlayer.dispose();
  }
}
