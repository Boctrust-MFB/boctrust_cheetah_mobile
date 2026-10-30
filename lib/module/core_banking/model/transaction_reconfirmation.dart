import 'package:equatable/equatable.dart';

enum ReconfirmationStatus {
  pending,
  comparing,
  verified,
  failed,
  expired,
  superseded,
}

enum ReconfirmationProvider { smileId, dojah }

/// A selfie reconfirmation that lets one transfer finalize.
///
/// Only what the transfer flow needs is kept. Capture fields the server also
/// returns (method, mode, tokens, callback URL, partner params, consent) are
/// deliberately dropped.
class TransactionReconfirmation extends Equatable {
  const TransactionReconfirmation({
    required this.verificationId,
    required this.status,
    required this.provider,
    required this.withdrawalReference,
    required this.expiresAt,
    this.validUntil,
    this.dojahReference,
  });

  factory TransactionReconfirmation.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('Reconfirmation is not an object.');
    }
    final verificationId = _text(json['verificationId']);
    final withdrawalReference = _text(json['withdrawalReference']);
    if (verificationId == null || withdrawalReference == null) {
      throw const FormatException('Reconfirmation is missing an identifier.');
    }
    final status = switch (json['status']) {
      'pending' => ReconfirmationStatus.pending,
      'comparing' => ReconfirmationStatus.comparing,
      'verified' => ReconfirmationStatus.verified,
      'failed' => ReconfirmationStatus.failed,
      'expired' => ReconfirmationStatus.expired,
      'superseded' => ReconfirmationStatus.superseded,
      _ => throw const FormatException('Unknown reconfirmation status.'),
    };
    final provider = switch (json['provider']) {
      'smile_id' => ReconfirmationProvider.smileId,
      'dojah' => ReconfirmationProvider.dojah,
      _ => throw const FormatException('Unknown reconfirmation provider.'),
    };
    final expiresAt = _time(json['expiresAt']);
    if (expiresAt == null) {
      throw const FormatException('Reconfirmation has no valid expiry.');
    }
    final metadata = json['metadata'];
    return TransactionReconfirmation(
      verificationId: verificationId,
      status: status,
      provider: provider,
      withdrawalReference: withdrawalReference,
      expiresAt: expiresAt,
      validUntil: _time(json['validUntil']),
      dojahReference: metadata is Map ? _text(metadata['reference']) : null,
    );
  }

  final String verificationId;
  final ReconfirmationStatus status;
  final ReconfirmationProvider provider;
  final String withdrawalReference;
  final DateTime expiresAt;
  final DateTime? validUntil;

  /// The Dojah capture nonce; present only while the challenge is pending.
  final String? dojahReference;

  /// Whether this proves [reference] for finalize at [now].
  bool provesTransfer(String reference, DateTime now) =>
      status == ReconfirmationStatus.verified &&
      withdrawalReference == reference &&
      validUntil != null &&
      now.toUtc().isBefore(validUntil!);

  /// A terminal state that can never become verified.
  bool get isTerminalFailure =>
      status == ReconfirmationStatus.failed ||
      status == ReconfirmationStatus.expired ||
      status == ReconfirmationStatus.superseded;

  /// This record without the capture nonce, for keeping after capture.
  TransactionReconfirmation withoutCapture() => TransactionReconfirmation(
    verificationId: verificationId,
    status: status,
    provider: provider,
    withdrawalReference: withdrawalReference,
    expiresAt: expiresAt,
    validUntil: validUntil,
  );

  @override
  List<Object?> get props => [
    verificationId,
    status,
    provider,
    withdrawalReference,
    expiresAt,
    validUntil,
    dojahReference,
  ];
}

String? _text(Object? value) {
  if (value is! String) return null;
  final text = value.trim();
  return text.isEmpty ? null : text;
}

DateTime? _time(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toUtc() : null;
