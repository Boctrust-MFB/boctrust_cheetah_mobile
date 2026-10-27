import 'package:boctrust_savings_loan/module/kyc/model/kyc_provider_models.dart';
import 'package:boctrust_savings_loan/module/kyc/service/dojah_platform_route.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS chooses the embedded browser', () {
    expect(
      chooseDojahPlatformRoute(isWeb: false, isAndroid: false, isIOS: true),
      DojahPlatformRoute.webView,
    );
  });

  test('Android uses the embedded browser for every operation', () {
    // The native Android SDK (sdk-kotlin v0.4.2) crashes the app on its
    // video-selfie path: the recording fails, then the preview calls toFile()
    // on an empty Uri. Identity therefore runs in the hosted flow too.
    final route = chooseDojahPlatformRoute(
      isWeb: false,
      isAndroid: true,
      isIOS: false,
    );
    expect(route, DojahPlatformRoute.webView);
    expect(
      dojahCaptureMode(route, KycOperation.identity),
      DojahCaptureMode.webView,
    );
    expect(
      dojahCaptureMode(route, KycOperation.governmentId),
      DojahCaptureMode.webView,
    );
  });

  test('other platforms are unsupported', () {
    expect(
      chooseDojahPlatformRoute(isWeb: true, isAndroid: false, isIOS: false),
      DojahPlatformRoute.unsupported,
    );
  });
}
