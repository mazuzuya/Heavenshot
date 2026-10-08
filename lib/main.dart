import 'dart:math' as math;

import 'package:flame/game.dart' show GameWidget;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game/game.dart';
import 'game/input_state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const HeavenshotApp());
}

class HeavenshotApp extends StatelessWidget {
  const HeavenshotApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(),
    home: GameScreen(game: HeavenshotGame()),
  );
}

class GameScreen extends StatelessWidget {
  final HeavenshotGame game;
  const GameScreen({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    final focusNode = FocusNode();
    return Scaffold(
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            RawKeyboardListener(
              autofocus: true,
              focusNode: focusNode,
              onKey: (event) {
                if (event is RawKeyDownEvent) {
                  game.onKeyDown(event.logicalKey);
                } else if (event is RawKeyUpEvent) {
                  game.onKeyUp(event.logicalKey);
                }
              },
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (event) =>
                    game.onPointerDown(event.localPosition),
                onPointerMove: (event) =>
                    game.onPointerMove(event.localPosition),
                onPointerUp: (event) => game.onPointerUp(event.localPosition),
                onPointerCancel: (event) =>
                    game.onPointerCancel(event.localPosition),
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent) {
                    game.onPointerScroll(event.scrollDelta.dy);
                  }
                },
                child: GameWidget(
                  game: game,
                  loadingBuilder: (_) => Container(
                    color: const Color(0xff05090f),
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                ),
              ),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: game.hudVisible,
              builder: (context, visible, _) => visible
                  ? ControlOverlay(game: game)
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

// Palet kontrol: kaca gelap transparan dengan garis tipis dan aksen per panah.
const Color _glassFill = Color(0x730A121B);
const Color _glassBorder = Color(0x2EFFFFFF);
const Color _ink = Color(0xFFF2F6FA);

class _ArrowStyle {
  final IconData icon;
  final Color accent;
  const _ArrowStyle(this.icon, this.accent);
}

const List<_ArrowStyle> _arrowStyles = [
  _ArrowStyle(Icons.north_east_rounded, Color(0xFFF6E8B7)),
  _ArrowStyle(Icons.local_fire_department_rounded, Color(0xFFFF8A3D)),
  _ArrowStyle(Icons.ac_unit_rounded, Color(0xFF66E7FF)),
  _ArrowStyle(Icons.link_rounded, Color(0xFFD9A96A)),
];

class ControlOverlay extends StatelessWidget {
  final HeavenshotGame game;
  const ControlOverlay({super.key, required this.game});

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned(
        left: 20,
        bottom: 28,
        child: _MovementJoystick(input: game.input),
      ),
      Positioned(
        right: 20,
        bottom: 28,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _ArrowSelector(game: game),
            const SizedBox(height: 16),
            _JumpButton(
              onDown: () {
                if (!game.input.jump) game.input.jumpPressed = true;
                game.input.jump = true;
              },
              onUp: () => game.input.jump = false,
            ),
          ],
        ),
      ),
    ],
  );
}

class _ArrowSelector extends StatelessWidget {
  final HeavenshotGame game;
  const _ArrowSelector({required this.game});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: game.unlockedArrows,
    builder: (context, unlocked, _) => ValueListenableBuilder<int>(
      valueListenable: game.selectedArrow,
      builder: (context, selected, _) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: _glassFill,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: _glassBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < _arrowStyles.length; i++)
              _ArrowChip(
                index: i,
                style: _arrowStyles[i],
                selected: selected == i,
                locked: unlocked & (1 << i) == 0,
                onTap: () {
                  HapticFeedback.selectionClick();
                  game.input.arrowRequest = i;
                },
              ),
          ],
        ),
      ),
    ),
  );
}

class _ArrowChip extends StatelessWidget {
  final int index;
  final _ArrowStyle style;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  const _ArrowChip({
    required this.index,
    required this.style,
    required this.selected,
    required this.locked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = style.accent;
    return Listener(
      key: Key('arrow-button-$index'),
      behavior: HitTestBehavior.opaque,
      // Listener langsung bereaksi, tanpa jeda deteksi gesture.
      onPointerDown: (_) => onTap(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        width: 44,
        height: 44,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? accent.withValues(alpha: 0.22) : Colors.transparent,
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.9)
                : Colors.transparent,
            width: 1.5,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.45),
                    blurRadius: 14,
                  ),
                ]
              : const [],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              style.icon,
              size: 20,
              color: locked
                  ? _ink.withValues(alpha: 0.22)
                  : selected
                  ? accent
                  : _ink.withValues(alpha: 0.7),
            ),
            if (locked)
              Positioned(
                right: 7,
                bottom: 7,
                child: Icon(
                  Icons.lock_rounded,
                  size: 10,
                  color: _ink.withValues(alpha: 0.55),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _JumpButton extends StatefulWidget {
  final VoidCallback onDown;
  final VoidCallback onUp;
  const _JumpButton({required this.onDown, required this.onUp});

  @override
  State<_JumpButton> createState() => _JumpButtonState();
}

class _JumpButtonState extends State<_JumpButton> {
  static const double _size = 76;
  bool _pressed = false;

  void _down() {
    if (_pressed) return;
    HapticFeedback.lightImpact();
    setState(() => _pressed = true);
    widget.onDown();
  }

  void _up() {
    if (!_pressed) return;
    setState(() => _pressed = false);
    widget.onUp();
  }

  @override
  Widget build(BuildContext context) => Listener(
    key: const Key('jump-button'),
    behavior: HitTestBehavior.opaque,
    onPointerDown: (_) => _down(),
    onPointerUp: (_) => _up(),
    onPointerCancel: (_) => _up(),
    child: AnimatedScale(
      scale: _pressed ? 0.9 : 1,
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 110),
        width: _size,
        height: _size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _pressed ? const Color(0x5254FF8A) : _glassFill,
          border: Border.all(
            color: _pressed ? const Color(0xFF54FF8A) : _glassBorder,
            width: 1.5,
          ),
          boxShadow: _pressed
              ? const [BoxShadow(color: Color(0x6654FF8A), blurRadius: 18)]
              : const [],
        ),
        child: Icon(
          Icons.keyboard_double_arrow_up_rounded,
          size: 34,
          color: _pressed ? const Color(0xFFB9FFD0) : _ink,
        ),
      ),
    ),
  );
}

class _MovementJoystick extends StatefulWidget {
  final InputController input;

  const _MovementJoystick({required this.input});

  @override
  State<_MovementJoystick> createState() => _MovementJoystickState();
}

class _MovementJoystickState extends State<_MovementJoystick> {
  static const double _size = 124;
  static const double _travel = 36;
  static const double _knob = 44;
  Offset _offset = Offset.zero;
  bool _active = false;

  void _move(Offset localPosition) {
    final delta = localPosition - const Offset(_size / 2, _size / 2);
    final distance = delta.distance;
    final offset = distance > _travel ? delta / distance * _travel : delta;
    setState(() {
      _offset = offset;
      _active = true;
    });

    const deadZone = 10.0;
    widget.input.left = offset.dx < -deadZone;
    widget.input.right = offset.dx > deadZone;
    widget.input.up = offset.dy < -deadZone;
    widget.input.down = offset.dy > deadZone;
    widget.input.engaged = true;
  }

  void _release() {
    setState(() {
      _offset = Offset.zero;
      _active = false;
    });
    widget.input.left = false;
    widget.input.right = false;
    widget.input.up = false;
    widget.input.down = false;
  }

  @override
  void dispose() {
    widget.input.left = false;
    widget.input.right = false;
    widget.input.up = false;
    widget.input.down = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    key: const Key('movement-joystick'),
    behavior: HitTestBehavior.opaque,
    onPanDown: (event) => _move(event.localPosition),
    onPanUpdate: (event) => _move(event.localPosition),
    onPanEnd: (_) => _release(),
    onPanCancel: _release,
    child: SizedBox(
      width: _size,
      height: _size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size.square(_size),
            painter: _JoystickBasePainter(
              direction: _offset / _travel,
              active: _active,
            ),
          ),
          AnimatedContainer(
            // Kembali ke tengah dengan halus, tapi mengikuti jari tanpa jeda.
            duration: _active
                ? Duration.zero
                : const Duration(milliseconds: 160),
            curve: Curves.easeOutBack,
            transform: Matrix4.translationValues(_offset.dx, _offset.dy, 0),
            transformAlignment: Alignment.center,
            width: _knob,
            height: _knob,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _active
                    ? const [Color(0xFFFFFFFF), Color(0xFFCFE3EF)]
                    : const [Color(0xE6FFFFFF), Color(0xB3BFD3E0)],
              ),
              boxShadow: [
                BoxShadow(
                  color: _active
                      ? const Color(0x5554FF8A)
                      : const Color(0x55000000),
                  blurRadius: _active ? 16 : 8,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _JoystickBasePainter extends CustomPainter {
  /// Arah dorongan, panjang 0..1.
  final Offset direction;
  final bool active;

  _JoystickBasePainter({required this.direction, required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 1;

    canvas.drawCircle(center, radius, Paint()..color = _glassFill);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = active ? const Color(0x4DFFFFFF) : _glassBorder
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Penanda arah kecil di empat sisi.
    final tick = Paint()
      ..color = _ink.withValues(alpha: 0.28)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (int i = 0; i < 4; i++) {
      final angle = i * math.pi / 2;
      final dir = Offset(math.cos(angle), math.sin(angle));
      final normal = Offset(-dir.dy, dir.dx);
      final tip = center + dir * (radius - 10);
      final back = center + dir * (radius - 15);
      canvas.drawPath(
        Path()
          ..moveTo(back.dx + normal.dx * 4, back.dy + normal.dy * 4)
          ..lineTo(tip.dx, tip.dy)
          ..lineTo(back.dx - normal.dx * 4, back.dy - normal.dy * 4),
        tick,
      );
    }

    // Busur menyala ke arah dorongan joystick.
    final strength = direction.distance.clamp(0.0, 1.0);
    if (strength > 0.15) {
      final angle = math.atan2(direction.dy, direction.dx);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - 2),
        angle - 0.55,
        1.1,
        false,
        Paint()
          ..color = const Color(
            0xFF54FF8A,
          ).withValues(alpha: 0.35 + strength * 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_JoystickBasePainter old) =>
      old.direction != direction || old.active != active;
}
