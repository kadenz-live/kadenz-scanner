import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Whether the torch (flashlight) can be used at all, and whether it is lit.
enum ScanTorch {
  /// The active camera has no controllable torch — the button stays disabled.
  unavailable,

  /// Torch is controllable and currently off.
  off,

  /// Torch is controllable and currently lit.
  on,
}

/// Which physical camera feeds the preview.
enum ScanCameraFacing { back, front }

/// Why the camera preview is unusable. Kept coarse on purpose: the scanner
/// screen maps each fault to the actions that can still help — grant
/// permission and retry, fall back to manual entry, or step back to the event
/// picker when manual entry is not addressable.
enum ScanCameraFault {
  /// The operator denied (or never granted) camera permission.
  permissionDenied,

  /// No usable camera on this device.
  unsupported,

  /// Anything else the platform reported while starting or running.
  unknown,
}

/// Immutable snapshot of everything the scanner screen renders about the
/// camera. Delivered through [ScanCamera.status] so the screen can rebuild
/// from a single listenable instead of polling the plugin.
@immutable
class ScanCameraStatus {
  const ScanCameraStatus({
    this.isRunning = false,
    this.torch = ScanTorch.unavailable,
    this.facing = ScanCameraFacing.back,
    this.fault,
  });

  final bool isRunning;
  final ScanTorch torch;
  final ScanCameraFacing facing;

  /// Non-null when the preview cannot be shown. The screen renders a blocking
  /// panel in place of the preview; scanning is impossible until it clears.
  final ScanCameraFault? fault;

  ScanCameraStatus copyWith({
    bool? isRunning,
    ScanTorch? torch,
    ScanCameraFacing? facing,
    ScanCameraFault? fault,
    bool clearFault = false,
  }) {
    return ScanCameraStatus(
      isRunning: isRunning ?? this.isRunning,
      torch: torch ?? this.torch,
      facing: facing ?? this.facing,
      fault: clearFault ? null : (fault ?? this.fault),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ScanCameraStatus &&
      other.isRunning == isRunning &&
      other.torch == torch &&
      other.facing == facing &&
      other.fault == fault;

  @override
  int get hashCode => Object.hash(isRunning, torch, facing, fault);

  @override
  String toString() =>
      'ScanCameraStatus(isRunning: $isRunning, torch: $torch, '
      'facing: $facing, fault: $fault)';
}

/// The camera surface the scanner screen talks to.
///
/// Deliberately thin: it covers exactly what `ScannerScreen` uses — lifecycle
/// (start/stop/dispose), the two operator controls (torch, camera switch), the
/// detection stream, the rendered preview, and an observable [status].
///
/// The point of the seam is testability. `MobileScannerController` reaches
/// straight for a platform channel in its constructor, so a screen holding one
/// directly cannot be driven from a widget test at all. With this interface the
/// production path stays exactly one implementation
/// (`MobileScanCamera`, in `mobile_scan_camera.dart`, the only file in the app
/// that imports `package:mobile_scanner`), while tests supply a fake that
/// pushes payloads and faults on demand.
abstract interface class ScanCamera {
  /// Current camera state. Emits on torch/facing/run-state/fault changes.
  ValueListenable<ScanCameraStatus> get status;

  /// Non-empty raw QR payloads, in detection order.
  ///
  /// One event per capture: unwrapping a capture to its first non-empty
  /// barcode is the implementation's job, not the screen's.
  Stream<String> get payloads;

  /// Begin (or resume) the camera. Safe to call when already running.
  Future<void> start();

  /// Pause the camera without tearing it down (app backgrounded).
  Future<void> stop();

  Future<void> toggleTorch();

  Future<void> switchCamera();

  /// Release the camera and the [status] listenable. The owner of the instance
  /// calls this exactly once — for the scanner screen, from `dispose()`.
  Future<void> dispose();

  /// The live preview widget, to be placed at the bottom of the screen stack.
  Widget buildPreview(BuildContext context);
}
