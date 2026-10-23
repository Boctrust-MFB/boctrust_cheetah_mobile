import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../service/transaction_authorizer.dart';

/// The amount and label/value rows of a [TransactionSummary], shown inside
/// the confirmation sheets. The sheet around it owns the title, subtitle,
/// input, errors and actions.
class TransactionSummaryDetails extends StatelessWidget {
  const TransactionSummaryDetails({required this.summary, super.key});

  final TransactionSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          summary.amountDisplay,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        for (final (label, value) in summary.lines)
          Padding(
            padding: const EdgeInsets.only(top: BocSpace.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodyMedium),
                const SizedBox(width: BocSpace.md),
                Expanded(
                  child: Text(
                    value,
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
