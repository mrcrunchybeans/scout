// ignore: avoid_web_libraries_in_flutter
import 'package:web/web.dart' as html;

class SoundFeedback {
  static void ok({num freq = 920, num ms = 110, num volume = .05}) {
    try {
      final ctx = (html.window as dynamic).AudioContext != null
          ? (html.window as dynamic).AudioContext()
          : (html.window as dynamic).webkitAudioContext();
      final osc = ctx.createOscillator();
      final gain = ctx.createGain();
      osc.type = 'sine';
      osc.frequency.value = freq.toDouble();
      gain.gain.value = volume.toDouble();
      osc.connect(gain);
      gain.connect(ctx.destination);
      final t = ctx.currentTime;
      osc.start(t);
      osc.stop(t + (ms / 1000));
    } catch (_) {/* ignore */}
  }

  static void error({num freq = 220, num ms = 180, num volume = .06}) =>
      ok(freq: freq, ms: ms, volume: volume);
}
