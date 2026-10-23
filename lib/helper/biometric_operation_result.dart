import 'biometric_auth_service.dart';

class BiometricOperationResult {
  const BiometricOperationResult({
    required this.succeeded,
    this.cancelled = false,
    this.message,
  });

  const BiometricOperationResult.cancelled()
    : succeeded = false,
      cancelled = true,
      message = null;

  final bool succeeded;
  final bool cancelled;
  final String? message;
}

/// Maps a biometric prompt outcome to the user-facing result. The fallback
/// credential ('password' or 'PIN') is the only wording that differs per flow.
BiometricOperationResult biometricOperationResultFor(
  BiometricAuthOutcome outcome, {
  required String fallbackCredential,
}) => switch (outcome) {
  BiometricAuthOutcome.success => const BiometricOperationResult(
    succeeded: true,
  ),
  BiometricAuthOutcome.cancelled => const BiometricOperationResult.cancelled(),
  BiometricAuthOutcome.temporaryLockout => BiometricOperationResult(
    succeeded: false,
    message:
        'Too many attempts. Try again shortly or use your $fallbackCredential.',
  ),
  BiometricAuthOutcome.permanentLockout => BiometricOperationResult(
    succeeded: false,
    message:
        'Biometrics are locked on this device. Unlock your device, or '
        'use your $fallbackCredential.',
  ),
  BiometricAuthOutcome.notEnrolled ||
  BiometricAuthOutcome.unavailable ||
  BiometricAuthOutcome.unsupported => BiometricOperationResult(
    succeeded: false,
    message:
        'Biometrics are not available right now. Use your $fallbackCredential.',
  ),
  BiometricAuthOutcome.failure => BiometricOperationResult(
    succeeded: false,
    message:
        'Biometric check failed. Try again or use your $fallbackCredential.',
  ),
};
