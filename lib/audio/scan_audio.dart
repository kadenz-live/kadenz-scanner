import 'package:audioplayers/audioplayers.dart';

/// Plays short audio cues for the scanner result panel.
///
/// Two cues are bundled (`assets/sounds/success.m4a`, `assets/sounds/fail.m4a`)
/// — both are ~3-5 KB AAC tones generated at build time. The success cue is a
/// short high beep (1100 Hz / 120 ms), the fail cue a longer low buzz
/// (220 Hz / 350 ms). Door staff can tell them apart from across the door
/// even when the phone is in a pocket.
///
/// Each play allocates its own `AudioPlayer` instance — the cues are short
/// enough that overlapping presses simply layer (a rapid double-scan plays
/// twice without the second tap silencing the first). The instance is
/// disposed automatically once playback completes via `release: low_latency`
/// semantics: we set `setReleaseMode(ReleaseMode.release)` so the player
/// tears itself down after the source finishes.
///
/// Failure is silent: if the platform refuses audio (no entitlement, missing
/// asset, AVAudioSession contention), the haptic + visual panel still carry
/// the result and the scan flow is uninterrupted.
class ScanAudio {
  ScanAudio({AudioPlayer Function()? playerFactory})
      : _playerFactory = playerFactory ?? AudioPlayer.new;

  final AudioPlayer Function() _playerFactory;

  Future<void> playSuccess() => _play('sounds/success.m4a');
  Future<void> playFail() => _play('sounds/fail.m4a');

  Future<void> _play(String assetPath) async {
    try {
      final player = _playerFactory();
      await player.setReleaseMode(ReleaseMode.release);
      await player.play(AssetSource(assetPath));
    } catch (_) {
      // Intentional: audio is an enhancement, not a guard. The haptic +
      // result panel are the load-bearing feedback channels.
    }
  }
}
