import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'services.dart';
import 'theme.dart';

String formatAppVersion(
  String version,
  String buildNumber, {
  required bool isStaging,
}) => 'v$version ($buildNumber)${isStaging ? ' - Staging' : ''}';

/// Displays the version embedded in the installed app package.
class AppVersionLabel extends StatelessWidget {
  const AppVersionLabel({super.key, this.onSplash = false});

  final bool onSplash;

  static final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) => FutureBuilder<PackageInfo>(
    future: _packageInfo,
    builder: (context, snapshot) {
      final info = snapshot.data;
      if (info == null) return const SizedBox.shrink();
      return Text(
        formatAppVersion(
          info.version,
          info.buildNumber,
          isStaging: Env.isStaging,
        ),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontSize: 11,
          color: onSplash
              ? BocColors.navy.withValues(alpha: 0.5)
              : context.bocColors.textTertiary,
        ),
      );
    },
  );
}
