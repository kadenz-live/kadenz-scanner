import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'scan_camera.dart';

/// Production [ScanCamera]: a thin delegate over [MobileScannerController].
///
/// This is the only file in the app that imports `package:mobile_scanner` —
/// everything above it (the scanner screen and its tests) speaks the plugin-free
/// vocabulary of [ScanCamera].
///
/// The controller is created with `autoStart: false` and started by the screen
/// once the preview is mounted. That is the ordering the plugin documents:
/// starting before a `MobileScanner` widget is attached raises
/// [MobileScannerErrorCode.controllerNotAttached].
class MobileScanCamera implements ScanCamera {
  MobileScanCamera({MobileScannerController? controller})
      : _controller = controller ??
            MobileScannerController(
              detectionSpeed: DetectionSpeed.normal,
              facing: CameraFacing.back,
              // The screen owns start(): see the class doc.
              autoStart: false,
            ) {
    _controller.addListener(_syncStatus);
    _syncStatus();
  }

  final MobileScannerController _controller;
  final ValueNotifier<ScanCameraStatus> _status =
      ValueNotifier<ScanCameraStatus>(const ScanCameraStatus());

  @override
  ValueListenable<ScanCameraStatus> get status => _status;

  @override
  Stream<String> get payloads => _controller.barcodes
      .map(firstPayload)
      .where((payload) => payload != null)
      .cast<String>();

  @override
  Future<void> start() => _controller.start();

  @override
  Future<void> stop() => _controller.stop();

  @override
  Future<void> toggleTorch() => _controller.toggleTorch();

  @override
  Future<void> switchCamera() => _controller.switchCamera();

  @override
  Future<void> dispose() async {
    _controller.removeListener(_syncStatus);
    _status.dispose();
    await _controller.dispose();
  }

  @override
  Widget buildPreview(BuildContext context) {
    return MobileScanner(
      controller: _controller,
      fit: BoxFit.cover,
      // Faults are rendered by the screen from [status], so there is exactly
      // one place deciding what the operator sees. Keep the preview slot black
      // rather than letting the plugin stack its own error icon underneath.
      errorBuilder: (_, __) => const ColoredBox(color: Color(0xFF000000)),
    );
  }

  void _syncStatus() => _status.value = statusOf(_controller.value);

  /// The first non-empty raw value in a capture, or null when the capture
  /// carried nothing scannable.
  ///
  /// A capture can contain several barcodes (a phone screen with two passes on
  /// it). Taking the first non-empty one keeps the pre-abstraction behaviour:
  /// one scan event equals one door decision.
  @visibleForTesting
  static String? firstPayload(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  /// Project a plugin state onto the screen's vocabulary.
  @visibleForTesting
  static ScanCameraStatus statusOf(MobileScannerState state) {
    return ScanCameraStatus(
      isRunning: state.isRunning,
      torch: switch (state.torchState) {
        TorchState.on => ScanTorch.on,
        // `auto` means the platform decides per frame — the operator has not
        // engaged the torch, so the button renders as off.
        TorchState.off || TorchState.auto => ScanTorch.off,
        TorchState.unavailable => ScanTorch.unavailable,
      },
      facing: state.cameraDirection == CameraFacing.front
          ? ScanCameraFacing.front
          : ScanCameraFacing.back,
      fault: faultOf(state.error),
    );
  }

  /// Map a plugin exception to a door-relevant fault, or null when the error
  /// is a benign lifecycle race.
  ///
  /// `controllerAlreadyInitialized` / `controllerInitializing` happen when a
  /// resume and an in-flight start overlap. The camera keeps running, so
  /// surfacing a blocking error panel for them would take the door offline for
  /// no reason.
  @visibleForTesting
  static ScanCameraFault? faultOf(MobileScannerException? error) {
    return switch (error?.errorCode) {
      null => null,
      MobileScannerErrorCode.controllerAlreadyInitialized ||
      MobileScannerErrorCode.controllerInitializing =>
        null,
      MobileScannerErrorCode.permissionDenied =>
        ScanCameraFault.permissionDenied,
      MobileScannerErrorCode.unsupported => ScanCameraFault.unsupported,
      _ => ScanCameraFault.unknown,
    };
  }
}
