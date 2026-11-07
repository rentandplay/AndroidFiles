/// Anchors server UTC to elapsed time so changing the device clock cannot
/// change a running countdown. Server due dates and fees remain authoritative.
class ServerClock {
  ServerClock({Duration Function()? elapsed, DateTime Function()? localNow})
      : _elapsed = elapsed,
        _localNow = localNow ?? DateTime.now;
  static final instance = ServerClock();
  final Stopwatch _watch = Stopwatch()..start();
  final Duration Function()? _elapsed;
  final DateTime Function() _localNow;
  DateTime? _anchor;
  Duration _anchorElapsed = Duration.zero;
  Duration get _ticks => _elapsed?.call() ?? _watch.elapsed;
  bool get synchronized => _anchor != null;
  void synchronize(DateTime serverTime) {
    _anchor = serverTime.toUtc();
    _anchorElapsed = _ticks;
  }

  DateTime get now => _anchor == null
      ? _localNow().toUtc()
      : _anchor!.add(_ticks - _anchorElapsed);
}
