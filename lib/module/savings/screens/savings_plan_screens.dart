part of 'savings_screens.dart';

/// Plan lists, detail and management. Everything shown comes from Core;
/// with no server plan the screen explains the gap. Deposit, edit
/// and withdraw are each gated by their own capability.
extension SavingsPlanScreens on FlowPageState {
  Color _productAccent(SavingsProductType type) {
    final colors = context.bocColors;
    return switch (type) {
      SavingsProductType.flex => colors.flexAccent,
      SavingsProductType.smartSave => colors.smartSaveAccent,
      SavingsProductType.fixed => colors.fixedAccent,
      SavingsProductType.padi => colors.padiAccent,
    };
  }

  Color _productContainer(SavingsProductType type) {
    final colors = context.bocColors;
    return switch (type) {
      SavingsProductType.flex => colors.flexContainer,
      SavingsProductType.smartSave => colors.smartSaveContainer,
      SavingsProductType.fixed => colors.fixedContainer,
      SavingsProductType.padi => colors.padiContainer,
    };
  }

  IconData _eventIcon(SavingsPlanEventType type) => switch (type) {
    SavingsPlanEventType.topUp => IconsaxPlusLinear.add_circle,
    SavingsPlanEventType.interestCredit => IconsaxPlusLinear.percentage_circle,
    SavingsPlanEventType.withdrawal ||
    SavingsPlanEventType.maturityPayout ||
    SavingsPlanEventType.liquidation => IconsaxPlusLinear.export,
    SavingsPlanEventType.created => IconsaxPlusLinear.flag,
    SavingsPlanEventType.unknown => IconsaxPlusLinear.activity,
  };

  Color _eventAccent(SavingsPlanEventType type, SavingsProductType product) {
    final colors = context.bocColors;
    return switch (type) {
      SavingsPlanEventType.topUp ||
      SavingsPlanEventType.interestCredit => colors.successText,
      SavingsPlanEventType.withdrawal ||
      SavingsPlanEventType.maturityPayout ||
      SavingsPlanEventType.liquidation => colors.errorText,
      _ => _productAccent(product),
    };
  }

  Color _eventContainer(SavingsPlanEventType type, SavingsProductType product) {
    final colors = context.bocColors;
    return switch (type) {
      SavingsPlanEventType.topUp ||
      SavingsPlanEventType.interestCredit => colors.successContainer,
      SavingsPlanEventType.withdrawal ||
      SavingsPlanEventType.maturityPayout ||
      SavingsPlanEventType.liquidation => colors.errorContainer,
      _ => _productContainer(product),
    };
  }

  /// Money in or out; the created and unknown rows carry no direction.
  String _eventSign(SavingsPlanEventType type) => switch (type) {
    SavingsPlanEventType.topUp || SavingsPlanEventType.interestCredit => '+',
    SavingsPlanEventType.withdrawal ||
    SavingsPlanEventType.maturityPayout ||
    SavingsPlanEventType.liquidation => '\u2212',
    _ => '',
  };

  String _planMoney(String? naira) => ref.watch(homeBalanceHiddenProvider)
      ? '₦ ••••••'
      : formatApiAmount(naira, currency: 'NGN') ?? 'Unavailable';

  String? _eventAmount(SavingsPlanEvent event, {required bool hidden}) {
    final amount = event.amount;
    if (amount == null || num.tryParse(amount) == 0) return null;
    final value = hidden
        ? '₦ ••••••'
        : formatApiAmount(amount, currency: 'NGN');
    return value == null
        ? null
        : '${hidden ? '' : _eventSign(event.type)}$value';
  }

  Future<void> _showPlanEvent(SavingsPlan plan, SavingsPlanEvent event) async {
    final hidden = ref.read(homeBalanceHiddenProvider);
    final amount = _eventAmount(event, hidden: hidden);
    final occurred = event.createdAt?.toLocal();
    await AppActionSheet.show<void>(
      context: context,
      builder: (_) => AppActionSheet(
        icon: _eventIcon(event.type),
        iconColor: _eventAccent(event.type, plan.type),
        iconBackground: _eventContainer(event.type, plan.type),
        title: event.type.label,
        subtitle: 'Activity in ${plan.name}',
        child: TransactionDetailRows(
          rows: [
            (label: 'Type', value: event.type.label),
            if (amount != null) (label: 'Amount', value: amount),
            if (occurred != null)
              (
                label: 'Date and time',
                value: DateFormat('d MMM yyyy, h:mm a').format(occurred),
              ),
            (label: 'Plan', value: plan.name),
          ],
        ),
      ),
    );
  }

  /// One product's plans, as Core groups them, with the product balance.
  Widget _savingsPlansScreen(SavingsProductType type, String title) {
    final state = ref.watch(savingsPlansProvider(type));
    final theme = Theme.of(context);
    return AppScaffold(
      title: title,
      activeSection: AppSection.save,
      onBack: back,
      onSectionSelected: goSection,
      body: _plansList(
        type,
        state,
        theme,
        const EdgeInsets.fromLTRB(
          BocSpace.gutter,
          BocSpace.xxs,
          BocSpace.gutter,
          BocSpace.lg,
        ).clearOfNav(context),
      ),
    );
  }

  Widget _plansList(
    SavingsProductType type,
    AsyncValue<NotifierState<List<SavingsProductGroup>>> state,
    ThemeData theme,
    EdgeInsets padding,
  ) {
    return RefreshIndicator(
      onRefresh: () => ref.refresh(savingsPlansProvider(type).future),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: padding,
        children: switch (state) {
          AsyncData(:final value)
              when value.data != null || value.status == ServiceStatus.empty =>
            switch (value.data
                ?.where((group) => group.type == type)
                .firstOrNull) {
              final group? => [
                SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: _productContainer(type),
                              borderRadius: BorderRadius.circular(BocRadius.sm),
                            ),
                            child: SizedBox.square(
                              dimension: 40,
                              child: Icon(
                                type == SavingsProductType.fixed
                                    ? IconsaxPlusLinear.lock
                                    : IconsaxPlusLinear.flag,
                                color: _productAccent(type),
                                size: 22,
                              ),
                            ),
                          ),
                          const SizedBox(width: BocSpace.sm),
                          Expanded(
                            child: Text(
                              group.productName,
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                          if (_frozenAccountNumber(group.accountNumber) != null)
                            const FrozenLabel(),
                        ],
                      ),
                      const SizedBox(height: BocSpace.sm),
                      Text(
                        'Available balance',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: BocSpace.xxs),
                      BocMoneyText(
                        _planMoney(
                          _watchCoreAccounts().data?.accounts
                              .where(
                                (account) =>
                                    account.accountNumber ==
                                    group.accountNumber,
                              )
                              .firstOrNull
                              ?.availableBalance,
                        ),
                        semanticsLabel: 'Product balance',
                      ),
                      if (group.rate != null) ...[
                        const SizedBox(height: BocSpace.xs),
                        Text(
                          '${group.rate}% p.a.',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: _productAccent(type),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_frozenAccountNumber(group.accountNumber)
                    case final frozen?)
                  FrozenAccountBanner.savings(
                    frozen,
                    group.productName,
                    onUnfreeze: (number) =>
                        openUnfreezeFlow(context, ref, number),
                  ),
                if (_canCreatePlan(type)) ...[
                  const SizedBox(height: BocSpace.sm),
                  PrimaryButton(
                    label: type == SavingsProductType.fixed
                        ? 'Create a new deposit'
                        : 'Create a new goal',
                    icon: IconsaxPlusLinear.add,
                    onPressed: () => _startPlanCreation(type),
                  ),
                ],
                const SizedBox(height: BocSpace.lg),
                if (group.plans.isEmpty)
                  const ApiStateCard(
                    title: 'No plans yet',
                    message: 'Plans you create will appear here.',
                    tone: ApiStateTone.info,
                  )
                else ...[
                  Semantics(
                    header: true,
                    child: Text(
                      type == SavingsProductType.fixed
                          ? 'Your deposits (${group.plans.length})'
                          : 'Your goals (${group.plans.length})',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  for (final plan in group.plans) ...[
                    const SizedBox(height: BocSpace.sm),
                    _planTile(plan),
                  ],
                ],
              ],
              _ => [
                SavingsEmptyState(
                  icon: IconsaxPlusLinear.save_2,
                  title: 'No ${type.displayName} plans yet',
                  message: 'Plans you create will appear here.',
                  actionLabel: _canCreatePlan(type) ? 'Create a plan' : null,
                  onAction: _canCreatePlan(type)
                      ? () => _startPlanCreation(type)
                      : null,
                ),
              ],
            },
          AsyncData(:final value) => [
            ApiStateCard(
              title: 'Plans unavailable',
              message: value.message ?? "We couldn't load your plans.",
              tone: ApiStateTone.error,
              actionLabel: 'Retry',
              onAction: () => ref.invalidate(savingsPlansProvider(type)),
            ),
          ],
          _ => const [ApiLoadingSection(label: 'Loading your plans')],
        },
      ),
    );
  }

  Widget _planTile(SavingsPlan plan) {
    final theme = Theme.of(context);
    final colors = context.bocColors;
    final maturity = plan.maturityDate;
    return SurfaceCard(
      onTap: () => go(
        AppRoutes.savingsPlanDetail,
        arguments: AppRouteArguments(entityId: plan.id),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(plan.name, style: theme.textTheme.titleSmall),
              ),
              const SizedBox(width: BocSpace.xs),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: BocSpace.xs,
                  vertical: BocSpace.xxs,
                ),
                decoration: BoxDecoration(
                  color: _productContainer(plan.type),
                  borderRadius: BorderRadius.circular(BocRadius.pill),
                ),
                child: Text(
                  plan.status.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: _productAccent(plan.type),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: BocSpace.sm),
          Text('Plan balance', style: theme.textTheme.bodySmall),
          const SizedBox(height: BocSpace.xxs),
          Text(
            _planMoney(plan.principal),
            style: theme.textTheme.titleLarge?.figures,
          ),
          if (maturity != null || plan.target != null) ...[
            const SizedBox(height: BocSpace.sm),
            Divider(height: 1, color: colors.border),
            const SizedBox(height: BocSpace.xs),
            Wrap(
              spacing: BocSpace.sm,
              runSpacing: BocSpace.xxs,
              children: [
                if (plan.target case final target?)
                  Text(
                    'Target ${_planMoney(target)}',
                    style: theme.textTheme.bodySmall,
                  ),
                if (maturity != null)
                  Text(
                    'Matures ${DateFormat('d MMM yyyy').format(maturity)}',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _savingsPlanDetailScreen() {
    final planId = routeArguments.entityId;
    final state = planId == null
        ? null
        : ref.watch(savingsPlanDetailProvider(planId));
    final detail = state?.value?.data;
    if (detail == null) {
      return AppScaffold(
        title: 'Savings plan',
        activeSection: AppSection.save,
        onBack: back,
        onSectionSelected: goSection,
        body: ListView(
          padding: const EdgeInsets.all(BocSpace.gutter).clearOfNav(context),
          children: [
            switch (state) {
              AsyncData(:final value) when value.statusCode == 404 =>
                ApiStateCard(
                  title: 'Plan unavailable',
                  message: 'This plan is no longer available.',
                  tone: ApiStateTone.info,
                  actionLabel: 'Back to plans',
                  onAction: () {
                    ref.invalidate(savingsPlansProvider);
                    back();
                  },
                ),
              AsyncData(:final value) => ApiStateCard(
                title: 'Plan unavailable',
                message: value.message ?? "We couldn't load this plan.",
                tone: ApiStateTone.error,
                actionLabel: 'Retry',
                onAction: () =>
                    ref.invalidate(savingsPlanDetailProvider(planId!)),
              ),
              null => const ApiStateCard(
                title: 'Plan unavailable',
                message: 'This plan is no longer available.',
                tone: ApiStateTone.info,
              ),
              _ => const ApiLoadingSection(label: 'Loading your plan'),
            },
          ],
        ),
      );
    }
    final plan = detail.plan;
    final theme = Theme.of(context);
    final rate = plan.rate;
    final hidden = ref.watch(homeBalanceHiddenProvider);
    final progress =
        plan.type == SavingsProductType.smartSave &&
            !hidden &&
            (plan.status == SavingsPlanStatus.active ||
                plan.status == SavingsPlanStatus.pendingFunding)
        ? savingsPlanProgress(principal: plan.principal, target: plan.target)
        : null;
    String date(DateTime value) => DateFormat('d MMM yyyy').format(value);
    final productGroup = ref
        .watch(savingsPlansProvider(plan.type))
        .value
        ?.data
        ?.where((group) => group.type == plan.type)
        .firstOrNull;
    final accountNumber = detail.accountNumber ?? productGroup?.accountNumber;
    final frozenAccount = _frozenAccountNumber(accountNumber);
    // Core only deletes a plan with no money in it, so the action is offered
    // only once the principal reads as exactly zero.
    final canDelete =
        balanceToKobo(plan.principal) == '0' &&
        ref
            .read(
              featureAvailabilityProvider(FeatureCapability.savingsPlanDelete),
            )
            .isAvailable;
    return AppScaffold(
      title: plan.name,
      activeSection: AppSection.save,
      onBack: back,
      onSectionSelected: goSection,
      actions: [
        PopupMenuButton<String>(
          tooltip: 'More options',
          onSelected: (action) => switch (action) {
            'edit' => _gatedPlanAction(FeatureCapability.savingsPlanEdit),
            'delete' => _deletePlan(plan),
            'interest' => go(
              AppRoutes.interestHistory,
              arguments: AppRouteArguments(entityId: plan.id),
            ),
            _ when frozenAccount != null =>
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text(kSavingsAccountFrozenMessage)),
              ),
            _ => _withdrawFromPlan(plan, accountNumber),
          },
          itemBuilder: (_) => [
            if (ref
                .read(
                  featureAvailabilityProvider(
                    FeatureCapability.savingsPlansView,
                  ),
                )
                .isAvailable)
              const PopupMenuItem(
                value: 'interest',
                child: Text('Interest history'),
              ),
            const PopupMenuItem(value: 'edit', child: Text('Edit plan')),
            const PopupMenuItem(value: 'withdraw', child: Text('Withdraw')),
            if (canDelete)
              const PopupMenuItem(value: 'delete', child: Text('Delete plan')),
          ],
        ),
      ],
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: () =>
                  ref.refresh(savingsPlanDetailProvider(plan.id).future),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(
                  BocSpace.gutter,
                ).clearOfNav(context),
                children: [
                  if (frozenAccount != null) ...[
                    FrozenAccountBanner.savings(
                      frozenAccount,
                      productGroup?.productName ?? plan.type.displayName,
                      onUnfreeze: (number) =>
                          openUnfreezeFlow(context, ref, number),
                    ),
                    const SizedBox(height: BocSpace.sm),
                  ],
                  SavingsPlanHero(
                    status: plan.status.label,
                    amount: _planMoney(plan.principal),
                    accent: _productAccent(plan.type),
                    container: _productContainer(plan.type),
                    icon: plan.type == SavingsProductType.fixed
                        ? IconsaxPlusLinear.lock
                        : IconsaxPlusLinear.flag,
                    onDeposit: () => _topUpPlan(plan),
                    rate: rate == null ? null : '$rate% per annum',
                    progress: progress,
                    progressLabel: progress == null
                        ? null
                        : progress.reached
                        ? 'Target reached'
                        : '${_planMoney(plan.principal)} of '
                              '${_planMoney(plan.target)} target',
                  ),
                  const SizedBox(height: BocSpace.md),
                  SavingsFactGroup(
                    title: 'Your plan',
                    rows: [
                      if (plan.target case final target?)
                        (label: 'Target', value: _planMoney(target)),
                      if (plan.type == SavingsProductType.smartSave)
                        (
                          label: 'Auto-save',
                          value: switch ((
                            plan.recurringAmount,
                            plan.saveFrequency,
                          )) {
                            (final amount?, final frequency?) =>
                              '${_planMoney(amount)} '
                                  '${frequency.label.toLowerCase()}',
                            _ => 'Manual deposits',
                          },
                        ),
                      if (plan.startDate case final start?)
                        (label: 'Started', value: date(start)),
                      if (plan.maturityDate case final maturity?)
                        (label: 'Matures', value: date(maturity)),
                      if (plan.tenorDays case final days?)
                        (label: 'Tenor', value: '$days days'),
                    ],
                  ),
                  if (plan.accruedInterest != null ||
                      plan.interestEarned != null ||
                      plan.projectedInterest != null) ...[
                    const SizedBox(height: BocSpace.md),
                    SavingsFactGroup(
                      title: 'Interest & returns',
                      rows: [
                        if (plan.accruedInterest case final accrued?)
                          (
                            label: 'Interest so far',
                            value: _planMoney(accrued),
                          ),
                        if (plan.interestEarned case final interest?)
                          (
                            label: 'Interest earned',
                            value: _planMoney(interest),
                          ),
                        if (plan.projectedInterest case final projected?)
                          (
                            label: 'Projected at maturity',
                            value: _planMoney(projected),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: BocSpace.lg),
                  Semantics(
                    header: true,
                    child: Text('Activity', style: theme.textTheme.titleMedium),
                  ),
                  const SizedBox(height: BocSpace.xs),
                  if (detail.events.isEmpty)
                    SurfaceCard(
                      child: Text(
                        'Deposits, interest and withdrawals will appear here.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    )
                  else
                    SurfaceCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (final (index, event)
                              in detail.events.indexed) ...[
                            if (index > 0)
                              Divider(
                                height: 1,
                                indent: BocSpace.md,
                                endIndent: BocSpace.md,
                                color: context.bocColors.border,
                              ),
                            SavingsActivityRow(
                              icon: _eventIcon(event.type),
                              label: event.type.label,
                              accent: _eventAccent(event.type, plan.type),
                              container: _eventContainer(event.type, plan.type),
                              date: event.createdAt == null
                                  ? null
                                  : DateFormat(
                                      'd MMM yyyy · h:mm a',
                                    ).format(event.createdAt!.toLocal()),
                              amount: _eventAmount(event, hidden: hidden),
                              onTap: () => _showPlanEvent(plan, event),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _gatedPlanAction(FeatureCapability capability) async {
    if (!ref.read(featureAvailabilityProvider(capability)).isAvailable) {
      await BocUnavailableSheet.show(context);
    }
  }

  /// Soft-deletes an empty plan after an explicit confirmation. The result
  /// comes from Core's reply and a refreshed list, never from a resend.
  Future<void> _deletePlan(SavingsPlan plan) async {
    final confirmed = await AppConfirmSheet.show(
      context,
      title: 'Delete plan?',
      message:
          'A plan can only be deleted when it has no money in it and no '
          'interest is still being paid. Once deleted it no longer shows in '
          'your savings.',
      confirmLabel: 'Delete plan',
      cancelLabel: 'Keep plan',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final actions = ref.read(savingsPlanActionProvider.notifier);
    await actions.deletePlan(plan.id);
    if (!mounted) return;
    final state = ref
        .read(savingsPlanActionProvider)
        .viewFor(SavingsPlanAction.delete, plan.id);
    switch (state.phase) {
      case SavingsPlanActionPhase.done:
        messenger.showSnackBar(const SnackBar(content: Text('Plan deleted.')));
        go(AppRoutes.home);
      case SavingsPlanActionPhase.idle:
        // Another savings action was still sending, so nothing was sent.
        messenger.showSnackBar(
          const SnackBar(content: Text(savingsPlanBusyMessage)),
        );
      default:
        messenger.showSnackBar(
          SnackBar(content: Text(state.message ?? 'Request failed.')),
        );
    }
  }

  Future<void> _topUpPlan(SavingsPlan plan) async {
    if (!ref
        .read(featureAvailabilityProvider(FeatureCapability.savingsPlanDeposit))
        .isAvailable) {
      await BocUnavailableSheet.show(context);
      return;
    }
    // The sheet blocks Back itself while sending; a barrier tap or drag
    // would close it mid-request.
    await AppActionSheet.show<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (_) =>
          SavingsPlanTopUpSheet(planId: plan.id, planName: plan.name),
    );
  }

  /// Early withdrawal costs a fee on the interest, so it needs an explicit,
  /// clearly labelled confirmation; the safe choice is the prominent one.
  Future<void> _withdrawFromPlan(
    SavingsPlan plan,
    String? accountNumber,
  ) async {
    if (!ref
        .read(
          featureAvailabilityProvider(FeatureCapability.savingsPlanWithdraw),
        )
        .isAvailable) {
      await BocUnavailableSheet.show(context);
      return;
    }
    final matured = plan.status == SavingsPlanStatus.matured;
    final percent = plan.earlyWithdrawalFeePercent;
    final fee = percent == null ? 'the' : 'a $percent%';
    final confirmed = await AppConfirmSheet.show(
      context,
      title: 'Withdraw?',
      message: matured
          ? 'Your money will move to Boc Flex Savings.'
          : 'Withdrawing early returns your principal and the interest earned '
                'so far to Boc Flex Savings, minus '
                '$fee early withdrawal fee on that interest.',
      confirmLabel: matured ? 'Withdraw' : 'Withdraw early',
      cancelLabel: 'Keep saving',
      destructive: !matured,
    );
    if (!confirmed || !mounted) return;
    final withdrawn = await AppActionSheet.show<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => SavingsPlanWithdrawSheet(
        planId: plan.id,
        accountNumber: accountNumber,
      ),
    );
    if (withdrawn == true && mounted) back();
  }
}

/// One wizard for every savings product: each type contributes its steps,
/// all steps edit one [SavingsPlanDraft], and the draft stays on the device
/// until Core creates the plan. Creating is gated by the product's create
/// capability; SmartSave and Fixed Deposit are created in Core and funded
/// from Boc Flex, and Padi has no Core plan yet.
class _SavingsPlanWizard extends ConsumerStatefulWidget {
  const _SavingsPlanWizard({
    required this.type,
    required this.onExit,
    required this.onCreated,
  });

  final SavingsProductType type;
  final VoidCallback onExit;

  /// Called with the new plan's id once Core confirms it.
  final ValueChanged<String> onCreated;

  @override
  ConsumerState<_SavingsPlanWizard> createState() => _SavingsPlanWizardState();
}

enum _WizardStep { goal, amount, schedule, days, padiGroup, start, confirm }

class _SavingsPlanWizardState extends ConsumerState<_SavingsPlanWizard> {
  late SavingsPlanDraft _draft = SavingsPlanDraft(type: widget.type);
  int _index = 0;
  final _name = TextEditingController();
  final _amount = TextEditingController();
  final _recurring = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _recurring.dispose();
    super.dispose();
  }

  List<_WizardStep> get _steps => switch (widget.type) {
    SavingsProductType.smartSave => [
      _WizardStep.goal,
      _WizardStep.schedule,
      if (_draft.autoSave) _WizardStep.days,
      _WizardStep.confirm,
    ],
    // Core takes a recurring schedule for target savings only.
    SavingsProductType.fixed => [
      _WizardStep.schedule,
      _WizardStep.amount,
      _WizardStep.confirm,
    ],
    SavingsProductType.padi => [
      _WizardStep.padiGroup,
      _WizardStep.days,
      _WizardStep.start,
      _WizardStep.confirm,
    ],
    SavingsProductType.flex => [_WizardStep.confirm],
  };

  _WizardStep get _step => _steps[_index];

  /// The SmartSave target is checked against the quote on the schedule step;
  /// the Fixed principal is checked against it here.
  bool get _amountValid => switch (widget.type) {
    SavingsProductType.smartSave => savingsPlanNaira(_draft.amount) != null,
    SavingsProductType.fixed => _quote?.acceptsDeposit(_draft.amount) ?? false,
    SavingsProductType.padi => periodicSavingsAmountValid(_draft.amount),
    SavingsProductType.flex => savingsPlanNaira(_draft.amount) != null,
  };

  /// Created in Core and funded from Boc Flex.
  bool get _createsInCore => widget.type.coreCode != null;

  /// Core's catalogue row for this product, as of the last build.
  SavingsPlanProduct? _product;

  /// Core's quote for the chosen duration, as of the last build.
  SavingsPlanQuote? _quote;
  AsyncValue<NotifierState<SavingsPlanQuote>>? _quoteState;

  /// The quote request for the chosen duration: its days for a preset, the
  /// date for a custom maturity date. Null until a duration within the
  /// product's bounds is chosen.
  SavingsQuoteKey? get _quoteKey {
    final product = _product;
    if (product == null) return null;
    final now = DateTime.now();
    if (_draft.tenorDaysOn(now, product) == null) return null;
    final today = DateTime(now.year, now.month, now.day);
    final custom = _draft.customMaturityDate;
    return custom == null
        ? (
            productCode: product.productCode,
            tenorDays: savingsMonthPresetDays[_draft.durationMonths],
            endDate: null,
            today: today,
          )
        : (
            productCode: product.productCode,
            tenorDays: null,
            endDate: DateTime(custom.year, custom.month, custom.day),
            today: today,
          );
  }

  /// The first deposit Core moves from Boc Flex, and the `amount` sent:
  /// the quote's minimum for SmartSave, the typed principal for Fixed.
  String? get _openingNaira => widget.type == SavingsProductType.fixed
      ? savingsPlanNaira(_draft.amount)
      : _quote?.minAmount;

  String get _openingAmount =>
      formatApiAmount(_openingNaira, currency: 'NGN') ?? 'the first deposit';

  String _naira(String amount) =>
      formatApiAmount(amount, currency: 'NGN') ?? '₦$amount';

  String get _planKind =>
      widget.type == SavingsProductType.fixed ? 'deposit' : 'goal';

  /// Why the typed SmartSave [amount] cannot be the target, or null when it
  /// fits. With a [quote] it is checked against that duration's terms;
  /// without one, against the lowest opening deposit Core lists.
  String? _targetError(String amount, [SavingsPlanQuote? quote]) {
    if (quote != null) {
      if (quote.acceptsTarget(amount)) return null;
      final max = quote.maxAmount;
      if (max != null && quote.exceedsMax(amount)) {
        return "Your target can't be more than ${_naira(max)} for this "
            'duration.';
      }
      return 'Your target must be above the ${_naira(quote.minAmount)} '
          'opening deposit.';
    }
    final lowest = _product?.lowestMinAmount;
    final typed = balanceToKobo(savingsPlanNaira(amount) ?? '');
    if (lowest == null || typed == null) return null;
    if (BigInt.parse(typed) > BigInt.parse(balanceToKobo(lowest)!)) {
      return null;
    }
    return 'Your target must be above the opening deposit, which starts at '
        '${_naira(lowest)}.';
  }

  bool get _stepValid => switch (_step) {
    _ when _createsInCore && _product == null => false,
    _WizardStep.goal =>
      _draft.name.trim().isNotEmpty &&
          _amountValid &&
          (widget.type != SavingsProductType.smartSave ||
              _targetError(_draft.amount, _quote) == null),
    _WizardStep.amount => _amountValid,
    _WizardStep.schedule =>
      _quote != null &&
          (widget.type != SavingsProductType.smartSave ||
              _targetError(_draft.amount, _quote) == null),
    _WizardStep.days when _createsInCore =>
      _draft.frequency != null &&
          periodicSavingsAmountValid(_draft.recurringAmount),
    _WizardStep.days =>
      _draft.frequency != null &&
          (_draft.frequency == SavingsFrequency.daily ||
              _draft.contributionDays.isNotEmpty),
    _WizardStep.padiGroup =>
      _draft.name.trim().isNotEmpty &&
          (_draft.memberCount ?? 0) >= 2 &&
          _amountValid,
    _WizardStep.start => _draft.startDate != null,
    _WizardStep.confirm => true,
  };

  void _update(SavingsPlanDraft next) => setState(() => _draft = next);

  Future<void> _pickMaturityDate() async {
    final product = _product;
    if (product == null) return;
    final today = DateTime.now();
    final firstDate = DateTime(
      today.year,
      today.month,
      today.day + product.shortestTenorDays,
    );
    final lastDate = DateTime(
      today.year,
      today.month,
      today.day + product.longestTenorDays,
    );
    final selected = _draft.customMaturityDate;
    final picked = await showDatePicker(
      context: context,
      firstDate: firstDate,
      lastDate: lastDate,
      initialDate:
          selected != null &&
              !selected.isBefore(firstDate) &&
              !selected.isAfter(lastDate)
          ? selected
          : firstDate,
    );
    if (picked != null && mounted) {
      _update(
        _draft.copyWith(customMaturityDate: picked, clearDurationMonths: true),
      );
    }
  }

  /// Shown on the confirm step when another savings action is sending.
  String? _busy;

  Future<bool> _confirmOpeningTransfer(String amount) async {
    final openingAmount =
        formatApiAmount(amount, currency: 'NGN') ?? _naira(amount);
    final name = _draft.name.trim();
    return await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: const Text('Confirm opening transfer'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (name.isNotEmpty) ...[
                  Text(name, style: Theme.of(dialog).textTheme.titleMedium),
                  const SizedBox(height: BocSpace.sm),
                ],
                Text(
                  widget.type == SavingsProductType.smartSave
                      ? 'Creating this goal moves $openingAmount from Boc '
                            'Flex Savings into the new plan. This is its '
                            'minimum opening balance for the duration you '
                            'chose.'
                      : 'Creating this $_planKind moves $openingAmount '
                            'from Boc Flex Savings into the new plan.',
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialog).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialog).pop(true),
                child: const Text('Confirm and create'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _showCreateFailure(String? message) async {
    final insufficient = RegExp(
      r'insufficient|not enough|low balance',
      caseSensitive: false,
    ).hasMatch(message ?? '');
    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(
          insufficient
              ? 'Not enough in Boc Flex'
              : 'Could not create $_planKind',
        ),
        content: Text(
          insufficient
              ? 'You need $_openingAmount in Boc Flex Savings to open this '
                    '$_planKind. Add money to Boc Flex and try again.'
              : message ?? 'Please try again.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialog).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void back() {
    // A create in flight finishes on this screen.
    final action = ref.read(savingsPlanActionProvider);
    if (action.phase == SavingsPlanActionPhase.sending &&
        action.startedBy(SavingsPlanAction.create)) {
      return;
    }
    if (_index == 0) {
      widget.onExit();
    } else {
      setState(() => _index--);
    }
  }

  Future<void> _next() async {
    if (_step != _WizardStep.confirm) {
      setState(() => _index++);
      return;
    }
    final capability = widget.type.createCapability;
    if (capability == null ||
        !ref.read(featureAvailabilityProvider(capability)).isAvailable ||
        !_createsInCore) {
      await BocUnavailableSheet.show(
        context,
        title: '${widget.type.displayName} is not available yet',
      );
      return;
    }
    final quote = _quote;
    final request = quote == null ? null : _draft.toCreateRequest(quote);
    if (request == null) {
      setState(() => _index = _steps.indexOf(_WizardStep.schedule));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Check the duration and amount.')),
      );
      return;
    }
    if (ref.read(savingsPlanActionProvider).busyFor(SavingsPlanAction.create)) {
      setState(() => _busy = savingsPlanBusyMessage);
      return;
    }
    if (_createsInCore && !await _confirmOpeningTransfer(request.amount)) {
      return;
    }
    if (!mounted) return;
    if (ref.read(savingsPlanActionProvider).busyFor(SavingsPlanAction.create)) {
      setState(() => _busy = savingsPlanBusyMessage);
      return;
    }
    setState(() => _busy = null);
    final actions = ref.read(savingsPlanActionProvider.notifier);
    await actions.create(request);
    if (!mounted) return;
    final action = ref
        .read(savingsPlanActionProvider)
        .viewFor(SavingsPlanAction.create);
    switch (action.phase) {
      case SavingsPlanActionPhase.done:
        final planId = action.planId;
        if (planId != null) widget.onCreated(planId);
      case SavingsPlanActionPhase.unknown:
        // Core may have created it; leave so the customer checks their plans
        // instead of creating it twice.
        await AppActionSheet.show<void>(
          context: context,
          builder: (sheet) => SavingsPlanNotConfirmedSheet(
            message: action.message ?? '',
            onClose: () => Navigator.of(sheet).pop(),
          ),
        );
        if (mounted) widget.onExit();
      case SavingsPlanActionPhase.failed:
        await _showCreateFailure(action.message);
      case SavingsPlanActionPhase.idle || SavingsPlanActionPhase.sending:
        break;
    }
  }

  /// Watches the catalogue and the chosen duration's quote on every step, so
  /// neither is dropped and re-read between steps, and returns the catalogue
  /// state; null for a product not created in Core.
  AsyncValue<NotifierState<List<SavingsPlanProduct>>>? _watchCoreTerms() {
    if (!_createsInCore) return null;
    final catalogue = ref.watch(savingsPlanProductsProvider);
    // A product with no tenor bands has no terms to open a plan on.
    _product = catalogue.value?.data
        ?.where(
          (product) =>
              product.productCode == widget.type.coreCode &&
              product.tenors.isNotEmpty,
        )
        .firstOrNull;
    final key = _quoteKey;
    final quote = key == null ? null : ref.watch(savingsPlanQuoteProvider(key));
    _quoteState = quote;
    _quote = quote == null || quote.isLoading || quote.hasError
        ? null
        : quote.value?.data;
    return catalogue;
  }

  /// Stands in for the steps until Core's catalogue has this product.
  Widget? _catalogueGate(
    AsyncValue<NotifierState<List<SavingsPlanProduct>>>? catalogue,
  ) {
    if (catalogue == null || _product != null) return null;
    return switch (catalogue) {
      _ when catalogue.isLoading => const ApiLoadingSection(
        label: 'Loading plan options',
      ),
      AsyncData(:final value) when value.data != null => ApiStateCard(
        title: '${widget.type.displayName} is not available',
        message: 'New plans cannot be opened on this product right now.',
        tone: ApiStateTone.info,
      ),
      AsyncData(:final value) => ApiStateCard(
        title: 'Plan options unavailable',
        message: value.message ?? "We couldn't load this product's terms.",
        tone: ApiStateTone.error,
        actionLabel: 'Retry',
        onAction: () => ref.invalidate(savingsPlanProductsProvider),
      ),
      AsyncError() => ApiStateCard(
        title: 'Plan options unavailable',
        message: "We couldn't load this product's terms.",
        tone: ApiStateTone.error,
        actionLabel: 'Retry',
        onAction: () => ref.invalidate(savingsPlanProductsProvider),
      ),
      _ => const ApiLoadingSection(label: 'Loading plan options'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gate = _catalogueGate(_watchCoreTerms());
    final steps = _steps;
    final action = ref
        .watch(savingsPlanActionProvider)
        .viewFor(SavingsPlanAction.create);
    final sending = action.phase == SavingsPlanActionPhase.sending;
    final failure = _step == _WizardStep.confirm ? _busy : null;
    final title = switch (widget.type) {
      SavingsProductType.padi => 'Create a Padi',
      SavingsProductType.fixed => 'New Fixed Deposit',
      _ => 'Start a new goal',
    };
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) back();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: Padding(
            padding: const EdgeInsets.only(left: BocSpace.xs),
            child: BocBackButton(onPressed: back),
          ),
          leadingWidth: BocSpace.minTouch + BocSpace.md,
          title: Text(title),
        ),
        body: SafeArea(
          top: false,
          child: ResponsiveContent(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    BocSpace.gutter,
                    BocSpace.xs,
                    BocSpace.gutter,
                    0,
                  ),
                  child: Semantics(
                    label: 'Step ${_index + 1} of ${steps.length}',
                    excludeSemantics: true,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(BocRadius.pill),
                      child: LinearProgressIndicator(
                        minHeight: 4,
                        value: (_index + 1) / steps.length,
                        color: theme.brightness == Brightness.dark
                            ? BocColors.goldLight
                            : BocColors.navy,
                        backgroundColor: context.bocColors.border,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    // A fresh subtree per step: otherwise a field in the same
                    // slot (Fixed's amount, then its name) keeps the focused
                    // input and its number keyboard.
                    key: ValueKey(_step),
                    padding: const EdgeInsets.all(BocSpace.gutter),
                    children: gate == null ? _stepBody(theme) : [gate],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    BocSpace.gutter,
                    0,
                    BocSpace.gutter,
                    BocSpace.md,
                  ),
                  child: Column(
                    children: [
                      PrimaryButton(
                        label: _step == _WizardStep.confirm
                            ? switch (widget.type) {
                                SavingsProductType.smartSave => 'Create goal',
                                SavingsProductType.fixed => 'Create deposit',
                                _ => 'Confirm & create',
                              }
                            : 'Continue',
                        isLoading: sending,
                        onPressed: _stepValid && !sending ? _next : null,
                      ),
                      if (failure != null) ...[
                        const SizedBox(height: BocSpace.xs),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            failure,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: context.bocColors.errorText,
                            ),
                          ),
                        ),
                      ],
                      if (_step == _WizardStep.confirm)
                        BocTextButton(
                          label: 'Go back and edit',
                          onPressed: sending ? null : back,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _heading(ThemeData theme, String text, [String? detail]) => Padding(
    padding: const EdgeInsets.only(bottom: BocSpace.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(text, style: theme.textTheme.titleLarge),
        ),
        if (detail != null) ...[
          const SizedBox(height: BocSpace.xxs),
          Text(detail, style: theme.textTheme.bodyMedium),
        ],
      ],
    ),
  );

  Widget _label(ThemeData theme, String text) => Padding(
    padding: const EdgeInsets.only(top: BocSpace.md, bottom: BocSpace.xs),
    child: Text(text, style: theme.textTheme.labelMedium),
  );

  /// The chosen duration's quote: loading, Core's refusal with a retry, or
  /// the terms Core applies to it.
  List<Widget> _quoteSection(ThemeData theme) {
    final key = _quoteKey;
    final state = _quoteState;
    if (key == null || state == null) return const [];
    ApiStateCard refused(String? message) => ApiStateCard(
      title: 'Duration unavailable',
      message: message ?? "We couldn't check this duration.",
      tone: ApiStateTone.error,
      actionLabel: 'Retry',
      onAction: () => ref.invalidate(savingsPlanQuoteProvider(key)),
    );
    final quote = _quote;
    return [
      const SizedBox(height: BocSpace.md),
      switch (state) {
        _ when state.isLoading => const ApiLoadingSection(
          label: 'Checking this duration',
          compact: true,
        ),
        AsyncData() when quote != null => SavingsFactGroup(
          title: 'For this duration',
          rows: _quoteRows(quote),
        ),
        AsyncData(:final value) => refused(value.message),
        _ => refused(null),
      },
    ];
  }

  /// What Core applies to the chosen duration, as its quote states it;
  /// [withLimits] adds the first-deposit minimum and maximum.
  List<({String label, String value})> _quoteRows(
    SavingsPlanQuote quote, {
    bool withLimits = true,
  }) {
    final fixed = widget.type == SavingsProductType.fixed;
    final max = quote.maxAmount;
    return [
      (
        label: 'Maturity date',
        value: DateFormat('d MMM yyyy').format(quote.endDate),
      ),
      (label: 'Interest rate', value: '${quote.interestRatePercent}% p.a.'),
      (
        label: 'Early withdrawal fee',
        value: '${quote.earlyWithdrawalFeePercent}% of interest',
      ),
      if (withLimits) ...[
        (
          label: fixed ? 'Minimum deposit' : 'Opening deposit',
          value: _naira(quote.minAmount),
        ),
        if (max != null)
          (
            label: fixed ? 'Maximum deposit' : 'Maximum target',
            value: _naira(max),
          ),
      ],
    ];
  }

  /// [validateNow] shows the error before the first edit; an edited field
  /// re-runs its validator on every rebuild, so a new quote is reflected.
  Widget _amountField(String label, {bool validateNow = false}) => AppTextField(
    label: label,
    controller: _amount,
    hintText: '₦0.00',
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [ThousandsAmountFormatter()],
    autovalidateMode: validateNow
        ? AutovalidateMode.always
        : AutovalidateMode.onUserInteraction,
    validator: (value) {
      final amount = value ?? '';
      if (savingsPlanNaira(amount) == null) {
        return 'Enter a valid amount.';
      }
      final quote = _quote;
      if (widget.type == SavingsProductType.fixed && quote != null) {
        final max = quote.maxAmount;
        if (max != null && quote.exceedsMax(amount)) {
          return 'The most you can lock for this term is ${_naira(max)}.';
        }
        if (!quote.acceptsDeposit(amount)) {
          return 'The least you can lock for this term is '
              '${_naira(quote.minAmount)}.';
        }
      }
      if (widget.type == SavingsProductType.smartSave) {
        return _targetError(amount, quote);
      }
      if (widget.type == SavingsProductType.padi &&
          !periodicSavingsAmountValid(amount)) {
        return 'Each contribution must be at least ₦$minimumPeriodicSavingsNaira.';
      }
      return null;
    },
    onChanged: (value) => _update(_draft.copyWith(amount: value)),
  );

  List<Widget> _stepBody(ThemeData theme) {
    switch (_step) {
      case _WizardStep.goal:
        return [
          _heading(theme, 'What are you saving for?'),
          AppTextField(
            label: 'Goal name',
            controller: _name,
            hintText: 'e.g. New home 🏡',
            onChanged: (value) => _update(_draft.copyWith(name: value)),
          ),
          const SizedBox(height: BocSpace.md),
          _amountField('Target amount'),
          if (_product?.lowestMinAmount case final lowest?) ...[
            const SizedBox(height: BocSpace.md),
            SavingsCallout(
              icon: IconsaxPlusLinear.wallet_2,
              title: 'Opening deposit starts at ${_naira(lowest)}',
              body:
                  'When you create this goal, we move its opening deposit '
                  'from Boc Flex Savings. Your target must be greater than '
                  'the opening deposit; the exact deposit depends on '
                  'duration.',
            ),
          ],
        ];
      case _WizardStep.amount:
        final quote = _quote;
        final max = quote?.maxAmount;
        return [
          _heading(
            theme,
            'How much do you want to lock?',
            'Your money earns a fixed rate until the end of the term. We '
                'move this amount from Boc Flex Savings when you create the '
                'deposit.',
          ),
          _amountField('Amount'),
          if (quote != null) ...[
            const SizedBox(height: BocSpace.xs),
            Text(
              max == null
                  ? 'At least ${_naira(quote.minAmount)} for this term.'
                  : 'Between ${_naira(quote.minAmount)} and ${_naira(max)} '
                        'for this term.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ];
      case _WizardStep.schedule:
        final product = _product;
        final presets = product?.presetMonths ?? const <int>[];
        final longest = product?.longestTenorDays;
        final latest = longest == 365 ? '1 year' : '$longest days';
        return [
          _heading(
            theme,
            widget.type == SavingsProductType.fixed
                ? 'Choose a term'
                : 'How long will you save?',
          ),
          if (presets.isNotEmpty) ...[
            BocChoiceChips<int>(
              options: [
                for (final months in presets)
                  (value: months, label: '$months months'),
              ],
              selected: {?_draft.durationMonths},
              onChanged: (value) => _update(
                _draft.copyWith(
                  durationMonths: value.first,
                  clearCustomMaturityDate: true,
                ),
              ),
            ),
            const SizedBox(height: BocSpace.md),
          ],
          InkWell(
            borderRadius: BorderRadius.circular(BocRadius.sm),
            onTap: _pickMaturityDate,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Custom maturity date',
                suffixIcon: Icon(IconsaxPlusLinear.calendar),
              ),
              child: Text(
                _draft.customMaturityDate == null
                    ? 'Choose a date'
                    : DateFormat(
                        'd MMM yyyy',
                      ).format(_draft.customMaturityDate!),
              ),
            ),
          ),
          const SizedBox(height: BocSpace.xs),
          if (product != null)
            Text(
              'Earliest date: ${product.shortestTenorDays} days from today. '
              'Latest date: $latest from today.',
              style: theme.textTheme.bodySmall,
            ),
          ..._quoteSection(theme),
          if (widget.type == SavingsProductType.smartSave) ...[
            const SizedBox(height: BocSpace.md),
            _amountField('Target amount', validateNow: true),
            const SizedBox(height: BocSpace.md),
            SettingsGroup(
              padding: EdgeInsets.zero,
              children: [
                SettingsTile.toggle(
                  icon: IconsaxPlusLinear.repeat,
                  title: 'Auto-save',
                  subtitle: 'Save automatically on a schedule',
                  value: _draft.autoSave,
                  onChanged: (value) =>
                      _update(_draft.copyWith(autoSave: value)),
                ),
              ],
            ),
          ],
          const SizedBox(height: BocSpace.md),
          Text(
            widget.type == SavingsProductType.fixed
                ? 'Withdrawing before the end of the term pays your deposit '
                      'and the interest earned so far, minus an early '
                      'withdrawal fee.'
                : 'Withdrawing before your target date pays your savings '
                      'and the interest earned so far, minus an early '
                      'withdrawal fee.',
            style: theme.textTheme.bodySmall,
          ),
        ];
      case _WizardStep.days:
        final frequency = _draft.frequency;
        return [
          _heading(
            theme,
            widget.type == SavingsProductType.padi
                ? 'When do members contribute?'
                : 'How often should we save?',
          ),
          BocChoiceChips<SavingsFrequency>(
            options: [
              for (final value in SavingsFrequency.values)
                (value: value, label: value.label),
            ],
            selected: {?frequency},
            onChanged: (value) => _update(
              _draft.copyWith(frequency: value.first, contributionDays: {}),
            ),
          ),
          if (_createsInCore) ...[
            const SizedBox(height: BocSpace.md),
            AppTextField(
              label: 'Amount each time',
              controller: _recurring,
              hintText: '₦0.00',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [ThousandsAmountFormatter()],
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: (value) {
                final amount = value ?? '';
                if (savingsPlanNaira(amount) == null) {
                  return 'Enter a valid amount.';
                }
                if (!periodicSavingsAmountValid(amount)) {
                  return 'Each scheduled save must be at least '
                      '₦$minimumPeriodicSavingsNaira.';
                }
                return null;
              },
              onChanged: (value) =>
                  _update(_draft.copyWith(recurringAmount: value)),
            ),
          ],
          // Core has no contribution days; only Padi picks them.
          if (!_createsInCore && frequency == SavingsFrequency.weekly) ...[
            _label(theme, 'Day of the week'),
            BocChoiceChips<int>(
              multiSelect: widget.type == SavingsProductType.padi,
              options: const [
                (value: 1, label: 'Mon'),
                (value: 2, label: 'Tue'),
                (value: 3, label: 'Wed'),
                (value: 4, label: 'Thu'),
                (value: 5, label: 'Fri'),
                (value: 6, label: 'Sat'),
                (value: 7, label: 'Sun'),
              ],
              selected: _draft.contributionDays,
              onChanged: (value) =>
                  _update(_draft.copyWith(contributionDays: value)),
            ),
          ],
          if (!_createsInCore && frequency == SavingsFrequency.monthly) ...[
            _label(theme, 'Day of the month'),
            BocChoiceChips<int>(
              options: const [
                (value: 1, label: '1st'),
                (value: 15, label: '15th'),
                (value: 28, label: '28th'),
              ],
              selected: _draft.contributionDays,
              onChanged: (value) =>
                  _update(_draft.copyWith(contributionDays: value)),
            ),
          ],
        ];
      case _WizardStep.padiGroup:
        final members = _draft.memberCount ?? 2;
        return [
          _heading(theme, 'Set up your Padi group'),
          AppTextField(
            label: 'Group name',
            controller: _name,
            hintText: 'e.g. Office rent circle',
            onChanged: (value) => _update(_draft.copyWith(name: value)),
          ),
          _label(theme, 'Number of members'),
          Row(
            children: [
              IconButton.outlined(
                tooltip: 'Fewer members',
                onPressed: members > 2
                    ? () => _update(_draft.copyWith(memberCount: members - 1))
                    : null,
                icon: const Icon(IconsaxPlusLinear.minus),
              ),
              Expanded(
                child: Text(
                  '$members',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.figures,
                ),
              ),
              IconButton.outlined(
                tooltip: 'More members',
                onPressed: members < 20
                    ? () => _update(_draft.copyWith(memberCount: members + 1))
                    : null,
                icon: const Icon(IconsaxPlusLinear.add),
              ),
            ],
          ),
          const SizedBox(height: BocSpace.md),
          _amountField('Contribution per member'),
        ];
      case _WizardStep.start:
        final start = _draft.startDate;
        return [
          _heading(
            theme,
            'When does the first round start?',
            'Each round, every member contributes and one member, in turn '
                'order, receives the full pot. The cycle closes once everyone '
                'has been paid.',
          ),
          InkWell(
            borderRadius: BorderRadius.circular(BocRadius.sm),
            onTap: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                firstDate: now,
                lastDate: DateTime(now.year + 1, now.month, now.day),
                initialDate: start ?? now,
              );
              if (picked != null) _update(_draft.copyWith(startDate: picked));
            },
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Start date',
                suffixIcon: Icon(IconsaxPlusLinear.calendar),
              ),
              child: Text(
                start == null
                    ? 'Choose a date'
                    : DateFormat('d MMM yyyy').format(start),
              ),
            ),
          ),
        ];
      case _WizardStep.confirm:
        final fixed = widget.type == SavingsProductType.fixed;
        final frequency = _draft.autoSave ? _draft.frequency : null;
        if (widget.type == SavingsProductType.smartSave || fixed) {
          final months = _draft.durationMonths;
          final customDate = _draft.customMaturityDate;
          final quote = _quote;
          final recurring = formatApiAmount(
            savingsPlanNaira(_draft.recurringAmount),
            currency: 'NGN',
          );
          return [
            _heading(
              theme,
              fixed ? 'Review your deposit' : 'Review your goal',
              'Check the details before you create it.',
            ),
            if (fixed) ...[
              AppTextField(
                label: 'Deposit name (optional)',
                controller: _name,
                hintText: 'e.g. School fees 🎓',
                onChanged: (value) => _update(_draft.copyWith(name: value)),
              ),
              const SizedBox(height: BocSpace.md),
            ] else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(BocSpace.lg),
                decoration: BoxDecoration(
                  color: context.bocColors.smartSaveContainer,
                  borderRadius: BorderRadius.circular(BocRadius.lg),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_draft.name.trim().isNotEmpty) ...[
                      Text(
                        _draft.name.trim(),
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: BocSpace.xxs),
                    ],
                    Text(
                      'Target',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: context.bocColors.textSecondary,
                      ),
                    ),
                    Text(
                      formatApiAmount(
                            savingsPlanNaira(_draft.amount),
                            currency: 'NGN',
                          ) ??
                          '₦${_draft.amount}',
                      style: theme.textTheme.headlineMedium?.figures,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: BocSpace.md),
            ],
            SavingsFactGroup(
              title: fixed ? 'Deposit details' : 'Saving plan',
              rows: [
                if (fixed && _openingNaira != null)
                  (label: 'Deposit', value: _openingAmount),
                if (customDate == null && months != null)
                  (label: 'Duration', value: '$months months'),
                if (customDate != null && quote != null)
                  (label: 'Duration', value: '${quote.tenorDays} days'),
                if (quote != null) ..._quoteRows(quote, withLimits: false),
                if (!fixed)
                  (
                    label: 'Auto-save',
                    value: frequency != null && recurring != null
                        ? '$recurring ${frequency.label.toLowerCase()}'
                        : 'Manual deposits',
                  ),
              ],
            ),
            if (_createsInCore) ...[
              const SizedBox(height: BocSpace.md),
              SavingsCallout(
                icon: IconsaxPlusLinear.wallet_2,
                title: '$_openingAmount from Boc Flex Savings',
                body: fixed
                    ? 'Creating this deposit moves this amount from Boc Flex '
                          'Savings into your new plan.'
                    : 'Creating this goal moves the minimum opening balance '
                          'for this duration from Boc Flex Savings into your '
                          'new plan.',
              ),
            ],
          ];
        }
        return [
          _heading(
            theme,
            'Confirm your ${widget.type.displayName}',
            'Double-check the details before you create it.',
          ),
          if (fixed) ...[
            AppTextField(
              label: 'Deposit name (optional)',
              controller: _name,
              hintText: 'e.g. School fees 🎓',
              onChanged: (value) => _update(_draft.copyWith(name: value)),
            ),
            const SizedBox(height: BocSpace.md),
          ],
          BocSummaryGrid(
            items: [
              if (!fixed && _draft.name.trim().isNotEmpty)
                (label: 'Name', value: _draft.name.trim()),
              if (!fixed)
                (
                  label: widget.type == SavingsProductType.padi
                      ? 'Contribution'
                      : 'Target amount',
                  value: '₦${_draft.amount}',
                ),
              if (_draft.durationMonths != null)
                (label: 'Duration', value: '${_draft.durationMonths} months'),
              if (frequency != null)
                (label: 'Frequency', value: frequency.label),
              if (frequency != null && _createsInCore)
                (
                  label: 'Amount each time',
                  value: '₦${_draft.recurringAmount}',
                ),
              if (_draft.memberCount != null)
                (label: 'Members', value: '${_draft.memberCount}'),
              if (_draft.startDate != null)
                (
                  label: 'Starts',
                  value: DateFormat('d MMM yyyy').format(_draft.startDate!),
                ),
            ],
          ),
          if (_createsInCore) ...[
            const SizedBox(height: BocSpace.md),
            Text(
              'Funded from Boc Flex Savings',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: BocSpace.xxs),
            Text(
              "We'll move the minimum for this term from Boc Flex Savings now.",
              style: theme.textTheme.bodySmall,
            ),
          ],
        ];
    }
  }
}
