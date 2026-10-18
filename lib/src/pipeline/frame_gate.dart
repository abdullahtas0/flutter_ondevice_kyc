class FrameGate {
  FrameGate({this.minInterval = const Duration(milliseconds: 200)});

  final Duration minInterval;
  bool _inFlight = false;
  DateTime? _lastAccepted;

  bool get inFlight => _inFlight;

  /// Accepts at most one frame every [minInterval], and never a second frame
  /// while the first is still running.
  bool tryAcquire(DateTime now) {
    if (_inFlight) return false;
    final last = _lastAccepted;
    if (last != null && now.difference(last) < minInterval) return false;
    _inFlight = true;
    _lastAccepted = now;
    return true;
  }

  void release() {
    _inFlight = false;
  }
}
