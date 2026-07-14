import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadenz_scanner/audio/scan_audio.dart';

/// Hand-rolled fake — keeps the test free of mocking-library coupling and
/// makes the assertions about *what was played* legible at a glance.
class _RecordingPlayer implements AudioPlayer {
  final List<String> playedPaths = [];
  final List<ReleaseMode> releaseModes = [];
  bool throwOnSetReleaseMode = false;

  @override
  Future<void> setReleaseMode(ReleaseMode mode) async {
    if (throwOnSetReleaseMode) throw StateError('boom');
    releaseModes.add(mode);
  }

  @override
  Future<void> play(
    Source source, {
    double? volume,
    AudioContext? ctx,
    Duration? position,
    PlayerMode? mode,
    double? balance,
  }) async {
    if (source is AssetSource) {
      playedPaths.add(source.path);
    }
  }

  // Anything else used by the audioplayers surface is a no-op for these tests.
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  group('ScanAudio', () {
    test('playSuccess plays the success asset and sets release mode', () async {
      final player = _RecordingPlayer();
      final audio = ScanAudio(playerFactory: () => player);

      await audio.playSuccess();

      expect(player.releaseModes, [ReleaseMode.release]);
      expect(player.playedPaths, ['sounds/success.m4a']);
    });

    test('playFail plays the fail asset', () async {
      final player = _RecordingPlayer();
      final audio = ScanAudio(playerFactory: () => player);

      await audio.playFail();

      expect(player.playedPaths, ['sounds/fail.m4a']);
    });

    test('swallows player errors silently — audio must never crash a scan',
        () async {
      final player = _RecordingPlayer()..throwOnSetReleaseMode = true;
      final audio = ScanAudio(playerFactory: () => player);

      // No throw, no rethrow — silent failure is the contract.
      await expectLater(audio.playSuccess(), completes);
      expect(player.playedPaths, isEmpty);
    });

    test('uses a fresh player per call so overlapping scans layer naturally',
        () async {
      final players = <_RecordingPlayer>[];
      final audio = ScanAudio(playerFactory: () {
        final p = _RecordingPlayer();
        players.add(p);
        return p;
      });

      await audio.playSuccess();
      await audio.playSuccess();

      expect(players.length, 2);
      expect(players[0].playedPaths, ['sounds/success.m4a']);
      expect(players[1].playedPaths, ['sounds/success.m4a']);
    });
  });
}
