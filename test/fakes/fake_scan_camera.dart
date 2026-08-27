import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:kadenz_scanner/camera/scan_camera.dart';

/// Hand-rolled [ScanCamera] fake — same house style as `_RecordingPlayer` in
/// `scan_audio_test.dart`: no mocking-library coupling, and the assertions
/// about *what the screen asked the camera to do* stay legible.
///
/// Test-only by construction: it lives under `test/`, so it cannot be reached
/// from `lib/` and can never ship in a build. The production path has exactly
/// one implementation (`MobileScanCamera`).
class FakeScanCamera implements ScanCamera {
  FakeScanCamera({
    ScanTorch torch = ScanTorch.off,
    ScanCameraFacing facing = ScanCameraFacing.back,
  }) : _status = ValueNotifier<ScanCameraStatus>(
          ScanCameraStatus(torch: torch, facing: facing),
        );

  final ValueNotifier<ScanCameraStatus> _status;
  final StreamController<String> _payloads = StreamController<String>.broadcast();

  int startCount = 0;
  int stopCount = 0;
  int disposeCount = 0;
  int torchToggleCount = 0;
  int switchCameraCount = 0;

  @override
  ValueListenable<ScanCameraStatus> get status => _status;

  @override
  Stream<String> get payloads => _payloads.stream;

  @override
  Future<void> start() async {
    startCount++;
    _status.value = _status.value.copyWith(isRunning: true, clearFault: true);
  }

  @override
  Future<void> stop() async {
    stopCount++;
    _status.value = _status.value.copyWith(isRunning: false);
  }

  @override
  Future<void> toggleTorch() async {
    torchToggleCount++;
    final current = _status.value.torch;
    if (current == ScanTorch.unavailable) return;
    _status.value = _status.value.copyWith(
      torch: current == ScanTorch.on ? ScanTorch.off : ScanTorch.on,
    );
  }

  @override
  Future<void> switchCamera() async {
    switchCameraCount++;
    _status.value = _status.value.copyWith(
      facing: _status.value.facing == ScanCameraFacing.back
          ? ScanCameraFacing.front
          : ScanCameraFacing.back,
    );
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
    await _payloads.close();
    _status.dispose();
  }

  @override
  Widget buildPreview(BuildContext context) => const ColoredBox(
        key: ValueKey('fake_camera_preview'),
        color: Color(0xFF101010),
      );

  // --- test drivers -------------------------------------------------------

  /// Push a detection, as if the camera had read a QR code.
  void emit(String payload) => _payloads.add(payload);

  /// Report a camera fault (permission denied, no camera, platform error).
  void raiseFault(ScanCameraFault fault) =>
      _status.value = _status.value.copyWith(fault: fault);

  /// Force a torch state the operator cannot reach by tapping (e.g. a front
  /// camera without a controllable torch).
  void setTorch(ScanTorch torch) =>
      _status.value = _status.value.copyWith(torch: torch);
}
