// Release preflight. Run locally before producing a store build:
//
//   dart run tool/release_preflight.dart [--env .env.prod] \
//       [--staging .env.stage] [--artifact build/.../app-release.aab] \
//       [--crashlytics-approved]
//
// Never prints values from the env files: only key names and pass/fail.
import 'dart:io';

const _allowedKeys = {
  'ENV',
  'BASE_URL',
  'CORE_BASE_URL',
  'SITE_URL',
  'SECURE_STORAGE_NAMESPACE',
  'DOJAH_SELFIE_WIDGET_ID',
  'DOJAH_GOVERNMENT_WIDGET_ID',
  'DOJAH_TRANSFER_WIDGET_ID',
  'DOJAH_USE_SANDBOX_BVN',
  'CRASHLYTICS_ENABLED',
};

const _dojahKeys = [
  'DOJAH_SELFIE_WIDGET_ID',
  'DOJAH_GOVERNMENT_WIDGET_ID',
  'DOJAH_TRANSFER_WIDGET_ID',
];

// Test identities compiled into the app. Public sandbox values.
const _testIdentities = {
  'Dojah sandbox BVN (dojahSandboxBvn)': '22222222222',
  'Smile ID sandbox BVN (smileIdSandboxBvn)': '00000000000',
};

final _failures = <String>[];
final _warnings = <String>[];

void _fail(String m) => _failures.add(m);
void _warn(String m) => _warnings.add(m);

Map<String, String> _parseEnv(String path) {
  final map = <String, String>{};
  for (final raw in File(path).readAsLinesSync()) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final i = line.indexOf('=');
    if (i <= 0) continue;
    var v = line.substring(i + 1).trim();
    if (v.length >= 2 &&
        ((v.startsWith('"') && v.endsWith('"')) ||
            (v.startsWith("'") && v.endsWith("'")))) {
      v = v.substring(1, v.length - 1);
    }
    map[line.substring(0, i).trim()] = v;
  }
  return map;
}

String? _host(String? url) {
  if (url == null || url.isEmpty) return null;
  final u = Uri.tryParse(url);
  return (u == null || u.host.isEmpty) ? null : u.host.toLowerCase();
}

void _checkUrl(
  Map<String, String> prod,
  String key,
  Set<String> stagingHosts, {
  required bool required,
}) {
  final v = prod[key] ?? '';
  if (v.isEmpty) {
    if (required) _fail('$key is missing');
    return;
  }
  final u = Uri.tryParse(v);
  if (u == null || u.scheme != 'https' || u.host.isEmpty) {
    _fail('$key is not an https URL');
    return;
  }
  if (stagingHosts.contains(u.host.toLowerCase())) {
    _fail('$key host matches a staging host');
  }
}

void _checkEnv(
  Map<String, String> prod,
  Map<String, String>? staging,
  bool crashlyticsApproved,
) {
  for (final k in prod.keys) {
    if (!_allowedKeys.contains(k)) _fail('Unknown key present: $k');
  }
  if (prod['ENV'] != 'prod') _fail('ENV is not "prod"');

  final stagingHosts = <String>{
    if (staging != null)
      for (final k in ['BASE_URL', 'CORE_BASE_URL'])
        if (_host(staging[k]) != null) _host(staging[k])!,
  };
  _checkUrl(prod, 'BASE_URL', stagingHosts, required: true);
  _checkUrl(prod, 'CORE_BASE_URL', stagingHosts, required: false);
  if ((prod['CORE_BASE_URL'] ?? '').isEmpty) {
    _warn(
      'CORE_BASE_URL is blank: Core capabilities are disabled in this build',
    );
  }
  _checkUrl(prod, 'SITE_URL', const {}, required: true);
  if (staging != null &&
      _host(prod['SITE_URL']) != null &&
      _host(prod['SITE_URL']) == _host(staging['SITE_URL'])) {
    _warn('SITE_URL host equals staging SITE_URL (the public site is shared)');
  }

  final ns = prod['SECURE_STORAGE_NAMESPACE'] ?? '';
  if (ns.isEmpty) {
    _fail('SECURE_STORAGE_NAMESPACE is missing');
  } else if (staging != null && ns == staging['SECURE_STORAGE_NAMESPACE']) {
    _fail('SECURE_STORAGE_NAMESPACE equals the staging value');
  }

  for (final k in _dojahKeys) {
    final v = prod[k] ?? '';
    if (v.isEmpty) {
      _fail('$k is missing');
    } else if (staging != null && v == (staging[k] ?? '')) {
      _fail('$k equals the staging value');
    }
  }

  if ((prod['DOJAH_USE_SANDBOX_BVN'] ?? '').toLowerCase() == 'true') {
    _fail('DOJAH_USE_SANDBOX_BVN is true');
  }

  final c = (prod['CRASHLYTICS_ENABLED'] ?? 'false').toLowerCase();
  final want = crashlyticsApproved ? 'true' : 'false';
  if (c != want) {
    _fail(
      'CRASHLYTICS_ENABLED disagrees with the runbook gate '
      '(expected $want${crashlyticsApproved ? '' : '; pass --crashlytics-approved only after the runbook gates pass'})',
    );
  }
}

Future<void> _checkArtifact(String path, Map<String, String>? staging) async {
  if (!File(path).existsSync()) {
    _fail('Artifact not found: $path');
    return;
  }
  final tmp = await Directory.systemTemp.createTemp('preflight_artifact_');
  try {
    final unzip = await Process.run('unzip', [
      '-q',
      '-o',
      path,
      '-d',
      tmp.path,
    ]);
    if (unzip.exitCode != 0) {
      _fail('Could not unzip artifact');
      return;
    }
    final aot = <File>[];
    for (final e in tmp.listSync(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final p = e.path;
      if (p.endsWith('/libapp.so') || p.endsWith('/App.framework/App')) {
        aot.add(e);
      }
    }
    if (aot.isEmpty) {
      _fail('No Dart AOT library (libapp.so / App.framework/App) in artifact');
      return;
    }

    final needles = <String, String>{};
    if (staging != null) {
      for (final k in ['BASE_URL', 'CORE_BASE_URL']) {
        final h = _host(staging[k]);
        if (h != null) needles['staging host from $k'] = h;
      }
      final ns = staging['SECURE_STORAGE_NAMESPACE'] ?? '';
      if (ns.isNotEmpty) needles['staging SECURE_STORAGE_NAMESPACE'] = ns;
    }

    for (final lib in aot) {
      final r = await Process.run('strings', [
        '-a',
        lib.path,
      ], stdoutEncoding: systemEncoding);
      final text = r.stdout as String;
      final rel = lib.path.substring(tmp.path.length + 1);
      stdout.writeln('  scanned $rel');
      needles.forEach((label, needle) {
        if (text.contains(needle)) _fail('Artifact contains $label ($rel)');
      });
      _testIdentities.forEach((label, id) {
        if (text.contains(id)) {
          _warn(
            'Artifact contains $label ($rel): likely the sandbox gate is not '
            'tree-shaken; the runtime flag is still forced off outside staging',
          );
        }
      });
    }
  } finally {
    await tmp.delete(recursive: true);
  }
}

Future<void> main(List<String> args) async {
  var envPath = '.env.prod';
  var stagingPath = '.env.stage';
  String? artifact;
  var crashlyticsApproved = false;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--env':
        envPath = args[++i];
      case '--staging':
        stagingPath = args[++i];
      case '--artifact':
        artifact = args[++i];
      case '--crashlytics-approved':
        crashlyticsApproved = true;
      default:
        stderr.writeln('Unknown argument: ${args[i]}');
        exit(64);
    }
  }

  if (!File(envPath).existsSync()) {
    stderr.writeln('Env file not found: $envPath');
    exit(64);
  }
  final prod = _parseEnv(envPath);
  Map<String, String>? staging;
  if (File(stagingPath).existsSync()) {
    staging = _parseEnv(stagingPath);
  } else {
    _fail('Staging env file not found: $stagingPath (cannot compare)');
  }

  stdout.writeln('Checking $envPath (keys only, values never printed)');
  _checkEnv(prod, staging, crashlyticsApproved);
  if (artifact != null) {
    stdout.writeln('Inspecting artifact $artifact');
    await _checkArtifact(artifact, staging);
  }

  for (final w in _warnings) {
    stdout.writeln('WARN  $w');
  }
  for (final f in _failures) {
    stdout.writeln('FAIL  $f');
  }
  if (_failures.isEmpty) {
    stdout.writeln('PASS  all release preflight checks');
  } else {
    stdout.writeln('${_failures.length} check(s) failed');
    exit(1);
  }
}
