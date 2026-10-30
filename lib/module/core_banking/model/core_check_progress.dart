import 'package:equatable/equatable.dart';

import 'core_json.dart';
import 'core_transfer_initiation.dart';

/// Core's reply to a PIN verify, OTP verify or OTP resend: which checks are
/// required, completed and pending, and whether an OTP was sent.
///
/// [otpCode] is Core's development/staging-only copy of the code; production
/// never sends it. It is only shown in the staging test banner.
class CoreCheckProgress extends Equatable {
  const CoreCheckProgress({
    this.reference,
    this.required = const {},
    this.completed = const {},
    this.pending = const {},
    this.otpSent,
    this.otpExpiresAt,
    this.otpCode,
  });

  /// Refuses an unknown check name rather than guessing its meaning.
  factory CoreCheckProgress.fromJson(Object? json) {
    if (json is! Map) throw const FormatException('Invalid check progress.');
    Set<CoreTransferCheck> checks(String key) {
      final raw = json[key];
      if (raw == null) return const {};
      if (raw is! List) throw FormatException('Invalid $key.');
      return Set.unmodifiable({
        for (final value in raw)
          CoreTransferCheck.parse(value) ??
              (throw FormatException('Unknown check in $key.')),
      });
    }

    final sent = json['otpSent'];
    return CoreCheckProgress(
      reference: coreText(json['reference']),
      required: checks('requiredChecks'),
      completed: checks('completedChecks'),
      pending: checks('pendingChecks'),
      otpSent: sent is bool ? sent : null,
      otpExpiresAt: DateTime.tryParse(
        coreText(json['otpExpiresAt']) ?? '',
      )?.toUtc(),
      otpCode: coreText(json['otpCode']),
    );
  }

  final String? reference;
  final Set<CoreTransferCheck> required;
  final Set<CoreTransferCheck> completed;
  final Set<CoreTransferCheck> pending;
  final bool? otpSent;
  final DateTime? otpExpiresAt;

  /// Left out of [props] so it never reaches a log.
  final String? otpCode;

  @override
  List<Object?> get props => [
    reference,
    required,
    completed,
    pending,
    otpSent,
    otpExpiresAt,
  ];
}

/// Whether a PIN/OTP verify reply contradicts what initiation asked for, so
/// the flow must stop rather than continue. A null [progress] is treated as an
/// empty pending set.
bool coreCheckProgressContradicts({
  required CoreTransferCheck step,
  required CoreTransferInitiation initiation,
  required CoreCheckProgress? progress,
}) {
  final pending = progress?.pending ?? const <CoreTransferCheck>{};
  return (pending.contains(CoreTransferCheck.liveness) &&
          !initiation.requiresLiveness) ||
      pending.contains(step) ||
      (step == CoreTransferCheck.otp &&
          pending.contains(CoreTransferCheck.pin)) ||
      (step == CoreTransferCheck.pin &&
          !initiation.needsOtp &&
          pending.contains(CoreTransferCheck.otp)) ||
      // Initiate asked for an OTP but the PIN reply no longer awaits one:
      // never open the OTP sheet for a code that was not sent.
      (step == CoreTransferCheck.pin &&
          initiation.needsOtp &&
          progress != null &&
          !pending.contains(CoreTransferCheck.otp));
}
