import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadenz_scanner/camera/mobile_scan_camera.dart';
import 'package:kadenz_scanner/camera/scan_camera.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// The plugin-facing half of the camera seam.
///
/// `MobileScanCamera` itself cannot be instantiated in a widget test —
/// `MobileScannerController` grabs a platform channel in its constructor,
/// which is exactly why the seam exists. What *is* testable, and what carries
/// the decisions, are the pure projections from plugin types onto the screen's
/// vocabulary, plus the delegation onto a recording controller. Only
/// `buildPreview` stays uncovered: mounting a real `MobileScanner` widget
/// attaches the plugin's platform session, which a unit test has no business
/// doing.
class _RecordingController extends MobileScannerController {
  _RecordingController() : super(autoStart: false);

  final StreamController<BarcodeCapture> captures =
      StreamController<BarcodeCapture>.broadcast();

  int starts = 0;
  int stops = 0;
  int torchToggles = 0;
  int cameraSwitches = 0;
  int disposals = 0;
  final List<VoidCallback> removedListeners = <VoidCallback>[];

  @override
  void removeListener(VoidCallback listener) {
    removedListeners.add(listener);
    super.removeListener(listener);
  }

  @override
  Stream<BarcodeCapture> get barcodes => captures.stream;

  @override
  Future<void> start({
    CameraFacing? cameraDirection,
    CameraLensType? cameraLensType,
  }) async =>
      starts++;

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> toggleTorch() async => torchToggles++;

  @override
  Future<void> switchCamera([
    SwitchCameraOption option = const ToggleDirection(),
  ]) async =>
      cameraSwitches++;

  @override
  Future<void> dispose() async {
    disposals++;
    await captures.close();
    await super.dispose();
  }
}

void main() {
  MobileScannerState stateWith({
    TorchState torch = TorchState.off,
    CameraFacing facing = CameraFacing.back,
    bool isRunning = true,
    MobileScannerException? error,
  }) {
    return MobileScannerState(
      availableCameras: 2,
      cameraDirection: facing,
      cameraLensType: CameraLensType.wide,
      isInitialized: true,
      isStarting: false,
      isRunning: isRunning,
      size: Size.zero,
      torchState: torch,
      zoomScale: 1,
      deviceOrientation: DeviceOrientation.portraitUp,
      error: error,
    );
  }

  group('firstPayload', () {
    test('takes the first non-empty raw value in a capture', () {
      const capture = BarcodeCapture(
        barcodes: [
          Barcode(rawValue: null),
          Barcode(rawValue: ''),
          Barcode(rawValue: 'signed.token.A'),
          Barcode(rawValue: 'signed.token.B'),
        ],
      );

      // One capture is one door decision: the second code on the same phone
      // screen must not queue a second validation behind the first.
      expect(MobileScanCamera.firstPayload(capture), 'signed.token.A');
    });

    test('returns null when a capture carries nothing scannable', () {
      const capture = BarcodeCapture(
        barcodes: [Barcode(rawValue: null), Barcode(rawValue: '')],
      );

      expect(MobileScanCamera.firstPayload(capture), isNull);
    });

    test('returns null for an empty capture', () {
      expect(MobileScanCamera.firstPayload(const BarcodeCapture()), isNull);
    });
  });

  group('statusOf', () {
    test('projects torch, facing and run state', () {
      final status = MobileScanCamera.statusOf(
        stateWith(torch: TorchState.on, facing: CameraFacing.front),
      );

      expect(status.torch, ScanTorch.on);
      expect(status.facing, ScanCameraFacing.front);
      expect(status.isRunning, isTrue);
      expect(status.fault, isNull);
    });

    test('a torchless camera is reported as unavailable, not off', () {
      final status =
          MobileScanCamera.statusOf(stateWith(torch: TorchState.unavailable));

      expect(status.torch, ScanTorch.unavailable);
    });

    test('auto torch renders as off — the operator has not engaged it', () {
      final status = MobileScanCamera.statusOf(stateWith(torch: TorchState.auto));

      expect(status.torch, ScanTorch.off);
    });

    test('an unknown facing falls back to back', () {
      final status =
          MobileScanCamera.statusOf(stateWith(facing: CameraFacing.unknown));

      expect(status.facing, ScanCameraFacing.back);
    });

    test('carries a permission error through to the fault', () {
      final status = MobileScanCamera.statusOf(
        stateWith(
          error: const MobileScannerException(
            errorCode: MobileScannerErrorCode.permissionDenied,
          ),
        ),
      );

      expect(status.fault, ScanCameraFault.permissionDenied);
    });
  });

  group('faultOf', () {
    test('no error is no fault', () {
      expect(MobileScanCamera.faultOf(null), isNull);
    });

    test('permission denied and unsupported map to their own faults', () {
      expect(
        MobileScanCamera.faultOf(const MobileScannerException(
          errorCode: MobileScannerErrorCode.permissionDenied,
        )),
        ScanCameraFault.permissionDenied,
      );
      expect(
        MobileScanCamera.faultOf(const MobileScannerException(
          errorCode: MobileScannerErrorCode.unsupported,
        )),
        ScanCameraFault.unsupported,
      );
    });

    test('a start/resume race is not shown to the operator', () {
      // The camera is running fine in both cases — blanking the preview with
      // an error panel would take the door offline for a benign race.
      expect(
        MobileScanCamera.faultOf(const MobileScannerException(
          errorCode: MobileScannerErrorCode.controllerAlreadyInitialized,
        )),
        isNull,
      );
      expect(
        MobileScanCamera.faultOf(const MobileScannerException(
          errorCode: MobileScannerErrorCode.controllerInitializing,
        )),
        isNull,
      );
    });

    test('anything else is a generic camera fault', () {
      expect(
        MobileScanCamera.faultOf(const MobileScannerException(
          errorCode: MobileScannerErrorCode.genericError,
        )),
        ScanCameraFault.unknown,
      );
      expect(
        MobileScanCamera.faultOf(const MobileScannerException(
          errorCode: MobileScannerErrorCode.controllerDisposed,
        )),
        ScanCameraFault.unknown,
      );
    });
  });

  group('ScanCameraStatus', () {
    test('equality covers every rendered field', () {
      const base = ScanCameraStatus(isRunning: true, torch: ScanTorch.off);

      expect(base, const ScanCameraStatus(isRunning: true, torch: ScanTorch.off));
      expect(base.hashCode,
          const ScanCameraStatus(isRunning: true, torch: ScanTorch.off).hashCode);
      expect(base, isNot(base.copyWith(torch: ScanTorch.on)));
      expect(base, isNot(base.copyWith(facing: ScanCameraFacing.front)));
      expect(base, isNot(base.copyWith(fault: ScanCameraFault.unknown)));
      expect(base, isNot(base.copyWith(isRunning: false)));
    });

    test('clearFault beats a fault argument so a restart really clears', () {
      const faulted = ScanCameraStatus(fault: ScanCameraFault.permissionDenied);

      expect(faulted.copyWith(clearFault: true).fault, isNull);
      expect(faulted.copyWith().fault, ScanCameraFault.permissionDenied);
    });

    test('toString names the state for failure output', () {
      expect(
        const ScanCameraStatus(torch: ScanTorch.on).toString(),
        contains('torch: ScanTorch.on'),
      );
    });
  });

  group('delegation onto the plugin controller', () {
    test('operator controls reach the plugin one-for-one', () async {
      final controller = _RecordingController();
      final camera = MobileScanCamera(controller: controller);

      await camera.start();
      await camera.stop();
      await camera.toggleTorch();
      await camera.switchCamera();

      expect(controller.starts, 1);
      expect(controller.stops, 1);
      expect(controller.torchToggles, 1);
      expect(controller.cameraSwitches, 1);

      await camera.dispose();
    });

    test('status tracks the controller and stops tracking after dispose',
        () async {
      final controller = _RecordingController();
      final camera = MobileScanCamera(controller: controller);
      expect(camera.status.value.torch, ScanTorch.unavailable);

      controller.value = controller.value.copyWith(
        isRunning: true,
        torchState: TorchState.on,
        cameraDirection: CameraFacing.front,
      );

      expect(camera.status.value,
          const ScanCameraStatus(isRunning: true, torch: ScanTorch.on, facing: ScanCameraFacing.front));

      await camera.dispose();

      expect(controller.disposals, 1);
      // Detached before the controller went down: a late plugin callback can
      // no longer write into a disposed notifier on the way out.
      expect(controller.removedListeners, hasLength(1));
    });

    test('only non-empty payloads reach the screen', () async {
      final controller = _RecordingController();
      final camera = MobileScanCamera(controller: controller);
      final seen = <String>[];
      final subscription = camera.payloads.listen(seen.add);

      controller.captures.add(const BarcodeCapture(barcodes: [Barcode(rawValue: null)]));
      controller.captures.add(const BarcodeCapture(barcodes: [Barcode(rawValue: '')]));
      controller.captures.add(
        const BarcodeCapture(barcodes: [Barcode(rawValue: 'signed.token.A')]),
      );
      await pumpEventQueue();

      expect(seen, ['signed.token.A']);

      await subscription.cancel();
      await camera.dispose();
    });
  });
}
