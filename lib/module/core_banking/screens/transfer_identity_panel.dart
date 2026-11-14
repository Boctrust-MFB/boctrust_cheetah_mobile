import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/services.dart';
import '../../../app/theme.dart';
import '../../account/provider/user_providers.dart';
import '../../app_flow/app_ui.dart';
import '../../kyc/model/kyc_configuration_models.dart';
import '../../kyc/model/kyc_provider_models.dart';
import '../../kyc/screens/dojah_capture_screen.dart';
import '../../kyc/service/dojah_config.dart';
import '../../legal/screens/legal_document_screen.dart';
import '../provider/core_transfer_attempt_provider.dart';

/// The identity step of a transfer Core asked liveness for: consent, a
/// Dojah selfie, then waiting for User Service's verdict. Once the attempt
/// is ready to finalize or settled, the attempt view takes over. No money
/// moves here.
class TransferIdentityPanel extends ConsumerStatefulWidget {
  const TransferIdentityPanel({
    required this.attempt,
    required this.onExit,
    super.key,
  });

  final CoreTransferAttempt attempt;

  /// Leaves the transfer flow after the customer cancels.
  final VoidCallback onExit;

  @override
  ConsumerState<TransferIdentityPanel> createState() =>
      _TransferIdentityPanelState();
}

class _TransferIdentityPanelState extends ConsumerState<TransferIdentityPanel> {
  static const _pollEvery = Duration(seconds: 5);
  static const _maxPolls = 24;

  Timer? _poll;
  int _polls = 0;
  bool _busy = false;

  bool get _checking =>
      widget.attempt.phase == CoreTransferPhase.checkingIdentity;

  @override
  void initState() {
    super.initState();
    if (!_checking) {
      final id = widget.attempt.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(coreTransferAttemptProvider.notifier).expireIdentityIfDue(id);
      });
    }
    if (_checking) {
      // Re-entry re-reads the verdict at once. After the frame, since a
      // refresh may settle the attempt synchronously.
      final id = widget.attempt.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(
          ref.read(coreTransferAttemptProvider.notifier).refreshIdentity(id),
        );
      });
      _startPolling();
    }
  }

  @override
  void didUpdateWidget(covariant TransferIdentityPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final entered =
        oldWidget.attempt.id != widget.attempt.id ||
        oldWidget.attempt.phase != widget.attempt.phase;
    if (!entered) return;
    if (_checking) {
      _startPolling();
    } else {
      _stopPolling();
    }
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }

  void _startPolling() {
    _stopPolling();
    _polls = 0;
    final id = widget.attempt.id;
    _poll = Timer.periodic(_pollEvery, (_) {
      if (!mounted || !_checking || ++_polls > _maxPolls) {
        return _stopPolling();
      }
      unawaited(
        ref.read(coreTransferAttemptProvider.notifier).refreshIdentity(id),
      );
    });
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  void _setBusy(bool busy) {
    if (mounted && _busy != busy) setState(() => _busy = busy);
  }

  void _cancel() {
    ref
        .read(coreTransferAttemptProvider.notifier)
        .cancelReview(widget.attempt.id);
    widget.onExit();
  }

  Future<void> _continue() async {
    if (_busy) return;
    // Held directly: this panel may be gone by the time a reply arrives.
    final notifier = ref.read(coreTransferAttemptProvider.notifier);
    final id = widget.attempt.id;
    final widgetId = ref
        .read(dojahConfigProvider)
        .widgetIdFor(KycOperation.identity);
    final messenger = ScaffoldMessenger.of(context);
    if (widgetId.isEmpty) {
      notifier.cancelReview(id);
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Identity check is not configured for this environment.',
          ),
        ),
      );
      widget.onExit();
      return;
    }
    final consentedAt = DateTime.now().toUtc();
    _setBusy(true);
    try {
      final challenge = await notifier.startIdentity(
        id,
        consentedAt: consentedAt,
      );
      if (challenge == null || !mounted) return;
      final email = ref.read(userProfileProvider).data?.email;
      // startIdentity returns only a challenge whose reply named Dojah. The
      // reply names no provider environment, but staging only ever accepts
      // sandbox providers. DOJAH_USE_SANDBOX_BVN decides, as it does for the
      // BVN check.
      final bvn = challenge.bvn;
      final outcome = await Navigator.of(context).push<KycCaptureOutcome>(
        MaterialPageRoute(
          builder: (_) => DojahCaptureScreen(
            widgetId: widgetId,
            referenceId: challenge.dojahReference!,
            operation: KycOperation.identity,
            bvn: bvn == null
                ? null
                : dojahCaptureBvn(
                    bvn,
                    environment: Env.isStaging
                        ? KycProviderEnvironment.sandbox.wireValue
                        : null,
                  ),
            email: email,
          ),
        ),
      );
      // Dojah's WebView reports unknown when it redirects to its
      // confirmation page before posting success, so both count as
      // captured. Only the server's verdict approves the transfer.
      if (outcome == KycCaptureOutcome.submitted ||
          outcome == KycCaptureOutcome.unknown) {
        notifier.identityCaptured(id);
        await notifier.refreshIdentity(id);
      } else {
        notifier.cancelReview(id);
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              "Identity check wasn't completed, so this transfer was not sent.",
            ),
          ),
        );
      }
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _checkAgain() async {
    if (_busy) return;
    _setBusy(true);
    try {
      await ref
          .read(coreTransferAttemptProvider.notifier)
          .refreshIdentity(widget.attempt.id);
    } finally {
      _setBusy(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_checking) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ApiLoadingSection(label: 'Checking your identity…'),
          const SizedBox(height: BocSpace.lg),
          SecondaryButton(
            label: 'Check again',
            isLoading: _busy,
            onPressed: _busy ? null : _checkAgain,
          ),
          const SizedBox(height: BocSpace.xs),
          BocTextButton(label: 'Cancel transfer', onPressed: _cancel),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: BocSpace.md),
        Text(
          "Confirm it's you",
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: BocSpace.xs),
        Text(
          "To protect larger transfers, confirm it's you with a quick selfie. "
          'This check is only for this transfer.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: BocSpace.xs),
        BocTextButton(
          label: 'Privacy policy',
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => const LegalDocumentScreen.privacy(),
            ),
          ),
        ),
        const SizedBox(height: BocSpace.lg),
        PrimaryButton(
          label: 'Continue',
          isLoading: _busy,
          onPressed: _busy ? null : _continue,
        ),
        const SizedBox(height: BocSpace.xs),
        BocTextButton(label: 'Cancel transfer', onPressed: _cancel),
      ],
    );
  }
}
