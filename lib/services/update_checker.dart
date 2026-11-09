// Dart port of mpv-emo src/update/UpdateChecker.{h,cpp} (PORT-MAP §1, A 类
// 纯逻辑直译 + 网络语义保留). The pure functions (tagToVersion /
// compareVersions / isNewer) and their 考证 comments are translated
// line-for-line; the Qt network layer (QNetworkAccessManager) maps onto
// package:http with the same observable semantics:
//   - One GET per check() call; main.dart schedules exactly one per launch
//     (mpv-emo src/main.cpp:315-321), gated on the settings-center
//     autoUpdate toggle.
//   - The result is only ever *reported*. This class never downloads or
//     installs anything; opening the release page is user-initiated
//     (update settings page -> url_launcher, the 1.x UpdateBadge role).
//   - Every failure mode (offline, HTTP error, malformed JSON, missing
//     fields, transfer timeout) is silent: nothing but the checkFinished
//     callback fires, so a network-less launch looks exactly like an
//     up-to-date one.
//
// Endpoint note: the 1.x source queried repos/emoeem/mpv-emo/releases/latest;
// the 2.0 wiring targets this repository (docs/SPEC.md §1 identity) at
// repos/emoeem/emoplay/releases/latest. Everything else — version grammar,
// comparison ranks, silent failure, in-flight dedup — is unchanged.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:emoplay/utils/constants.dart';

// Endpoint of the GitHub releases API (public repo, unauthenticated) and the
// release page base used as a fallback when the response carries no
// "html_url". GitHub's REST API rejects requests without a User-Agent
// header; check() always sets one.
const String kUpdateApiBase = 'https://api.github.com';
const String _kLatestReleasePath = '/repos/emoeem/emoplay/releases/latest';
const String _kReleasePageBase = 'https://github.com/emoeem/emoplay/releases';

class _VersionParts {
  _VersionParts(this.numbers, this.suffix);

  final List<int> numbers;
  final String suffix; // text after the first '-'; empty means a release
}

// Split "major.minor.patch[-identifier]" into numeric components and the
// pre-release suffix. Qt::SkipEmptyParts semantics: empty chunks ("1..0")
// are skipped. Non-numeric chunks (C++ QString::toInt ok=false) normalize
// to 0, e.g. "1.0.x" compares as 1.0.0.
_VersionParts _splitVersion(String version) {
  final numbers = <int>[];
  var suffix = '';
  final dash = version.indexOf('-');
  final core = (dash < 0) ? version : version.substring(0, dash);
  suffix = (dash < 0) ? '' : version.substring(dash + 1);
  for (final chunk in core.split('.')) {
    if (chunk.isEmpty) continue; // Qt::SkipEmptyParts
    final number = int.tryParse(chunk);
    numbers.add(number ?? 0);
  }
  return _VersionParts(numbers, suffix);
}

// Rank of a pre-release identifier: alpha < beta < rc ("pre" counts as rc).
// Unrecognized identifiers rank after rc. Ranks only order pre-releases
// among themselves — a release outranks every pre-release, which
// compareVersions() handles before this is consulted.
int _preReleaseRank(String identifier) {
  if (identifier == 'alpha') return 0;
  if (identifier == 'beta') return 1;
  if (identifier == 'rc' || identifier == 'pre') return 2;
  return 3;
}

// Compares two pre-release identifiers such as "beta", "rc.2" or "dev".
// The letter part (before the first '.') ranks via _preReleaseRank(); equal
// known ranks then compare the numeric tail ("rc.2" > "rc.1", a missing
// tail counts as 0). Unrecognized identifiers with different letters fall
// back to lexicographic order — not a value judgement, only determinism.
int _compareIdentifiers(String a, String b) {
  final dotA = a.indexOf('.');
  final dotB = b.indexOf('.');
  final lettersA = (dotA < 0) ? a : a.substring(0, dotA);
  final lettersB = (dotB < 0) ? b : b.substring(0, dotB);
  final tailA = (dotA < 0) ? '' : a.substring(dotA + 1);
  final tailB = (dotB < 0) ? '' : b.substring(dotB + 1);

  final rankA = _preReleaseRank(lettersA);
  final rankB = _preReleaseRank(lettersB);
  if (rankA != rankB) return rankA < rankB ? -1 : 1;
  if (rankA == 3 && lettersA != lettersB) {
    return lettersA.compareTo(lettersB) < 0 ? -1 : 1;
  }

  // C++ QString::toInt(&ok) yields 0 with ok=false on non-numeric tails;
  // int.tryParse(null) maps onto the same pair of values.
  final numberA = int.tryParse(tailA);
  final numberB = int.tryParse(tailB);
  final okA = numberA != null;
  final okB = numberB != null;
  if ((numberA ?? 0) != (numberB ?? 0)) {
    return (numberA ?? 0) < (numberB ?? 0) ? -1 : 1;
  }
  if (!okA && !okB && tailA != tailB) {
    return tailA.compareTo(tailB) < 0 ? -1 : 1;
  }
  return 0;
}

/// P9 update check: queries the GitHub releases API for the latest release of
/// emoeem/emoplay and reports it when the published tag is newer than the
/// running build (`appVersion`, passed in by main.dart / [instance]).
/// Scope is deliberately minimal:
///   - One GET per [check] call; main.dart schedules exactly one per launch.
///   - The result is only ever *reported*. This class never downloads or
///     installs anything; opening the release page is user-initiated UI.
///   - Every failure mode (offline, HTTP error, malformed JSON, missing
///     fields) is silent: nothing but the checkFinished callback fires, so a
///     network-less launch looks exactly like an up-to-date one.
///
/// The three state fields ([hasUpdate], [latestVersion], [releaseUrl]) flip
/// together when a newer release has been confirmed; they stay at their
/// defaults (no update) until then — including on every failure path.
/// ChangeNotifier mirrors the 1.x hasUpdateChanged/latestVersionChanged/
/// releaseUrlChanged signal bundle; [onUpdateAvailable] / [onCheckFinished]
/// mirror the updateAvailable/checkFinished signals for headless tests.
class UpdateChecker extends ChangeNotifier {
  /// The app-wide checker used by the startup wiring and the update settings
  /// page (1.x: one instance exposed to QML as the `updateChecker` context
  /// property). Carries the app version so callers need no arguments.
  static final UpdateChecker instance = UpdateChecker(appVersion);

  UpdateChecker(this.currentVersion, {String? apiBase, http.Client? client})
      : _apiBase = apiBase ?? kUpdateApiBase,
        _client = client;

  final String currentVersion;

  String _apiBase;
  set apiBase(String value) => _apiBase = value;

  final http.Client? _client;
  http.Client? _ownClient;
  bool _inFlight = false;

  bool _hasUpdate = false;
  bool get hasUpdate => _hasUpdate;

  String _latestVersion = '';
  String get latestVersion => _latestVersion;

  String _releaseUrl = '';
  String get releaseUrl => _releaseUrl;

  // 1.x signals. [onUpdateAvailable] carries the parsed version (tag without
  // any leading 'v') and the release page URL from the API response
  // ("html_url", falling back to the deterministic /releases/tag/<tag> page
  // when absent). [onCheckFinished] fires once per completed check(), on
  // success and failure alike; lets headless tests await the silent paths
  // instead of sleeping.
  void Function(String version, String releaseUrl)? onUpdateAvailable;
  void Function()? onCheckFinished;

  // Bounded transfer so an unreachable endpoint cannot hang the check
  // forever; the timeout lands on the same silent failure path (1.x
  // QNetworkRequest::setTransferTimeout(15000)).
  static const Duration _transferTimeout = Duration(seconds: 15);

  // --- pure logic, unit-tested headlessly without any network ----------

  // "v0.2.0-beta" -> "0.2.0-beta": trims whitespace and strips one leading
  // 'v'/'V' when a digit follows (so a tag like "verbose-1" survives).
  // Unknown shapes pass through trimmed; empty stays empty.
  static String tagToVersion(String tag) {
    var version = tag.trim();
    // Strip a git-convention "v"/"V" prefix only when a digit follows, so
    // tags like "verbose-1" pass through untouched.
    if (version.length >= 2 &&
        (version.startsWith('v') || version.startsWith('V')) &&
        _isAsciiDigit(version.codeUnitAt(1))) {
      version = version.substring(1);
    }
    return version;
  }

  // QChar::isDigit checks the Unicode Nd category; the version grammar only
  // ever feeds ASCII 0-9 here (non-digits normalize to 0 downstream), so the
  // ASCII range check is the faithful subset.
  static bool _isAsciiDigit(int codeUnit) =>
      codeUnit >= 0x30 && codeUnit <= 0x39;

  // Dotted-numeric comparison with pre-release handling. Documented
  // simplification (details in the 1.x source, carried over): numeric
  // components compare left to right (missing = 0, so "1.0" == "1.0.0"), a
  // release outranks its own pre-releases, and pre-release identifiers rank
  // alpha < beta < rc (rc.2 > rc.1) < anything unrecognized.
  static int compareVersions(String a, String b) {
    final pa = _splitVersion(tagToVersion(a));
    final pb = _splitVersion(tagToVersion(b));

    // Numeric components left to right; a missing component counts as 0
    // ("1.0" == "1.0.0"). Non-numeric components already normalized to 0.
    final count = pa.numbers.length > pb.numbers.length
        ? pa.numbers.length
        : pb.numbers.length;
    for (var i = 0; i < count; ++i) {
      final x = (i < pa.numbers.length) ? pa.numbers[i] : 0;
      final y = (i < pb.numbers.length) ? pb.numbers[i] : 0;
      if (x != y) return x < y ? -1 : 1;
    }

    // Numerically equal: a release outranks its own pre-releases
    // ("0.2.0" > "0.2.0-beta", "0.2.0-rc.1" < "0.2.0").
    if (pa.suffix.isEmpty || pb.suffix.isEmpty) {
      return pa.suffix.isEmpty ? (pb.suffix.isEmpty ? 0 : 1) : -1;
    }

    // Both are pre-releases of the same numbers.
    final identifierOrder = _compareIdentifiers(pa.suffix, pb.suffix);
    if (identifierOrder != 0) return identifierOrder;

    // Fully tied (e.g. two unrecognized identifiers): lexicographic so the
    // result is at least deterministic. Dart String.compareTo is UTF-16
    // code-unit order, matching the C++ QString operator<.
    if (pa.suffix == pb.suffix) return 0;
    return pa.suffix.compareTo(pb.suffix) < 0 ? -1 : 1;
  }

  // True when candidate is strictly newer than the running version.
  static bool isNewer(String current, String candidate) =>
      compareVersions(candidate, current) > 0;

  // Assembled URL of the GitHub "latest release" endpoint. The base is
  // injectable so tests can point check() at a local loopback server and
  // never touch the real API.
  Uri releasesUrl() {
    var base = _apiBase;
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return Uri.parse('$base$_kLatestReleasePath');
  }

  // Starts one GET of releasesUrl(). Ignored while a check is in flight.
  // A newer tag fires [onUpdateAvailable] and flips the state fields above;
  // every failure fires nothing but [onCheckFinished].
  void check() {
    // One in-flight check at a time; a second check() during a request is a
    // no-op (main.dart only schedules one per launch anyway).
    if (_inFlight) return;
    _inFlight = true;

    final request = http.Request('GET', releasesUrl())
      // 1.x RedirectPolicyAttribute: NoLessSafeRedirectPolicy — http follows
      // safe redirects automatically.
      ..followRedirects = true
      // GitHub's REST API requires a User-Agent; identify the app and
      // version (documented requirement, not decoration).
      ..headers['User-Agent'] = 'EmoPlay/$currentVersion (+$_kReleasePageBase)'
      ..headers['Accept'] = 'application/vnd.github+json';

    unawaited(_runCheck(request));
  }

  Future<void> _runCheck(http.Request request) async {
    http.StreamedResponse? reply;
    try {
      reply = await (_client ?? _resolveClient())
          .send(request)
          .timeout(_transferTimeout);
      final body =
          await reply.stream.bytesToString().timeout(_transferTimeout);
      _finishCheck(reply: reply, body: body);
    } catch (_) {
      // Silent failure: transport errors (offline, DNS, reset) and the
      // transfer timeout land here — checkFinished only.
      _finishCheck();
    }
  }

  http.Client _resolveClient() => _ownClient ??= http.Client();

  // 1.x UpdateChecker::finishCheck — the body after the reply completes is
  // fully synchronous, so the callbacks and state flips below happen in the
  // same order as the C++ signal emissions.
  void _finishCheck({http.StreamedResponse? reply, String body = ''}) {
    _inFlight = false;
    onCheckFinished?.call();

    // Silent failure: transport/HTTP errors (offline, 404, rate limit,
    // transfer timeout) keep every property at its default.
    if (reply == null) return;
    if (reply.statusCode < 200 || reply.statusCode >= 300) return;

    final Object? document;
    try {
      document = jsonDecode(body);
    } catch (_) {
      return; // 1.x: !QJsonDocument parse — malformed body is silent
    }
    if (document is! Map<String, dynamic>) return; // 1.x: !document.isObject()

    final tag = document['tag_name'];
    if (tag is! String || tag.isEmpty) return;

    final version = tagToVersion(tag);
    if (!isNewer(currentVersion, version)) return;

    // Never auto-download: the only thing surfaced is the release page URL,
    // which the settings page opens when (and only when) the user clicks it.
    final htmlUrl = document['html_url'];
    final parsedUrl = (htmlUrl is String && htmlUrl.isNotEmpty)
        ? Uri.tryParse(htmlUrl)
        : null;
    final releaseUrl =
        parsedUrl ?? Uri.parse('$_kReleasePageBase/tag/$tag');

    _setFound(version, releaseUrl.toString());
    onUpdateAvailable?.call(version, releaseUrl.toString());
  }

  void _setFound(String version, String url) {
    if (_hasUpdate && _latestVersion == version && _releaseUrl == url) return;
    _hasUpdate = true;
    _latestVersion = version;
    _releaseUrl = url;
    notifyListeners();
  }

  @override
  void dispose() {
    _ownClient?.close();
    super.dispose();
  }
}
