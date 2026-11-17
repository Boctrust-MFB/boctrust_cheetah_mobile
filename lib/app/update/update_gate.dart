import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'app_update_controller.dart';
import 'update_policy.dart';
import 'update_policy_service.dart';

bool _isRequired(WidgetRef ref) =>
    ref.read(appUpdateControllerProvider).decision.kind == UpdateKind.required;

/// Triggers update checks and swallows system back while an update is
/// required. Sits above `MaterialApp` so it is asked about back before
/// `WidgetsApp` pops the navigator.
class AppUpdateScope extends ConsumerStatefulWidget {
  const AppUpdateScope({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppUpdateScope> createState() => _AppUpdateScopeState();
}

class _AppUpdateScopeState extends ConsumerState<AppUpdateScope>
    with WidgetsBindingObserver {
  bool _backgrounded = false;
  StreamSubscription<void>? _policyUpdates;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _policyUpdates = ref
        .read(updatePolicyServiceProvider)
        .updates
        .listen((_) => _check());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _check();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_policyUpdates?.cancel());
    super.dispose();
  }

  void _check() {
    unawaited(ref.read(appUpdateControllerProvider.notifier).checkForUpdate());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A biometric prompt only makes the app inactive; that is not a return.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _backgrounded = true;
    } else if (state == AppLifecycleState.resumed && _backgrounded) {
      _backgrounded = false;
      _check();
    }
  }

  @override
  Future<bool> didPopRoute() async => _isRequired(ref);

  // Claiming the gesture stops WidgetsBinding falling back to handlePopRoute
  // when it ends. Other observers that also claim it (the navigator) still
  // receive the gesture callbacks, so a predictive back animation may start;
  // the pop itself is swallowed by didPopRoute above.
  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) =>
      _isRequired(ref);

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Covers every route with the update screen while an update is required.
/// The routes stay alive underneath.
class UpdateGate extends ConsumerWidget {
  const UpdateGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final required =
        ref.watch(appUpdateControllerProvider.select((s) => s.decision.kind)) ==
        UpdateKind.required;
    // Same tree either way, so toggling the gate never remounts [child].
    return Stack(
      fit: StackFit.passthrough,
      children: [
        ExcludeSemantics(
          excluding: required,
          child: ExcludeFocus(
            excluding: required,
            child: AbsorbPointer(absorbing: required, child: child),
          ),
        ),
        if (required) const _UpdateGateScreen(),
      ],
    );
  }
}

class _UpdateGateScreen extends ConsumerWidget {
  const _UpdateGateScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appUpdateControllerProvider);
    final controller = ref.read(appUpdateControllerProvider.notifier);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final showInconclusive = !state.checking && state.lastCheckInconclusive;

    return Positioned.fill(
      child: Material(
        color: colors.surface,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      IconsaxPlusLinear.arrow_circle_up,
                      size: 56,
                      color: colors.primary,
                    ),
                    const SizedBox(height: 24),
                    Semantics(
                      header: true,
                      child: Text(
                        'Update required',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'This version of Cheetah is no longer supported. '
                      'Update to continue.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    if (showInconclusive) ...[
                      const SizedBox(height: 16),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          "Couldn't reach the store. Check your connection "
                          'and try again.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.error,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 32),
                    FilledButton(
                      onPressed: () => unawaited(controller.openStore()),
                      child: const Text('Update'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: state.checking
                          ? null
                          : () => unawaited(controller.checkForUpdate()),
                      child: state.checking
                          ? Semantics(
                              label: 'Checking for update',
                              child: const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
