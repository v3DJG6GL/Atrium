/// "0:42", "12:05": how long something has been running, as m:ss. Minutes
/// keep counting past an hour ("75:00"); negative durations read as 0:00.
String formatElapsed(Duration d) {
  final seconds = d.isNegative ? 0 : d.inSeconds;
  final m = seconds ~/ 60;
  final s = (seconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}
