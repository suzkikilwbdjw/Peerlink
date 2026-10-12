import 'dart:collection';

/// Скорость по скользящему окну в ~3 секунды.
///
/// Если новых данных нет больше двух секунд, скорость считается нулевой
class SpeedMeter {
  static const Duration _window = Duration(seconds: 3);
  static const Duration _staleAfter = Duration(seconds: 2);

  final Queue<(DateTime, int)> _samples = Queue();
  int _total = 0;

  void add(int bytes) {
    _total += bytes;

    final now = DateTime.now();
    _samples.add((now, _total));

    while (_samples.length > 2 && now.difference(_samples.first.$1) > _window) {
      _samples.removeFirst();
    }
  }

  double get bytesPerSecond {
    if (_samples.length < 2) return 0;

    final first = _samples.first;
    final last = _samples.last;

    if (DateTime.now().difference(last.$1) > _staleAfter) return 0;

    final ms = last.$1.difference(first.$1).inMilliseconds;
    if (ms <= 0) return 0;

    return (last.$2 - first.$2) * 1000 / ms;
  }
}
