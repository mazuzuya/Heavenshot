import 'dart:ui';

class AimTarget {
  final Offset? target;
  final Offset? direction;
  final Offset? screen;
  AimTarget({this.target, this.direction, this.screen});
}

class InputController {
  bool left = false;
  bool right = false;
  bool up = false;
  bool down = false;
  bool jump = false;
  bool jumpPressed = false;
  AimTarget? aim;
  AimTarget? shot;
  int? arrowRequest;
  bool engaged = false;

  Offset Function(Offset) projector = (Offset p) => p;

  bool consumeJump() {
    final v = jumpPressed;
    jumpPressed = false;
    return v;
  }

  AimTarget? consumeShot() {
    final v = shot;
    shot = null;
    return v;
  }

  int? consumeArrowRequest() {
    final v = arrowRequest;
    arrowRequest = null;
    return v;
  }

  void pollGamepad() {}

  void setProjector(Offset Function(Offset) fn) => projector = fn;

  InputController get state => this;
}
