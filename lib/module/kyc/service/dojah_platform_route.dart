import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/kyc_provider_models.dart';

/// How this device presents Dojah capture.
///
/// Both platforms use the hosted flow in an embedded browser for every
/// operation. iOS never had the native plugin: it is registered for Android
/// only.
///
/// Android left the native SDK, `sdk-kotlin` v0.4.2, for two crashes that kill
/// the host process. On the document pages it advances a persisted page index
/// without bounding it, so `GovDataViewModel.logIdOptionEvents` throws
/// `No stepNumber`. On the video-selfie path `CameraUtil.recordVideo` records
/// to `MediaStore.Video.Media.INTERNAL_CONTENT_URI`, which a third-party app
/// cannot write, and ignores the failed `Finalize`, so
/// `PreviewSelfieFragment` calls `toFile()` on an empty Uri.
///
/// `androidNativeIdentity` is kept, unused, for returning to the SDK once
/// Dojah ships a fix. Until installed builds no longer run the native SDK, the
/// Dojah selfie widget must offer only the photo selfie.
enum DojahPlatformRoute {
  /// The hosted flow in an embedded browser for every operation.
  webView,

  /// Parked: the native SDK for identity, the embedded browser for documents.
  androidNativeIdentity,

  unsupported,
}

/// How one capture is presented.
enum DojahCaptureMode { nativeSdk, webView, unsupported }

DojahPlatformRoute chooseDojahPlatformRoute({
  required bool isWeb,
  required bool isAndroid,
  required bool isIOS,
}) {
  if (isWeb) return DojahPlatformRoute.unsupported;
  if (isAndroid || isIOS) return DojahPlatformRoute.webView;
  return DojahPlatformRoute.unsupported;
}

DojahCaptureMode dojahCaptureMode(
  DojahPlatformRoute route,
  KycOperation operation,
) => switch (route) {
  DojahPlatformRoute.webView => DojahCaptureMode.webView,
  DojahPlatformRoute.androidNativeIdentity =>
    operation == KycOperation.identity
        ? DojahCaptureMode.nativeSdk
        : DojahCaptureMode.webView,
  DojahPlatformRoute.unsupported => DojahCaptureMode.unsupported,
};

final dojahPlatformRouteProvider = Provider<DojahPlatformRoute>(
  (ref) => chooseDojahPlatformRoute(
    isWeb: kIsWeb,
    isAndroid: defaultTargetPlatform == TargetPlatform.android,
    isIOS: defaultTargetPlatform == TargetPlatform.iOS,
  ),
);
