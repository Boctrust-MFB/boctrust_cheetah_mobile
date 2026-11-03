import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/preferences.dart';
import '../../../app/services.dart';
import '../../onboarding/provider/auth_session_provider.dart';
import '../model/user_home_model.dart';
import '../service/home_service.dart';
import '../../../app/session_scoped_notifier.dart';

final userHomeProvider =
    NotifierProvider<UserHomeNotifier, NotifierState<UserHomeData>>(
      UserHomeNotifier.new,
    );

class UserHomeNotifier extends SessionScopedNotifier<UserHomeData> {
  @override
  String get failureMessage => 'Unable to load your account overview.';

  @override
  Future<NotifierState<UserHomeData>> fetch() =>
      ref.read(homeServiceProvider).getOwnHome();
}

/// Visibility toggle for account balances across the app.
///
/// Persisted per signed-in user and hidden by default: signed out, on first
/// use, or when the stored value is unreadable, balances stay hidden. It only
/// hides the value on screen and is never sent to the API.
final homeBalanceHiddenProvider =
    NotifierProvider<HomeBalanceHiddenNotifier, bool>(
      HomeBalanceHiddenNotifier.new,
    );

class HomeBalanceHiddenNotifier extends Notifier<bool> {
  String? get _userId => ref.read(authSessionProvider)?.userId;

  @override
  bool build() {
    final userId = ref.watch(
      authSessionProvider.select((session) => session?.userId),
    );
    if (userId == null) return true;
    try {
      return ref
              .read(sharedPreferencesProvider)
              .getBool(homeBalanceHiddenKey(userId)) ??
          true;
    } catch (_) {
      return true;
    }
  }

  Future<void> toggle() async {
    state = !state;
    final userId = _userId;
    if (userId == null) return;
    await ref
        .read(sharedPreferencesProvider)
        .setBool(homeBalanceHiddenKey(userId), state);
  }
}
