import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/services.dart';
import '../../onboarding/provider/auth_session_provider.dart';
import '../model/savings_plan_models.dart';
import '../service/core_savings_plan_service.dart';

/// The customer's plans of one product. Re-read when the session changes,
/// so plans never outlive the customer they belong to, and dropped when no
/// screen shows them.
final savingsPlansProvider = FutureProvider.autoDispose
    .family<NotifierState<List<SavingsProductGroup>>, SavingsProductType>((
      ref,
      product,
    ) {
      ref.watch(authSessionProvider);
      return ref.read(coreSavingsPlanServiceProvider).getPlans(product);
    });

/// The products a SmartSave or Fixed Deposit plan can be opened on.
final savingsPlanProductsProvider =
    FutureProvider.autoDispose<NotifierState<List<SavingsPlanProduct>>>((ref) {
      ref.watch(authSessionProvider);
      return ref.read(coreSavingsPlanServiceProvider).getSavingsProducts();
    });

/// A product and one chosen duration: [tenorDays] for a preset or [endDate]
/// for a custom maturity date, never both. [today] is the device's date, so
/// a quote read on an earlier day is read again.
typedef SavingsQuoteKey = ({
  String productCode,
  int? tenorDays,
  DateTime? endDate,
  DateTime today,
});

/// Core's quote for one product and duration.
final savingsPlanQuoteProvider = FutureProvider.autoDispose
    .family<NotifierState<SavingsPlanQuote>, SavingsQuoteKey>((ref, key) {
      ref.watch(authSessionProvider);
      return ref
          .read(coreSavingsPlanServiceProvider)
          .quoteSavingsProduct(
            key.productCode,
            tenorDays: key.tenorDays,
            endDate: key.endDate,
          );
    });

/// One plan with its history, keyed by its server `planId`.
final savingsPlanDetailProvider = FutureProvider.autoDispose
    .family<NotifierState<SavingsPlanDetail>, String>((ref, planId) {
      ref.watch(authSessionProvider);
      return ref.read(coreSavingsPlanServiceProvider).getPlan(planId);
    });
