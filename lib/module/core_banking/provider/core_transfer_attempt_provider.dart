import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/feature_capability.dart';
import '../../../app/services.dart';
import '../../onboarding/provider/auth_session_provider.dart';
import '../../onboarding/provider/test_otp_provider.dart';
import '../model/core_check_progress.dart';
import '../model/core_submission_models.dart';
import '../model/core_transfer_initiation.dart';
import '../model/core_transfer_requery_models.dart';
import '../model/interbank_models.dart';
import '../model/intrabank_models.dart';
import '../model/transaction_reconfirmation.dart';
import '../service/core_transfer_service.dart';
import '../service/transaction_reconfirmation_service.dart';
import 'core_account_providers.dart';
import 'core_account_activity_providers.dart';
import 'flex_source_check.dart';

enum CoreTransferPhase {
  /// Reviewed and reserved; initiate is being sent. No money moves.
  initiating,

  /// Core recorded a pending transfer; the PIN sheet is open.
  awaitingPin,
  verifyingPin,

  /// The PIN passed and Core sent an OTP; the OTP sheet is open.
  awaitingOtp,
  verifyingOtp,

  /// PIN/OTP passed and Core asked for liveness: consent and capture next.
  awaitingIdentity,

  /// Capture done or resumed; waiting for User Service to say verified.
  checkingIdentity,

  /// Every required check passed; finalize may be sent once.
  readyToFinalize,

  /// Finalize was sent: money may be moving.
  finalizing,
  settled,
}

/// What a PIN or OTP step did. No step moves money.
sealed class CheckStep extends Equatable {
  const CheckStep();

  @override
  List<Object?> get props => [];
}

/// The step passed; the attempt moved to its next phase.
final class CheckPassed extends CheckStep {
  const CheckPassed();
}

/// The step can be tried again on the same initiation, e.g. a wrong PIN.
final class CheckRetry extends CheckStep {
  const CheckRetry(this.message);
  final String message;

  @override
  List<Object?> get props => [message];
}

/// The attempt stopped; its outcome says why.
final class CheckStopped extends CheckStep {
  const CheckStopped();
}

/// One reviewed transfer and what happened to it. Holds no credential.
class CoreTransferAttempt extends Equatable {
  const CoreTransferAttempt({
    required this.id,
    required this.draft,
    required this.phase,
    this.initiation,
    this.outcome,
    this.live,
    this.checking = false,
    this.checkError,
    this.identity,
  });

  final int id;

  /// A [BoctrustTransferDraft] or [InterbankTransferDraft], exactly as
  /// reviewed.
  final Object draft;
  final CoreTransferPhase phase;

  /// The pending transfer Core recorded. Its reference is never used to
  /// check status; only the final tracking reference is.
  final CoreTransferInitiation? initiation;
  final CoreSubmissionOutcome? outcome;

  /// The latest live BankOne status. Once final it is kept until a reversal
  /// replaces it; a later failed or unclear check never erases it.
  final CoreLiveTransferStatus? live;
  final bool checking;

  /// Why the last check could not confirm a status, shown beside the result.
  final String? checkError;

  /// The identity reconfirmation for a liveness transfer. Only a verified
  /// record bound to this initiation's reference lets finalize be sent.
  final TransactionReconfirmation? identity;

  CoreTransferKind get kind => draft is InterbankTransferDraft
      ? CoreTransferKind.interbank
      : CoreTransferKind.intrabank;

  /// The identifier Core issued for a live re-query, if it returned one.
  CoreTrackingReference? get tracking => switch (outcome) {
    AcceptedSubmission(:final ack) => ack.trackingReference(kind),
    _ => null,
  };

  /// Whether money may still be moving: in flight, accepted without a final
  /// status, or with no reliable answer at all.
  bool get unresolved => switch (phase) {
    CoreTransferPhase.finalizing => true,
    CoreTransferPhase.settled => switch (outcome) {
      AcceptedSubmission() => !_isFinal(live?.state),
      UnknownSubmission() => true,
      RejectedSubmission() || null => false,
    },
    _ => false,
  };

  CoreTransferAttempt _with({
    required CoreTransferPhase phase,
    CoreTransferInitiation? initiation,
    CoreSubmissionOutcome? outcome,
    TransactionReconfirmation? identity,
  }) => CoreTransferAttempt(
    id: id,
    draft: draft,
    phase: phase,
    initiation: initiation ?? this.initiation,
    outcome: outcome,
    identity: identity ?? this.identity,
  );

  CoreTransferAttempt _checked({
    required CoreLiveTransferStatus? live,
    bool checking = false,
    String? checkError,
  }) => CoreTransferAttempt(
    id: id,
    draft: draft,
    phase: phase,
    initiation: initiation,
    outcome: outcome,
    live: live,
    checking: checking,
    checkError: checkError,
    identity: identity,
  );

  /// This attempt with [status] as its live result.
  CoreTransferAttempt withLive(CoreLiveTransferStatus status) =>
      _checked(live: status);

  @override
  List<Object?> get props => [
    id,
    draft,
    phase,
    initiation,
    outcome,
    live,
    checking,
    checkError,
    identity,
  ];
}

bool _isFinal(CoreLiveState? state) =>
    state == CoreLiveState.completed ||
    state == CoreLiveState.failed ||
    state == CoreLiveState.reversed;

/// Whether [next] may replace [previous]: a final result is kept unless the
/// money was reversed.
bool _replaces(CoreLiveState? previous, CoreLiveState next) {
  if (!_isFinal(previous)) return true;
  return next == CoreLiveState.reversed && previous != CoreLiveState.reversed;
}

class CoreTransferAttemptState extends Equatable {
  const CoreTransferAttemptState({this.current, this.acknowledged = const []});

  /// The one transfer this session is working on, shared by every transfer
  /// entry so no entry can start a second one while it is unresolved.
  final CoreTransferAttempt? current;

  /// Unresolved transfers the customer chose to set aside, kept visible.
  final List<CoreTransferAttempt> acknowledged;

  @override
  List<Object?> get props => [current, acknowledged];
}

final coreTransferAttemptProvider =
    NotifierProvider<CoreTransferAttemptNotifier, CoreTransferAttemptState>(
      CoreTransferAttemptNotifier.new,
    );

/// Owns every BOCTRUST and interbank transfer for the signed-in customer:
/// initiate, verify the PIN, verify the OTP when Core sends one, reconfirm
/// identity when Core asks for liveness, finalize once, then track.
///
/// Core offers no idempotency key, so finalize is sent at most once. The PIN
/// and OTP pass straight through [verifyPin] and [verifyOtp] and are never
/// kept; finalize carries no credential. A liveness transfer finalizes only
/// with a verified reconfirmation bound to its reference.
class CoreTransferAttemptNotifier extends Notifier<CoreTransferAttemptState> {
  int _nextId = 0;

  /// Bumped when the session ends or changes customer, so a late reply is
  /// dropped instead of landing on the next customer.
  int _generation = 0;

  @override
  CoreTransferAttemptState build() {
    ref.listen(authSessionProvider, (previous, next) {
      if (next == null || previous?.userId != next.userId) clear();
    });
    ref.onDispose(() => _generation++);
    return const CoreTransferAttemptState();
  }

  void _set({
    CoreTransferAttempt? current,
    List<CoreTransferAttempt>? acknowledged,
  }) => state = CoreTransferAttemptState(
    current: current,
    acknowledged: acknowledged ?? state.acknowledged,
  );

  /// The attempt in progress, for callers that outlive their widget.
  CoreTransferAttempt? get current => state.current;

  /// Reserves a new attempt for [draft] before initiating. Null when
  /// transfers are not authorized yet or another attempt is open.
  int? beginReview(Object draft) {
    if (!ref.read(transferAuthorizationReadyProvider)) return null;
    if (state.current != null) return null;
    final attempt = CoreTransferAttempt(
      id: ++_nextId,
      draft: draft,
      phase: CoreTransferPhase.initiating,
    );
    _set(current: attempt);
    return attempt.id;
  }

  /// The customer stopped before finalize; no money moved.
  void cancelReview(int id) {
    final current = state.current;
    if (current?.id == id &&
        current?.phase != CoreTransferPhase.finalizing &&
        current?.phase != CoreTransferPhase.settled) {
      _set();
    }
  }

  CoreTransferAttempt? _open(int id, CoreTransferPhase phase) {
    final current = state.current;
    return current != null && current.id == id && current.phase == phase
        ? current
        : null;
  }

  void _settle(CoreTransferAttempt attempt, CoreRejection reason) => _set(
    current: attempt._with(
      phase: CoreTransferPhase.settled,
      outcome: RejectedSubmission(reason),
    ),
  );

  /// Asks Core to record the reviewed transfer and say which checks finalize
  /// needs. A failure here moved no money.
  Future<void> initiate(int id) async {
    final current = _open(id, CoreTransferPhase.initiating);
    if (current == null || !ref.read(transferAuthorizationReadyProvider)) {
      return;
    }
    final generation = _generation;
    // Core debits Boc Flex whatever the app shows, so a fresh read decides
    // before anything is sent; an unconfirmed read also stops it.
    final check = await ref.read(freshFlexDebitCheckProvider)();
    if (!ref.mounted ||
        generation != _generation ||
        _open(id, CoreTransferPhase.initiating) == null) {
      return;
    }
    if (check != FlexDebitCheck.allowed) {
      return _settle(
        current,
        check == FlexDebitCheck.frozen
            ? CoreRejection.sourcePaused
            : CoreRejection.sourceUnconfirmed,
      );
    }
    final service = ref.read(coreTransferServiceProvider);
    final result = await switch (current.draft) {
      final BoctrustTransferDraft d => service.initiateBoctrust(d),
      final InterbankTransferDraft d => service.initiateInterbank(d),
      _ => throw ArgumentError.value(current.draft, 'draft'),
    };
    if (!ref.mounted ||
        generation != _generation ||
        _open(id, CoreTransferPhase.initiating) == null) {
      return;
    }
    final initiation = result.data;
    if (initiation == null) {
      // A 403 explains itself (e.g. Tier 1 verification still needed), so
      // Core's reason is shown instead of generic copy.
      if (result.statusCode == 403) {
        return _set(
          current: current._with(
            phase: CoreTransferPhase.settled,
            outcome: RejectedSubmission(
              CoreRejection.accountRestricted,
              detail: result.message,
            ),
          ),
        );
      }
      return _settle(current, switch (result.statusCode) {
        400 => CoreRejection.validation,
        404 => CoreRejection.accountMissing,
        _ => CoreRejection.initiationFailed,
      });
    }
    _set(
      current: current._with(
        phase: CoreTransferPhase.awaitingPin,
        initiation: initiation,
      ),
    );
  }

  /// Verifies the PIN. When the initiation needs an OTP, Core sends it and
  /// the attempt waits for it; then, when Core asked for liveness, it waits
  /// for an identity reconfirmation; otherwise it is ready to finalize. The
  /// PIN passes straight through and is never kept.
  Future<CheckStep> verifyPin(int id, String pin) => _verify(
    id,
    CoreTransferCheck.pin,
    (service, attempt, initiation) =>
        service.verifyTransferPin(attempt.kind, initiation, pin),
  );

  /// Verifies the OTP the customer typed; never kept.
  Future<CheckStep> verifyOtp(int id, String otp) => _verify(
    id,
    CoreTransferCheck.otp,
    (service, attempt, initiation) =>
        service.verifyTransferOtp(attempt.kind, initiation, otp),
  );

  Future<CheckStep> _verify(
    int id,
    CoreTransferCheck step,
    Future<NotifierState<CoreCheckProgress>> Function(
      CoreTransferService service,
      CoreTransferAttempt attempt,
      CoreTransferInitiation initiation,
    )
    send,
  ) async {
    final (waiting, verifying) = step == CoreTransferCheck.pin
        ? (CoreTransferPhase.awaitingPin, CoreTransferPhase.verifyingPin)
        : (CoreTransferPhase.awaitingOtp, CoreTransferPhase.verifyingOtp);
    final current = _open(id, waiting);
    final initiation = current?.initiation;
    if (current == null || initiation == null) return const CheckStopped();
    if (initiation.isExpiredAt(DateTime.now())) {
      _settle(current, CoreRejection.initiationExpired);
      return const CheckStopped();
    }
    final generation = _generation;
    _set(current: current._with(phase: verifying));
    final result = await send(
      ref.read(coreTransferServiceProvider),
      current,
      initiation,
    );
    if (!ref.mounted ||
        generation != _generation ||
        _open(id, verifying) == null) {
      return const CheckStopped();
    }
    // Swagger: a 409 on a verify step means it was already completed.
    if (result.isDone || result.statusCode == 409) {
      final contradicts = coreCheckProgressContradicts(
        step: step,
        initiation: initiation,
        progress: result.data,
      );
      if (contradicts) {
        _settle(current, CoreRejection.checksInconsistent);
        return const CheckStopped();
      }
      _showTestOtp(step, result.data);
      _set(
        current: current._with(
          phase: step == CoreTransferCheck.pin && initiation.needsOtp
              ? CoreTransferPhase.awaitingOtp
              : initiation.requiresLiveness
              ? CoreTransferPhase.awaitingIdentity
              : CoreTransferPhase.readyToFinalize,
        ),
      );
      return const CheckPassed();
    }
    if (result.statusCode == 401) {
      _set(current: current._with(phase: waiting));
      return CheckRetry(
        step == CoreTransferCheck.pin
            ? CoreRejection.wrongPin.message
            : 'That code is incorrect or has expired.',
      );
    }
    // Finalize was never sent, so no money moved.
    _settle(current, switch (result.statusCode) {
      400 => CoreRejection.validation,
      403 => CoreRejection.checkRefused,
      404 => CoreRejection.initiationFailed,
      _ => CoreRejection.checkInterrupted,
    });
    return const CheckStopped();
  }

  /// Staging only: offers the code Core sent with a PIN pass, and drops it
  /// once the OTP passed.
  void _showTestOtp(CoreTransferCheck step, CoreCheckProgress? progress) {
    final testOtp = ref.read(testOtpProvider.notifier);
    if (step == CoreTransferCheck.otp) {
      testOtp.clear(TestOtpFlow.coreCheck);
    } else {
      testOtp.showCode(
        TestOtpFlow.coreCheck,
        progress?.otpCode,
        progress?.otpExpiresAt,
      );
    }
  }

  bool _resending = false;

  /// Asks Core to send the OTP again, on the customer's request. Only once
  /// the PIN is verified and an OTP is awaited; one request at a time.
  Future<CheckStep> resendOtp(int id) async {
    final current = _open(id, CoreTransferPhase.awaitingOtp);
    final initiation = current?.initiation;
    if (current == null || initiation == null) {
      return const CheckRetry('Verify your PIN first.');
    }
    if (_resending) return const CheckRetry('A new code is on its way.');
    _resending = true;
    final generation = _generation;
    try {
      final result = await ref
          .read(coreTransferServiceProvider)
          .resendTransferOtp(current.kind, initiation);
      if (!ref.mounted || generation != _generation) {
        return const CheckStopped();
      }
      if (result.isDone) {
        _showTestOtp(CoreTransferCheck.pin, result.data);
        return const CheckPassed();
      }
      if (result.statusCode == 403) {
        final still = _open(id, CoreTransferPhase.awaitingOtp);
        if (still != null) _settle(still, CoreRejection.checkRefused);
        return const CheckStopped();
      }
      return const CheckRetry("We couldn't send a new code. Try again.");
    } finally {
      _resending = false;
    }
  }

  bool _identityBusy = false;

  /// Starts the identity reconfirmation for a liveness transfer, after the
  /// customer consented at [consentedAt]. Returns the pending Dojah challenge
  /// to capture, or null when there is nothing to capture: the attempt then
  /// moved on, settled, or was replaced. No money moves here.
  Future<TransactionReconfirmation?> startIdentity(
    int id, {
    required DateTime consentedAt,
  }) async {
    final current = _open(id, CoreTransferPhase.awaitingIdentity);
    final initiation = current?.initiation;
    if (current == null || initiation == null || _identityBusy) return null;
    if (initiation.isExpiredAt(DateTime.now())) {
      _settle(current, CoreRejection.initiationExpired);
      return null;
    }
    final generation = _generation;
    _identityBusy = true;
    final NotifierState<TransactionReconfirmation> result;
    try {
      result = await ref
          .read(transactionReconfirmationServiceProvider)
          .initiate(initiation.reference, consentedAt: consentedAt);
    } finally {
      if (generation == _generation) _identityBusy = false;
    }
    if (!ref.mounted || generation != _generation) return null;
    final still = _open(id, CoreTransferPhase.awaitingIdentity);
    if (still == null) return null;
    final identity = result.data;
    if (identity == null) {
      _settle(still, switch (result.statusCode) {
        429 || 502 => CoreRejection.identityUnavailable,
        _ => CoreRejection.identityFailed,
      });
      return null;
    }
    if (identity.withdrawalReference != initiation.reference ||
        identity.isTerminalFailure) {
      _settle(still, CoreRejection.identityFailed);
      return null;
    }
    // Only a reply naming Dojah goes on to Dojah capture and its sandbox
    // BVN; any other provider stops here with no money moved.
    if (identity.provider != ReconfirmationProvider.dojah) {
      _settle(still, CoreRejection.identityProviderUnsupported);
      return null;
    }
    switch (identity.status) {
      case ReconfirmationStatus.verified:
        await _proceedIfProven(
          still._with(phase: still.phase, identity: identity.withoutCapture()),
        );
        return null;
      case ReconfirmationStatus.comparing:
        _set(
          current: still._with(
            phase: CoreTransferPhase.checkingIdentity,
            identity: identity.withoutCapture(),
          ),
        );
        return null;
      case ReconfirmationStatus.pending
          when identity.dojahReference?.isNotEmpty ?? false:
        _set(
          current: still._with(phase: still.phase, identity: identity),
        );
        return identity;
      case _:
        // Pending with nothing to capture can never be verified.
        _settle(still, CoreRejection.identityFailed);
        return null;
    }
  }

  /// The customer finished the capture: keep the record without its nonce
  /// and wait for the server's verdict. A cancelled or failed capture calls
  /// [cancelReview] instead; no money moved.
  void identityCaptured(int id) {
    final current = _open(id, CoreTransferPhase.awaitingIdentity);
    final identity = current?.identity;
    if (current == null || identity == null) return;
    _set(
      current: current._with(
        phase: CoreTransferPhase.checkingIdentity,
        identity: identity.withoutCapture(),
      ),
    );
  }

  /// Asks User Service for the reconfirmation's verdict; one request at a
  /// time. A verified record bound to this transfer finalizes it; an error
  /// keeps the phase so the customer can check again.
  Future<void> refreshIdentity(int id) async {
    if (_identityBusy) return;
    final current = _open(id, CoreTransferPhase.checkingIdentity);
    final initiation = current?.initiation;
    final identity = current?.identity;
    if (current == null || initiation == null || identity == null) return;
    final now = DateTime.now();
    if (initiation.isExpiredAt(now) ||
        !now.toUtc().isBefore(identity.expiresAt)) {
      return _settle(current, CoreRejection.initiationExpired);
    }
    final generation = _generation;
    _identityBusy = true;
    try {
      final result = await ref
          .read(transactionReconfirmationServiceProvider)
          .status(identity.verificationId);
      if (!ref.mounted || generation != _generation) return;
      final still = _open(id, CoreTransferPhase.checkingIdentity);
      if (still == null) return;
      final next = result.data;
      if (next == null) {
        final code = result.statusCode;
        // A reply we cannot read ends the attempt; other errors may pass.
        if (code == 404 || (code != null && code >= 200 && code < 300)) {
          _settle(still, CoreRejection.identityFailed);
        }
        return;
      }
      if (next.verificationId != identity.verificationId ||
          next.withdrawalReference != initiation.reference ||
          next.isTerminalFailure) {
        return _settle(still, CoreRejection.identityFailed);
      }
      final updated = still._with(
        phase: still.phase,
        identity: next.withoutCapture(),
      );
      if (next.status == ReconfirmationStatus.verified) {
        return await _proceedIfProven(updated);
      }
      _set(current: updated);
    } finally {
      if (generation == _generation) _identityBusy = false;
    }
  }

  /// Ends an identity step whose Core initiation or challenge has already
  /// expired, so the customer is never asked for consent on a dead transfer.
  void expireIdentityIfDue(int id) {
    final current =
        _open(id, CoreTransferPhase.awaitingIdentity) ??
        _open(id, CoreTransferPhase.checkingIdentity);
    final initiation = current?.initiation;
    if (current == null || initiation == null) return;
    final now = DateTime.now();
    final expiresAt = current.identity?.expiresAt;
    if (initiation.isExpiredAt(now) ||
        (expiresAt != null && !now.toUtc().isBefore(expiresAt))) {
      _settle(current, CoreRejection.initiationExpired);
    }
  }

  /// Finalizes [attempt] only when its identity proves this transfer now;
  /// otherwise settles it. [attempt] carries the record just received.
  Future<void> _proceedIfProven(CoreTransferAttempt attempt) async {
    final initiation = attempt.initiation;
    final identity = attempt.identity;
    final now = DateTime.now();
    if (initiation == null ||
        identity == null ||
        !identity.provesTransfer(initiation.reference, now) ||
        initiation.isExpiredAt(now)) {
      return _settle(attempt, CoreRejection.identityNotConfirmed);
    }
    _set(current: attempt._with(phase: CoreTransferPhase.readyToFinalize));
    await finalize(attempt.id);
  }

  /// Moves the money: one bodyless finalize once every required check has
  /// passed. Repeated calls while one is in flight send nothing. A liveness
  /// transfer is sent only with a verified identity bound to its reference.
  Future<void> finalize(int id) async {
    final current = _open(id, CoreTransferPhase.readyToFinalize);
    final initiation = current?.initiation;
    if (current == null ||
        initiation == null ||
        !ref.read(transferAuthorizationReadyProvider)) {
      return;
    }
    if (initiation.isExpiredAt(DateTime.now())) {
      return _settle(current, CoreRejection.initiationExpired);
    }
    if (initiation.requiresLiveness &&
        !(current.identity?.provesTransfer(
              initiation.reference,
              DateTime.now(),
            ) ??
            false)) {
      return _settle(current, CoreRejection.identityNotConfirmed);
    }
    final generation = _generation;
    _set(current: current._with(phase: CoreTransferPhase.finalizing));
    CoreSubmissionOutcome outcome;
    try {
      outcome = mapCoreTransferSubmission(
        await ref
            .read(coreTransferServiceProvider)
            .finalizeTransfer(current.kind, initiation),
      );
    } catch (_) {
      outcome = const UnknownSubmission();
    }
    if (!ref.mounted ||
        generation != _generation ||
        _open(id, CoreTransferPhase.finalizing) == null) {
      return;
    }
    final restricted =
        outcome is RejectedSubmission &&
        outcome.reason == CoreRejection.transferRestricted;
    // On a liveness transfer a 403 means User Service did not accept the
    // reconfirmation, not that the account is restricted.
    if (restricted && initiation.requiresLiveness) {
      outcome = const RejectedSubmission(CoreRejection.identityNotConfirmed);
    }
    _set(
      current: current._with(
        phase: CoreTransferPhase.settled,
        outcome: outcome,
      ),
    );
    if (outcome is AcceptedSubmission || outcome is UnknownSubmission) {
      ref.read(refreshFlexTransactionHistoryProvider)().ignore();
      ref.read(customerBankAccountsProvider.notifier).load().ignore();
    } else if (restricted) {
      // Possibly frozen from another device: let Home show it.
      ref.read(customerBankAccountsProvider.notifier).load().ignore();
    }
  }

  /// Clears a resolved attempt (rejected or final) so a new one can start.
  void startNewTransfer() {
    final current = state.current;
    if (current != null &&
        current.phase == CoreTransferPhase.settled &&
        !current.unresolved) {
      _set();
    }
  }

  /// The customer accepted that [id] may still go through and wants to start
  /// a different transfer. The old attempt stays listed and is never resent.
  void acknowledgeUnresolved(int id) {
    final current = state.current;
    if (current == null ||
        current.id != id ||
        current.phase != CoreTransferPhase.settled ||
        !current.unresolved) {
      return;
    }
    _set(acknowledged: [...state.acknowledged, current]);
  }

  /// Asks BankOne for [id]'s live status: a read that never resends. Works
  /// for the current attempt and for one set aside. Does nothing without a
  /// tracking reference or while a check is already running.
  Future<void> check(int id) async {
    final attempt = _find(id);
    final tracking = attempt?.tracking;
    if (attempt == null || tracking == null || attempt.checking) return;
    final generation = _generation;
    _replace(attempt._checked(live: attempt.live, checking: true));
    final result = await ref
        .read(coreTransferServiceProvider)
        .requeryTransfer(tracking);
    final latest = _find(id);
    if (!ref.mounted || generation != _generation || latest == null) return;
    final previous = latest.live;
    final next = result.data;
    if (next == null) {
      _replace(
        latest._checked(
          live: previous,
          checkError: result.statusCode == 404
              ? "We couldn't find this transfer to check."
              : "We couldn't check this transfer. Try again shortly.",
        ),
      );
      return;
    }
    if (!_replaces(previous?.state, next.state)) {
      _replace(
        latest._checked(
          live: previous,
          checkError: next.state == previous?.state
              ? null
              : "The latest check didn't match the confirmed result.",
        ),
      );
      return;
    }
    _replace(latest._checked(live: next));
    // Balances come from Core only; refresh once when money settles.
    if (next.state == CoreLiveState.completed ||
        next.state == CoreLiveState.reversed) {
      ref.read(customerBankAccountsProvider.notifier).load().ignore();
      ref.read(refreshFlexTransactionHistoryProvider)().ignore();
    }
  }

  CoreTransferAttempt? _find(int id) {
    final current = state.current;
    if (current?.id == id) return current;
    return state.acknowledged.where((a) => a.id == id).firstOrNull;
  }

  void _replace(CoreTransferAttempt attempt) {
    final current = state.current;
    state = CoreTransferAttemptState(
      current: current?.id == attempt.id ? attempt : current,
      acknowledged: [
        for (final a in state.acknowledged) a.id == attempt.id ? attempt : a,
      ],
    );
  }

  /// Drops everything, including a late reply, when the session ends.
  void clear() {
    _generation++;
    _identityBusy = false;
    state = const CoreTransferAttemptState();
  }
}
