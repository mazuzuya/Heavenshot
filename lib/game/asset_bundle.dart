import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/services.dart';

import 'constants.dart';

class FrameRect {
  final Rect source;
  final Rect content;
  final Offset anchor;

  FrameRect(this.source, this.content, this.anchor);

  Rect get crop => content;
  double get largest => content.height;
}

class SheetBundle {
  final String file;
  final Map<String, List<FrameRect>> animations;
  final Map<String, FrameRect> atlas;

  /// Gambar resolusi penuh, hanya ada saat sheet sedang dibutuhkan area aktif.
  Image? image;

  /// Gambar resolusi kecil untuk toko/peta (dan cadangan saat gambar penuh
  /// belum selesai dimuat).
  Image? preview;
  double previewScale = 1;

  SheetBundle(this.file, this.animations, this.atlas);
}

/// Gambar yang siap digambar beserta skala piksel terhadap koordinat frame JSON.
class SheetImage {
  final Image image;
  final double scale;
  const SheetImage(this.image, this.scale);

  Rect map(Rect r) => scale == 1
      ? r
      : Rect.fromLTRB(
          r.left * scale,
          r.top * scale,
          r.right * scale,
          r.bottom * scale,
        );
}

/// Menyimpan data frame semua sheet, tetapi hanya men-decode gambar yang
/// diminta lewat [setResident]. Sheet lain dibuang dari memori agar HP tidak
/// kehabisan memori GPU (semua sheet sekaligus ±700 MB setelah di-decode).
class GameAssets {
  final Map<String, SheetBundle> sheets = {};
  final Map<String, double> _largestHeights = {};
  final Map<String, Future<void>> _loading = {};
  Set<String> _wantedFull = {};
  Set<String> _wantedPreview = {};

  SheetImage? imageOf(String key) {
    final s = sheets[key];
    if (s == null) return null;
    if (s.image != null) return SheetImage(s.image!, 1);
    if (s.preview != null) return SheetImage(s.preview!, s.previewScale);
    return null;
  }

  SheetImage? previewOf(String key) {
    final s = sheets[key];
    if (s?.preview != null) return SheetImage(s!.preview!, s.previewScale);
    return imageOf(key);
  }

  List<FrameRect> animation(String key, String name) =>
      sheets[key]?.animations[name] ?? const [];

  FrameRect? atlasFrame(String key, String name) {
    final s = sheets[key];
    if (s == null) return null;
    return s.atlas[name] ?? s.animations[name]?.first;
  }

  double largestHeight(String key, String name) {
    return _largestHeights.putIfAbsent('$key/$name', () {
      final frames = animation(key, name);
      double max = 0;
      for (final frame in frames) {
        max = math.max(max, frame.largest);
      }
      return max;
    });
  }

  /// Hanya memuat data frame (JSON kecil). Gambar dimuat lewat [setResident].
  static Future<GameAssets> load() async {
    final assets = GameAssets();
    for (final entry in assetManifest.entries) {
      final sheet = SheetBundle(entry.value, {}, {});
      if (entry.value.contains('transparent')) {
        final jsonName = 'assets/json/${framesFileName(entry.value)}';
        try {
          final raw =
              jsonDecode(await rootBundle.loadString(jsonName))
                  as Map<String, dynamic>;
          _parseFrames(raw, sheet);
        } catch (e) {
          // Aset yang hanya dipakai sebagai gambar polos tidak punya frame JSON.
          // Lewati saja agar pemuatan tidak gagal.
          // ignore: avoid_print
          print('[GameAssets] frame data tidak ditemukan untuk $jsonName: $e');
        }
      }
      assets.sheets[entry.key] = sheet;
    }
    return assets;
  }

  /// Menetapkan sheet yang boleh ada di memori. Sheet di luar daftar langsung
  /// dibuang; sheet baru di-decode di latar belakang. Future selesai saat
  /// semua sheet yang diminta sudah siap.
  Future<void> setResident(Set<String> full, Set<String> previews) {
    _wantedFull = full;
    _wantedPreview = previews;
    final pending = <Future<void>>[];
    for (final entry in sheets.entries) {
      final key = entry.key;
      final sheet = entry.value;
      if (!full.contains(key) && sheet.image != null) {
        sheet.image!.dispose();
        sheet.image = null;
      }
      // Pratinjau tetap disimpan sebagai cadangan sampai gambar penuhnya siap.
      final keepAsFallback = full.contains(key) && sheet.image == null;
      if (!previews.contains(key) && !keepAsFallback && sheet.preview != null) {
        sheet.preview!.dispose();
        sheet.preview = null;
      }
      if (full.contains(key) && sheet.image == null) {
        pending.add(_load(key, preview: false));
      }
      if (previews.contains(key) && sheet.preview == null) {
        pending.add(_load(key, preview: true));
      }
    }
    return Future.wait(pending);
  }

  Future<void> _load(String key, {required bool preview}) {
    final id = '${preview ? 'p' : 'f'}:$key';
    return _loading.putIfAbsent(id, () async {
      final sheet = sheets[key]!;
      try {
        final data = await rootBundle.load('assets/images/${sheet.file}');
        final buffer = await ImmutableBuffer.fromUint8List(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
        final descriptor = await ImageDescriptor.encoded(buffer);
        final factor = preview ? _previewFactor(key) : 1.0;
        final codec = await descriptor.instantiateCodec(
          targetWidth: factor == 1
              ? null
              : math.max(1, (descriptor.width * factor).round()),
        );
        final image = (await codec.getNextFrame()).image;
        final scale = image.width / descriptor.width;
        codec.dispose();
        descriptor.dispose();
        buffer.dispose();
        if (preview) {
          if (sheet.preview == null &&
              (_wantedPreview.contains(key) ||
                  (_wantedFull.contains(key) && sheet.image == null))) {
            sheet.preview = image;
            sheet.previewScale = scale;
          } else {
            image.dispose();
          }
        } else {
          if (sheet.image == null && _wantedFull.contains(key)) {
            sheet.image = image;
            if (!_wantedPreview.contains(key) && sheet.preview != null) {
              sheet.preview!.dispose();
              sheet.preview = null;
            }
          } else {
            image.dispose();
          }
        }
      } catch (e) {
        // ignore: avoid_print
        print('[GameAssets] gagal memuat ${sheet.file}: $e');
      } finally {
        _loading.remove(id);
      }
    });
  }

  static double _previewFactor(String key) => key.endsWith('_BG') ? 0.25 : 0.5;

  static double _num(dynamic value) => (value as num).toDouble();

  static Rect? _rectOrNull(dynamic value) =>
      value == null ? null : _rect(value as Map<String, dynamic>);

  static void _parseFrames(Map<String, dynamic> data, SheetBundle sheet) {
    final frames = data['frames'] as List<dynamic>;
    for (final raw in frames) {
      final f = raw as Map<String, dynamic>;
      final name = f['name'] as String;
      final source = _rect(f['source'] as Map<String, dynamic>);
      final content = _rectOrNull(f['content']) ?? source;
      final anchorData = f['anchor'] as Map<String, dynamic>?;
      final anchor = anchorData == null
          ? Offset(source.left + source.width / 2, source.bottom)
          : Offset(_num(anchorData['x']), _num(anchorData['y']));
      final frame = FrameRect(source, content, anchor);
      final match = RegExp(r'^(.*)_(\d+)$').firstMatch(name);
      if (match != null) {
        final key = match.group(1)!;
        sheet.animations.putIfAbsent(key, () => []).add(frame);
      } else {
        sheet.atlas[name] = frame;
      }
    }
  }

  static Rect _rect(Map<String, dynamic> m) {
    return Rect.fromLTWH(
      (m['x'] as num).toDouble(),
      (m['y'] as num).toDouble(),
      (m['w'] as num).toDouble(),
      (m['h'] as num).toDouble(),
    );
  }
}
