enum UpdatePlatform { android, ios }

class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.middle, this.minor);

  final int major;
  final int middle;
  final int minor;

  static final RegExp _pattern = RegExp(r'^\d+\.\d+\.\d+$');

  static AppVersion? tryParse(String value) {
    final text = value.trim();
    if (!_pattern.hasMatch(text)) return null;
    final parts = text.split('.').map(int.tryParse).toList();
    if (parts.any((p) => p == null)) return null;
    return AppVersion(parts[0]!, parts[1]!, parts[2]!);
  }

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (middle != other.middle) return middle.compareTo(other.middle);
    return minor.compareTo(other.minor);
  }

  bool operator <(AppVersion other) => compareTo(other) < 0;
  bool operator >=(AppVersion other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, middle, minor);

  @override
  String toString() => '$major.$middle.$minor';
}

class UpdatePolicy {
  const UpdatePolicy({
    required this.platform,
    required this.targetVersion,
    this.force = false,
    this.targetBuild,
    this.appStoreId,
    this.country,
  });

  final UpdatePlatform platform;
  final AppVersion targetVersion;
  final bool force;
  final int? targetBuild;
  final String? appStoreId;
  final String? country;

  /// Returns null when the platform entry is disabled, missing or invalid.
  static UpdatePolicy? fromJson(Object? json, UpdatePlatform platform) {
    if (json is! Map) return null;
    final entry = json[platform.name];
    if (entry is! Map) return null;
    if (entry['enabled'] != true) return null;

    final rawVersion = entry['targetVersion'];
    if (rawVersion is! String) return null;
    final version = AppVersion.tryParse(rawVersion);
    if (version == null) return null;

    final rawForce = entry['force'];
    if (rawForce != null && rawForce is! bool) return null;
    final force = rawForce == true;

    switch (platform) {
      case UpdatePlatform.android:
        final build = entry['targetBuild'];
        if (build is! int || build <= 0) return null;
        return UpdatePolicy(
          platform: platform,
          targetVersion: version,
          targetBuild: build,
          force: force,
        );
      case UpdatePlatform.ios:
        final id = entry['appStoreId'];
        final country = entry['country'];
        if (id is! String || !RegExp(r'^\d+$').hasMatch(id)) return null;
        if (country is! String || !RegExp(r'^[a-z]{2}$').hasMatch(country)) {
          return null;
        }
        return UpdatePolicy(
          platform: platform,
          targetVersion: version,
          appStoreId: id,
          country: country,
          force: force,
        );
    }
  }
}

class InstalledRelease {
  const InstalledRelease({
    required this.platform,
    required this.version,
    required this.build,
    required this.packageName,
  });

  final UpdatePlatform platform;
  final AppVersion version;
  final int build;
  final String packageName;
}

class StoreRelease {
  const StoreRelease({this.version, this.build, required this.storeUrl});

  final AppVersion? version;
  final int? build;
  final Uri storeUrl;
}

sealed class StoreCheck {
  const StoreCheck();
}

class StoreAvailable extends StoreCheck {
  const StoreAvailable(this.release);
  final StoreRelease release;
}

/// Conclusive: the store has no matching release.
class StoreNotAvailable extends StoreCheck {
  const StoreNotAvailable();
}

/// Inconclusive: error, timeout or unsupported install source.
class StoreUnknown extends StoreCheck {
  const StoreUnknown();
}

enum UpdateKind { none, optional, required }

class UpdateDecision {
  const UpdateDecision({required this.kind, this.target, this.storeUrl});

  const UpdateDecision.none()
    : kind = UpdateKind.none,
      target = null,
      storeUrl = null;

  final UpdateKind kind;
  final AppVersion? target;
  final Uri? storeUrl;
}

/// Whether [installed] already meets the policy target: Android compares
/// build numbers, iOS compares versions.
bool isUpToDate(UpdatePolicy policy, InstalledRelease installed) {
  return policy.platform == UpdatePlatform.android
      ? installed.build >= (policy.targetBuild ?? 0)
      : installed.version >= policy.targetVersion;
}

/// Whether an update to the policy target would be required: not up to date,
/// and either forced or a higher first or middle number than installed.
bool wouldRequire(UpdatePolicy policy, InstalledRelease installed) {
  if (isUpToDate(policy, installed)) return false;
  final target = policy.targetVersion;
  final current = installed.version;
  final majorBump =
      target.major > current.major ||
      (target.major == current.major && target.middle > current.middle);
  return policy.force || majorBump;
}

UpdateDecision evaluateUpdate({
  required UpdatePolicy policy,
  required InstalledRelease installed,
  required StoreCheck store,
}) {
  if (isUpToDate(policy, installed)) return const UpdateDecision.none();

  if (store is! StoreAvailable) return const UpdateDecision.none();
  final release = store.release;

  final storeBelowTarget = policy.platform == UpdatePlatform.android
      ? (release.build ?? 0) < (policy.targetBuild ?? 0)
      : release.version == null || release.version! < policy.targetVersion;
  if (storeBelowTarget) return const UpdateDecision.none();

  return UpdateDecision(
    kind: wouldRequire(policy, installed)
        ? UpdateKind.required
        : UpdateKind.optional,
    target: policy.targetVersion,
    storeUrl: release.storeUrl,
  );
}
