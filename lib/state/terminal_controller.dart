import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/catalogue.dart';
import '../core/console_engine.dart';
import '../core/palette.dart';

/// Where the terminal is in its lifecycle.
enum BootStage { booting, ready }

/// The single source of truth for the Starlight terminal session.
///
/// Owns the scrollback buffer, the input line, command history, the observing
/// site, notes persisted to disk, and the live sky model.
class TerminalController extends ChangeNotifier {
  TerminalController({this.tickInterval = const Duration(seconds: 1)});

  final Duration tickInterval;

  // ── Scrollback ──────────────────────────────────────────────────────────
  final List<TLine> _lines = <TLine>[];
  List<TLine> get lines => List.unmodifiable(_lines);

  // ── Input / history ─────────────────────────────────────────────────────
  String _input = '';
  String get input => _input;

  final List<String> _history = <String>[];
  List<String> get history => List.unmodifiable(_history);
  int _historyCursor = -1;

  // ── Boot ────────────────────────────────────────────────────────────────
  BootStage _stage = BootStage.booting;
  BootStage get stage => _stage;

  double _bootProgress = 0;
  double get bootProgress => _bootProgress;

  String _bootMessage = 'initialising';
  String get bootMessage => _bootMessage;

  // ── Observable sky state ────────────────────────────────────────────────
  DateTime _now = DateTime.now();
  DateTime get now => _now;

  double _latitude = 51.4779;
  double _longitude = -0.0015;
  String _siteName = 'Greenwich, UK';

  double get latitude => _latitude;
  double get longitude => _longitude;
  String get siteName => _siteName;

  bool _trackingLive = true;
  bool get trackingLive => _trackingLive;

  int _timeOffsetHours = 0;
  int get timeOffsetHours => _timeOffsetHours;

  /// Effective observation time (now, optionally shifted by [timeOffsetHours]).
  DateTime get observationTime => _now.add(Duration(hours: _timeOffsetHours));

  double get lstDegrees =>
      localSiderealDegrees(observationTime.toUtc(), _longitude);

  List<Star> _stars = const <Star>[];
  List<Star> get stars => _stars;

  String? _selectedStarId;
  Star? get selectedStar => _stars.cast<Star?>().firstWhere(
    (s) => s?.id == _selectedStarId,
    orElse: () => null,
  );

  Palette _palette = Palette.phosphor;
  Palette get palette => _palette;

  bool _crtEnabled = true;
  bool get crtEnabled => _crtEnabled;

  final bool _reduceMotion = false;
  bool get reduceMotion => _reduceMotion;

  bool _loggedIn = false;
  bool get loggedIn => _loggedIn;

  String _observer = 'guest';
  String get observer => _observer;

  /// Bridge to the studio (agents, keys, effects). Wired by [StudioController]
  /// after construction so the console can talk to them without a cycle.
  CommandBridge? bridge;

  // ── Notes ───────────────────────────────────────────────────────────────
  final List<SkyNote> _notes = <SkyNote>[];
  List<SkyNote> get notes => List.unmodifiable(_notes);

  // ── Internals ───────────────────────────────────────────────────────────
  Timer? _clockTimer;
  Timer? _bootTimer;
  SharedPreferences? _prefs;
  int _bootStep = 0;
  bool _disposed = false;

  static const String _prefsNotes = 'starlight.notes.v1';
  static const String _prefsPalette = 'starlight.palette.v1';
  static const String _prefsCrt = 'starlight.crt.v1';
  static const String _prefsSiteLat = 'starlight.site.lat.v1';
  static const String _prefsSiteLon = 'starlight.site.lon.v1';
  static const String _prefsSiteName = 'starlight.site.name.v1';
  static const String _prefsObserver = 'starlight.observer.v1';

  // ══════════════════════════════════════════════════════════════════════
  // Lifecycle
  // ══════════════════════════════════════════════════════════════════════

  Future<void> start() async {
    _lines.clear();
    _recomputeSky();
    await _loadPrefs();
    _emitBootHeader();
    _runBootSequence();
  }

  void _emitBootHeader() {
    _add(const TLine(''));
    _add(
      TLine(
        '  ST★RLIGHT TERMINAL  ${'v1.0.0'}',
        tone: Tone.heading,
        glow: true,
      ),
    );
    _add(TLine('  sky console for the patient observer', tone: Tone.dim));
    _add(const TLine(''));
  }

  void _runBootSequence() {
    const steps = <String>[
      'powering phosphor tube',
      'warming optics',
      'loading star catalogue',
      'solving sidereal clock',
      'aligning coordinate frames',
      'restoring observer notes',
      'opening terminal',
    ];

    _bootStep = 0;
    _bootMessage = steps.first;
    _bootTimer?.cancel();
    _bootTimer = Timer.periodic(const Duration(milliseconds: 210), (timer) {
      if (_disposed) return;
      _bootStep++;
      if (_bootStep >= steps.length) {
        timer.cancel();
        _bootProgress = 1;
        _bootMessage = 'ready';
        _stage = BootStage.ready;
        _recomputeSky();
        _emitWelcome();
        _startClock();
        _safeNotify();
        return;
      }
      _bootMessage = steps[_bootStep];
      _bootProgress = _bootStep / steps.length;
      _add(TLine('  [ ok ] $_bootMessage', tone: Tone.dim));
      _safeNotify();
    });
  }

  void _emitWelcome() {
    _add(const TLine(''));
    _add(
      TLine(
        '  Session open. ${_notes.length} note'
        '${_notes.length == 1 ? '' : 's'} loaded.',
        tone: Tone.ok,
      ),
    );
    _add(
      TLine(
        '  Type *help* for the command index, or *sky* to look up.',
        tone: Tone.plain,
      ),
    );
    _add(const TLine(''));
  }

  void _startClock() {
    _clockTimer?.cancel();
    _clockTimer = Timer.periodic(tickInterval, (_) {
      if (_disposed || !_trackingLive) return;
      if (_timeOffsetHours != 0) return;
      _now = DateTime.now();
      _recomputeSky();
      _safeNotify();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _clockTimer?.cancel();
    _bootTimer?.cancel();
    super.dispose();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  // ══════════════════════════════════════════════════════════════════════
  // Sky model
  // ══════════════════════════════════════════════════════════════════════

  void _recomputeSky() {
    final lst = localSiderealDegrees(observationTime.toUtc(), _longitude);
    _stars = kStarCatalogue.map((s) {
      final h = equatorialToHorizontal(
        raDegrees: s.rightAscensionDegrees,
        decDegrees: s.decDegrees,
        lstDegrees: lst,
        latitude: _latitude,
      );
      return s.copyWithAltAz(h.altitude, h.azimuth);
    }).toList();
  }

  double get moonPhaseValue => moonPhase(observationTime.toUtc());
  String get moonPhaseLabel => moonPhaseName(moonPhaseValue);
  String get moonGlyphValue => moonGlyph(moonPhaseValue);

  /// Stars currently above the horizon, brightest first.
  List<Star> get visibleStars {
    final vis = _stars.where((s) => s.altitude > 0).toList();
    vis.sort((a, b) => a.magnitude.compareTo(b.magnitude));
    return vis;
  }

  int get visibleCount => _stars.where((s) => s.altitude > 0).length;

  String get compassLabel =>
      compassPoint(_stars.isEmpty ? 0 : _stars.first.azimuth);

  Star? get brightestVisible =>
      visibleStars.isEmpty ? null : visibleStars.first;

  Star? get culminationNext {
    if (_stars.isEmpty) return null;
    final sorted = List<Star>.from(_stars)
      ..sort((a, b) => b.altitude.compareTo(a.altitude));
    return sorted.first;
  }

  // ══════════════════════════════════════════════════════════════════════
  // Input handling
  // ══════════════════════════════════════════════════════════════════════

  void setInput(String value) {
    if (value == _input) return;
    _input = value;
    _historyCursor = -1;
    _safeNotify();
  }

  void appendInput(String char) {
    _input += char;
    _historyCursor = -1;
    _safeNotify();
  }

  void backspace() {
    if (_input.isEmpty) return;
    _input = _input.substring(0, _input.length - 1);
    _safeNotify();
  }

  /// Cycle through command history. [direction] is -1 (older) or +1 (newer).
  void historyStep(int direction) {
    if (_history.isEmpty) return;
    if (_historyCursor == -1) {
      _historyCursor = direction < 0 ? _history.length - 1 : -1;
    } else {
      _historyCursor = (_historyCursor + direction).clamp(
        -1,
        _history.length - 1,
      );
    }
    _input = _historyCursor >= 0 ? _history[_historyCursor] : '';
    _safeNotify();
  }

  void submit() {
    final raw = _input.trim();
    _input = '';
    _historyCursor = -1;
    if (raw.isEmpty) {
      _add(const TLine(''));
      _safeNotify();
      return;
    }
    _history.add(raw);
    _add(TLine('\$ $raw', tone: Tone.prompt));
    _execute(raw);
    _recomputeSky();
    _safeNotify();
  }

  // ══════════════════════════════════════════════════════════════════════
  // Output helpers
  // ══════════════════════════════════════════════════════════════════════

  void _add(TLine line) {
    _lines.add(line);
    // Keep the buffer bounded so long sessions stay smooth.
    if (_lines.length > 600) {
      _lines.removeRange(0, _lines.length - 600);
    }
  }

  void print(String text, {Tone tone = Tone.plain, bool glow = false}) {
    _add(TLine(text, tone: tone, glow: glow));
    _safeNotify();
  }

  void clear() {
    _lines.clear();
    _safeNotify();
  }

  // ══════════════════════════════════════════════════════════════════════
  // Command dispatch
  // ══════════════════════════════════════════════════════════════════════

  void _execute(String raw) {
    final parts = raw.split(RegExp(r'\s+'));
    final cmd = parts.first.toLowerCase();
    final args = parts.skip(1).toList();

    switch (cmd) {
      case 'help':
      case '?':
        _cmdHelp();
      case 'sky':
        _cmdSky(args);
      case 'star':
        _cmdStar(args);
      case 'map':
      case 'chart':
        _cmdMap();
      case 'find':
        _cmdFind(args);
      case 'top':
      case 'brightest':
        _cmdTop();
      case 'moon':
        _cmdMoon();
      case 'time':
        _cmdTime(args);
      case 'site':
      case 'location':
        _cmdSite(args);
      case 'constellation':
      case 'con':
        _cmdConstellation(args);
      case 'note':
        _cmdNote(args);
      case 'notes':
        _cmdNotes();
      case 'del':
      case 'delete':
        _cmdDelete(args);
      case 'theme':
      case 'palette':
        _cmdTheme(args);
      case 'crt':
        _crtEnabled = !_crtEnabled;
        _persistCrt();
        print(
          '  scanline overlay ${_crtEnabled ? 'enabled' : 'disabled'}',
          tone: Tone.ok,
        );
      case 'whoami':
        _cmdWhoami();
      case 'login':
        _cmdLogin(args);
      case 'logout':
        _loggedIn = false;
        _observer = 'guest';
        _persistObserver();
        print('  session closed. observer cleared.', tone: Tone.warn);
      case 'status':
      case 'stat':
        _cmdStatus();
      case 'agent':
      case 'agents':
        _cmdAgents(args);
      case 'ask':
        _cmdAsk(args);
      case 'fleet':
        _cmdFleet(args);
      case 'keys':
        _cmdKeys(args);
      case 'key':
        _cmdKeys(args);
      case 'fx':
      case 'effect':
        _cmdEffect(args);
      case 'about':
        _cmdAbout();
      case 'clear':
      case 'cls':
        clear();
      case 'banner':
        _cmdBanner();
      case 'echo':
        print('  ${args.join(' ')}');
      case 'date':
        print('  ${fmtUtc(_now)}  ·  ${fmtClock(observationTime)} local');
      case 'exit':
      case 'quit':
        print('  detaching is not possible from here.', tone: Tone.dim);
        print('  you are already as far away as it gets.', tone: Tone.dim);
      default:
        print('  command not found: $cmd', tone: Tone.err);
        print(
          '  try *help* to list what this terminal understands.',
          tone: Tone.dim,
        );
    }
  }

  // ── Commands ────────────────────────────────────────────────────────────

  void _cmdHelp() {
    const rows = <List<String>>[
      ['help', 'this index'],
      ['sky', 'visible sky summary + brightest objects'],
      ['star <name>', 'full data sheet for one object'],
      ['find <text>', 'search the catalogue by name or constellation'],
      ['top', 'ten brightest objects above the horizon'],
      ['map', 'render the polar sky chart'],
      ['moon', 'lunar phase and illumination'],
      ['time [+N|-N]', 'shift observing time by N hours'],
      ['site <lat> <lon>', 'set observing coordinates'],
      ['whoami', 'observer identity'],
      ['login <name>', 'attach an observer name'],
      ['note <text>', 'save a note to this session'],
      ['notes', 'list saved notes'],
      ['del <n>', 'delete note number n'],
      ['theme <name>', 'phosphor / amber / ice / nebula'],
      ['crt', 'toggle the scanline overlay'],
      ['agent', 'the agent fleet and their state'],
      ['ask <agent> <task>', 'run one agent on a task'],
      ['fleet <task>', 'broadcast a task to every agent'],
      ['keys', 'provider key vault status'],
      ['keys set <id> <key>', 'store an API key'],
      ['fx [name]', 'switch the background effect'],
      ['status', 'full terminal state dump'],
      ['banner', 'redraw the boot banner'],
      ['clear', 'wipe the scrollback'],
      ['about', 'what this is'],
    ];

    print(ruleLine('COMMAND INDEX', 46), tone: Tone.heading);
    for (final r in rows) {
      print('  ${pad(r[0], 18)}${r[1]}', tone: Tone.plain);
    }
    print(ruleLine('', 46), tone: Tone.line);
    print('  Arguments in angle brackets are required.', tone: Tone.dim);
  }

  void _cmdSky(List<String> args) {
    final vis = visibleStars;
    print(ruleLine('SKY', 52), tone: Tone.heading);
    print(
      '  site      $_siteName  '
      '(${_latitude.toStringAsFixed(2)}°, ${_longitude.toStringAsFixed(2)}°)',
    );
    print(
      '  local     ${fmtClock(observationTime)}  '
      '· ${trackingLive && _timeOffsetHours == 0 ? 'live' : 'offset ${_timeOffsetHours >= 0 ? '+' : ''}$_timeOffsetHours h'}',
    );
    print('  lst       ${(lstDegrees / 15).toStringAsFixed(3)} h');
    print('  visible   ${vis.length} of ${_stars.length} catalogue objects');
    print(
      '  moon      $moonGlyphValue  $moonPhaseLabel '
      '(${(moonPhaseValue * 100).toStringAsFixed(0)}% cycle)',
    );
    print(ruleLine('', 52), tone: Tone.line);

    if (vis.isEmpty) {
      print('  No catalogue objects above the horizon.', tone: Tone.warn);
      return;
    }

    print(
      '  ${pad('OBJECT', 16)}${pad('CON', 6)}'
      '${padLeft('ALT', 7)}${padLeft('AZ', 6)}${padLeft('MAG', 6)}',
      tone: Tone.dim,
    );
    for (final s in vis.take(12)) {
      print(
        '  ${pad(clip(s.name, 15), 16)}'
        '${pad(s.constellation.split(' ').first, 6)}'
        '${padLeft('${s.altitude.toStringAsFixed(1)}°', 7)}'
        '${padLeft('${s.azimuth.toStringAsFixed(0)}°', 6)}'
        '${padLeft(fmtMag(s.magnitude), 6)}',
        tone: Tone.plain,
      );
    }
    if (vis.length > 12) {
      print(
        '  … ${vis.length - 12} more above horizon. try *top* or *find*',
        tone: Tone.dim,
      );
    }
  }

  void _cmdStar(List<String> args) {
    if (args.isEmpty) {
      print('  usage: star <name>', tone: Tone.warn);
      print('  example: star vega', tone: Tone.dim);
      return;
    }
    final q = args.join(' ').toLowerCase();
    final match =
        _stars.cast<Star?>().firstWhere(
          (s) => s!.name.toLowerCase() == q,
          orElse: () => null,
        ) ??
        _stars.cast<Star?>().firstWhere(
          (s) => s!.name.toLowerCase().startsWith(q),
          orElse: () => null,
        ) ??
        _stars.cast<Star?>().firstWhere(
          (s) =>
              s!.name.toLowerCase().contains(q) ||
              s.constellation.toLowerCase().contains(q),
          orElse: () => null,
        );

    if (match == null) {
      print('  no object matching "$q" in the catalogue.', tone: Tone.err);
      print(
        '  try *find ${args.join(' ')}* to search broadly.',
        tone: Tone.dim,
      );
      return;
    }

    _selectedStarId = match.id;
    _printStarSheet(match);
  }

  void _printStarSheet(Star s) {
    final above = s.altitude > 0;
    print(ruleLine(s.name.toUpperCase(), 54), tone: Tone.heading, glow: true);
    print('  ${pad('Bayer', 15)}${s.bayer}');
    print('  ${pad('Constellation', 15)}${s.constellation}');
    print(
      '  ${pad('RA / Dec', 15)}${fmtRa(s.raHours)}  ${fmtDec(s.decDegrees)}',
    );
    print(
      '  ${pad('Magnitude', 15)}${fmtMag(s.magnitude)}  '
      '${meter(1 - ((s.magnitude + 1.5) / 4.0), width: 10)}',
    );
    print('  ${pad('Spectral', 15)}${s.spectral}');
    print('  ${pad('Distance', 15)}${fmtDistance(s.distanceLy)}');
    print(ruleLine('', 54), tone: Tone.line);

    print(
      '  ${pad('Altitude', 15)}${s.altitude.toStringAsFixed(2)}°  '
      '${meter(s.altitude / 90.0, width: 14)}  '
      '${above ? 'above horizon' : 'below horizon'}',
      tone: above ? Tone.ok : Tone.dim,
    );
    print(
      '  ${pad('Azimuth', 15)}${s.azimuth.toStringAsFixed(1)}°  '
      '(${compassPoint(s.azimuth)})',
    );
    print('');
    print(_wrap(s.note, 66), tone: Tone.quote);
    print('');
    print(
      '  map marker plotted. type *map* to see it in context.',
      tone: Tone.dim,
    );
  }

  void _cmdMap() {
    print('  rendering sky chart — switch to the *MAP* tab.', tone: Tone.ok);
    print(
      '  projection: azimuthal, horizon at the rim, zenith at centre.',
      tone: Tone.dim,
    );
    if (_selectedStarId != null) {
      final sel = selectedStar;
      if (sel != null) {
        print(
          '  focus: ${sel.name} (${sel.altitude.toStringAsFixed(1)}°)',
          tone: Tone.bright,
        );
      }
    }
  }

  void _cmdFind(List<String> args) {
    if (args.isEmpty) {
      print('  usage: find <text>', tone: Tone.warn);
      return;
    }
    final q = args.join(' ').toLowerCase();
    final hits = _stars
        .where(
          (s) =>
              s.name.toLowerCase().contains(q) ||
              s.constellation.toLowerCase().contains(q) ||
              s.bayer.toLowerCase().contains(q),
        )
        .toList();
    if (hits.isEmpty) {
      print('  nothing matched "$q".', tone: Tone.err);
      return;
    }
    print(
      '  ${hits.length} match${hits.length == 1 ? '' : 'es'}:',
      tone: Tone.heading,
    );
    for (final s in hits.take(10)) {
      final vis = s.altitude > 0 ? '•' : '·';
      print(
        '  $vis ${pad(s.name, 16)}${pad(s.constellation.split(' ').first, 8)}'
        '${padLeft(fmtMag(s.magnitude), 7)}  '
        '${s.altitude.toStringAsFixed(0)}°',
        tone: s.altitude > 0 ? Tone.plain : Tone.dim,
      );
    }
    print('  (*•* = above horizon)', tone: Tone.dim);
  }

  void _cmdTop() {
    final vis = visibleStars;
    if (vis.isEmpty) {
      print('  the sky is empty of catalogue objects.', tone: Tone.warn);
      return;
    }
    print(ruleLine('BRIGHTEST ABOVE HORIZON', 44), tone: Tone.heading);
    var i = 1;
    for (final s in vis.take(10)) {
      print(
        '  ${padLeft('$i.', 4)}${pad(s.name, 15)}'
        '${padLeft(fmtMag(s.magnitude), 7)}  '
        '${padLeft('${s.altitude.toStringAsFixed(0)}°', 5)}  '
        '${compassPoint(s.azimuth)}',
      );
      i++;
    }
  }

  void _cmdMoon() {
    final phase = moonPhaseValue;
    final illum = (1 - math.cos(2 * math.pi * phase)) / 2;
    print(ruleLine('LUNA', 40), tone: Tone.heading, glow: true);
    print('  glyph     $moonGlyphValue');
    print('  phase     $moonPhaseLabel');
    print('  cycle     ${(phase * 100).toStringAsFixed(1)}%');
    print('  illum     ${(illum * 100).toStringAsFixed(1)}%');
    print('  ${meter(illum, width: 24)}');
    print('');
    print('  ${moonAdvice(illum)}', tone: Tone.quote);
  }

  String moonAdvice(double illumination) {
    if (illumination < 0.12) {
      return 'Dark sky. Deep-sky objects at their best tonight.';
    }
    if (illumination < 0.45) {
      return 'Partial moonlight. Good balance of lunar detail and deep sky.';
    }
    if (illumination < 0.85) {
      return 'Bright moon. Push magnification and chase craters instead.';
    }
    return 'Full moon. Planetary detail washes out — observe the terminator.';
  }

  void _cmdTime(List<String> args) {
    if (args.isEmpty) {
      print('  now       ${fmtUtc(_now)}');
      print(
        '  observing ${fmtUtc(observationTime)} '
        '(offset ${_timeOffsetHours >= 0 ? '+' : ''}$_timeOffsetHours h)',
      );
      print('  lst       ${(lstDegrees / 15).toStringAsFixed(3)} h');
      return;
    }
    final arg = args.first.toLowerCase();
    if (arg == 'reset' || arg == 'now' || arg == 'live') {
      _timeOffsetHours = 0;
      _trackingLive = true;
      _now = DateTime.now();
      _recomputeSky();
      print('  clock reset to live.', tone: Tone.ok);
      return;
    }
    final n = int.tryParse(arg);
    if (n == null) {
      print('  usage: time [+N|-N|reset]', tone: Tone.warn);
      return;
    }
    _timeOffsetHours = n.clamp(-24, 24);
    _trackingLive = false;
    _recomputeSky();
    print(
      '  observing time shifted ${_timeOffsetHours >= 0 ? '+' : ''}'
      '$_timeOffsetHours h → ${fmtClock(observationTime)}',
      tone: Tone.ok,
    );
  }

  void _cmdSite(List<String> args) {
    if (args.isEmpty) {
      print('  site   $_siteName');
      print('  lat    ${_latitude.toStringAsFixed(4)}');
      print('  lon    ${_longitude.toStringAsFixed(4)}');
      print('  usage: site <lat> <lon> [name…]', tone: Tone.dim);
      return;
    }
    final lat = double.tryParse(args[0]);
    final lon = args.length > 1 ? double.tryParse(args[1]) : null;
    if (lat == null || lon == null || lat.abs() > 90 || lon.abs() > 180) {
      print(
        '  invalid coordinates. lat ∈ [-90, 90], lon ∈ [-180, 180].',
        tone: Tone.err,
      );
      return;
    }
    _latitude = lat;
    _longitude = lon;
    _siteName = args.length > 2 ? args.sublist(2).join(' ') : 'custom site';
    _recomputeSky();
    _persistSite();
    print(
      '  site updated → $_siteName '
      '(${lat.toStringAsFixed(2)}°, ${lon.toStringAsFixed(2)}°)',
      tone: Tone.ok,
    );
  }

  void _cmdConstellation(List<String> args) {
    if (args.isEmpty) {
      print('  usage: constellation <name>', tone: Tone.warn);
      return;
    }
    final q = args.join(' ').toLowerCase();
    final hits = _stars
        .where((s) => s.constellation.toLowerCase().contains(q))
        .toList();
    if (hits.isEmpty) {
      print(
        '  constellation "$q" has no catalogued members here.',
        tone: Tone.err,
      );
      return;
    }
    print(
      ruleLine(hits.first.constellation.toUpperCase(), 46),
      tone: Tone.heading,
    );
    for (final s in hits) {
      final mark = s.altitude > 0 ? '•' : '·';
      print(
        '  $mark ${pad(s.name, 16)}${padLeft(fmtMag(s.magnitude), 7)}  '
        '${padLeft('${s.altitude.toStringAsFixed(0)}°', 5)}',
        tone: s.altitude > 0 ? Tone.plain : Tone.dim,
      );
    }
  }

  void _cmdNote(List<String> args) {
    if (args.isEmpty) {
      print('  usage: note <text>', tone: Tone.warn);
      return;
    }
    final text = args.join(' ');
    final note = SkyNote(
      text: text,
      createdAt: observationTime,
      starId: _selectedStarId,
    );
    _notes.add(note);
    _persistNotes();
    print('  note #${_notes.length} saved.', tone: Tone.ok);
    if (_selectedStarId != null) {
      final s = selectedStar;
      if (s != null) print('  tagged to ${s.name}.', tone: Tone.dim);
    }
  }

  void _cmdNotes() {
    if (_notes.isEmpty) {
      print(
        '  no notes yet. try *note seeing is excellent tonight*.',
        tone: Tone.dim,
      );
      return;
    }
    print(ruleLine('OBSERVING LOG', 50), tone: Tone.heading);
    for (var i = 0; i < _notes.length; i++) {
      final n = _notes[i];
      final tag = n.starId == null ? '' : ' ⇒ ${_starNameFor(n.starId!)}';
      print(
        '  ${padLeft('#${i + 1}', 4)} '
        '${pad(n.createdAt.toLocal().toString().substring(0, 16), 18)}$tag',
      );
      print('      ${_wrap(n.text, 58, indent: 6)}');
    }
    print(ruleLine('', 50), tone: Tone.line);
    print(
      '  ${_notes.length} entr${_notes.length == 1 ? 'y' : 'ies'} · '
      '*del <n>* to remove',
      tone: Tone.dim,
    );
  }

  void _cmdDelete(List<String> args) {
    if (args.isEmpty) {
      print('  usage: del <n>', tone: Tone.warn);
      return;
    }
    final n = int.tryParse(args.first);
    if (n == null || n < 1 || n > _notes.length) {
      print('  no note #${args.first}.', tone: Tone.err);
      return;
    }
    _notes.removeAt(n - 1);
    _persistNotes();
    print('  note #$n removed.', tone: Tone.ok);
  }

  void _cmdTheme(List<String> args) {
    if (args.isEmpty) {
      print('  available palettes:', tone: Tone.heading);
      for (final p in Palette.all) {
        final mark = p.id == _palette.id ? '●' : '○';
        print(
          '  $mark ${pad(p.label.toLowerCase(), 10)}${p.description}',
          tone: p.id == _palette.id ? Tone.bright : Tone.plain,
        );
      }
      return;
    }
    final name = args.first.toLowerCase();
    if (name == 'next') {
      _palette = _palette.next();
    } else {
      final chosen = Palette.all.cast<Palette?>().firstWhere(
        (p) => p!.label.toLowerCase() == name,
        orElse: () => null,
      );
      if (chosen == null) {
        print('  unknown palette "$name".', tone: Tone.err);
        return;
      }
      _palette = chosen;
    }
    _persistPalette();
    print('  palette → ${_palette.label}', tone: Tone.ok, glow: true);
  }

  void _cmdWhoami() {
    final hour = observationTime.hour;
    print('  observer   $_observer');
    print('  session    ${_loggedIn ? 'authenticated' : 'anonymous'}');
    print('  site       $_siteName');
    print('  sky phase  ${skyPhaseForHour(hour)}');
    print('  notes      ${_notes.length}');
    print('  palette    ${_palette.label}');
  }

  void _cmdLogin(List<String> args) {
    if (args.isEmpty) {
      print('  usage: login <name>', tone: Tone.warn);
      return;
    }
    _observer = args.first.toLowerCase();
    _loggedIn = true;
    _persistObserver();
    print('  welcome, $_observer.', tone: Tone.ok, glow: true);
    print('  your notes are tagged to this session.', tone: Tone.dim);
  }

  void _cmdStatus() {
    print(ruleLine('STATUS', 48), tone: Tone.heading);
    print('  ${pad('palette', 14)}${_palette.label}');
    print('  ${pad('scanlines', 14)}${_crtEnabled ? 'on' : 'off'}');
    print(
      '  ${pad('clock', 14)}'
      '${_trackingLive && _timeOffsetHours == 0 ? 'live' : 'offset'}',
    );
    print('  ${pad('site', 14)}$_siteName');
    print('  ${pad('catalogue', 14)}${_stars.length} objects');
    print('  ${pad('above horizon', 14)}$visibleCount');
    print('  ${pad('notes', 14)}${_notes.length}');
    print('  ${pad('history', 14)}${_history.length} commands');
    print('  ${pad('scrollback', 14)}${_lines.length} lines');
    print('  ${pad('observer', 14)}$_observer');
    print(ruleLine('', 48), tone: Tone.line);
  }

  void _cmdAbout() {
    print(ruleLine('ABOUT', 50), tone: Tone.heading, glow: true);
    print('  STARLIGHT TERMINAL v1.0.0', tone: Tone.bright);
    print('  A telescope control surface rebuilt as a text console.');
    print('  Everything you see is drawn from a local star catalogue —');
    print('  no network, no sky API, no telemetry leaving the machine.');
    print('');
    print('  Coordinates are converted from equatorial to horizontal');
    print('  using your site latitude and the current sidereal time,');
    print('  updated once per second.');
    print('');
    print('  ${'─' * 44}', tone: Tone.line);
    print('  built with Flutter · running on web + android', tone: Tone.dim);
  }

  // ── Agents / keys / effects ────────────────────────────────────────────

  void _cmdAgents(List<String> args) {
    final b = bridge;
    if (b == null) {
      print('  agent runtime not mounted.', tone: Tone.err);
      return;
    }
    final agents = b.agentSummary();
    if (args.isNotEmpty && args.first == 'list') {
      print(ruleLine('AGENTS', 50), tone: Tone.heading);
      for (final a in agents) {
        print('  ${a.enabled ? '●' : '○'} ${pad(a.name, 12)}'
            '${pad(a.provider, 12)}${a.state}',
            tone: a.enabled ? Tone.plain : Tone.dim);
      }
      print('  *ask <agent> <task>* to run one, *fleet <task>* for all.',
          tone: Tone.dim);
      return;
    }
    print(ruleLine('AGENT FLEET', 50), tone: Tone.heading, glow: true);
    if (agents.isEmpty) {
      print('  no agents configured.', tone: Tone.warn);
      return;
    }
    for (final a in agents) {
      final mark = a.enabled ? '●' : '○';
      print('  $mark ${pad(a.name, 12)}${pad(a.provider, 13)}${a.state}',
          tone: a.enabled ? Tone.bright : Tone.dim);
    }
    print(ruleLine('', 50), tone: Tone.line);
    print('  ${agents.where((a) => a.enabled).length}/${agents.length} enabled · '
        '${b.configuredKeys} provider key(s) ready', tone: Tone.dim);
    print('  *ask surveyor what is up* · *fleet survey the sky*', tone: Tone.dim);
  }

  void _cmdAsk(List<String> args) {
    final b = bridge;
    if (b == null) {
      print('  agent runtime not mounted.', tone: Tone.err);
      return;
    }
    if (args.length < 2) {
      print('  usage: ask <agent> <task>', tone: Tone.warn);
      print('  example: ask surveyor what is above the horizon', tone: Tone.dim);
      return;
    }
    final wanted = args.first.toLowerCase();
    final match = b
        .agentSummary()
        .where((a) => a.name.toLowerCase() == wanted)
        .toList();
    if (match.isEmpty) {
      print('  no agent named "$wanted".', tone: Tone.err);
      final names = b.agentSummary().map((a) => a.name.toLowerCase()).join(', ');
      print('  available: $names', tone: Tone.dim);
      return;
    }
    final task = args.sublist(1).join(' ');
    print('  dispatching to ${match.first.name}…', tone: Tone.ok);
    b.runAgentTask(match.first.id, task);
  }

  void _cmdFleet(List<String> args) {
    final b = bridge;
    if (b == null) {
      print('  agent runtime not mounted.', tone: Tone.err);
      return;
    }
    if (args.isEmpty) {
      print('  usage: fleet <task>', tone: Tone.warn);
      return;
    }
    final task = args.join(' ');
    print('  broadcasting to the fleet: "$task"', tone: Tone.ok, glow: true);
    b.runFleet(task);
  }

  void _cmdKeys(List<String> args) {
    final b = bridge;
    if (b == null) {
      print('  key vault not mounted.', tone: Tone.err);
      return;
    }
    final providers = b.providerSummary();

    if (args.isEmpty || args.first == 'list') {
      print(ruleLine('KEY VAULT', 52), tone: Tone.heading);
      print('  ${b.configuredKeys} of ${providers.length} providers ready',
          tone: b.configuredKeys > 0 ? Tone.ok : Tone.warn);
      print('');
      for (final p in providers) {
        final mark = p.ready ? '●' : '○';
        print('  $mark ${pad(p.label, 20)}${pad(p.kind, 7)}${p.masked}',
            tone: p.ready ? Tone.plain : Tone.dim);
      }
      print('');
      print('  *keys set <id> <key>* to store a key.', tone: Tone.dim);
      return;
    }

    if (args.first == 'set') {
      if (args.length < 3) {
        print('  usage: keys set <provider-id> <key>', tone: Tone.warn);
        return;
      }
      final id = args[1].toLowerCase();
      final key = args.sublist(2).join(' ').trim();
      final exists = providers.any((p) => p.id == id);
      if (!exists) {
        print('  unknown provider "$id". try *keys list*.', tone: Tone.err);
        return;
      }
      b.setProviderKey(id, key);
      // Never echo the key back — only a masked confirmation.
      print('  key stored for $id (${key.length} chars)', tone: Tone.ok);
      print('  note: keys live in local storage on this device only.',
          tone: Tone.dim);
      return;
    }

    print('  usage: keys [list] | keys set <id> <key>', tone: Tone.warn);
  }

  void _cmdEffect(List<String> args) {
    final b = bridge;
    if (b == null) {
      print('  effect stack not mounted.', tone: Tone.err);
      return;
    }
    if (args.isEmpty) {
      print(ruleLine('BACKGROUND EFFECT', 46), tone: Tone.heading);
      final current = b.currentEffect();
      for (final name in b.effectNames()) {
        final mark = name == current ? '●' : '○';
        print('  $mark $name', tone: name == current ? Tone.bright : Tone.plain);
      }
      print('');
      print('  *fx <name>* to switch · *fx random* to roll', tone: Tone.dim);
      return;
    }
    final name = args.first.toLowerCase();
    if (name == 'random' || name == 'randomise' || name == 'randomize') {
      b.randomiseEffect();
      print('  effect rolled → ${b.currentEffect()}', tone: Tone.ok, glow: true);
      return;
    }
    if (!b.effectNames().contains(name)) {
      print('  unknown effect "$name".', tone: Tone.err);
      return;
    }
    b.setEffect(name);
    print('  effect → $name', tone: Tone.ok, glow: true);
  }

  void _cmdBanner() {
    print('');
    for (final line in bannerLines) {
      print(line, tone: Tone.heading, glow: true);
    }
    print('');
  }

  // ══════════════════════════════════════════════════════════════════════
  // Public actions used by the UI chrome
  // ══════════════════════════════════════════════════════════════════════

  void selectStar(Star s) {
    _selectedStarId = s.id;
    _safeNotify();
  }

  void clearSelection() {
    _selectedStarId = null;
    _safeNotify();
  }

  void setPalette(Palette p) {
    _palette = p;
    _persistPalette();
    _safeNotify();
  }

  void cyclePalette() {
    _palette = _palette.next();
    _persistPalette();
    _safeNotify();
  }

  void toggleCrt() {
    _crtEnabled = !_crtEnabled;
    _persistCrt();
    _safeNotify();
  }

  void runCommand(String cmd) {
    setInput(cmd);
    submit();
  }

  void resetTime() {
    _timeOffsetHours = 0;
    _trackingLive = true;
    _now = DateTime.now();
    _recomputeSky();
    _safeNotify();
  }

  void shiftTime(int hours) {
    _timeOffsetHours = (_timeOffsetHours + hours).clamp(-24, 24);
    _trackingLive = false;
    _recomputeSky();
    _safeNotify();
  }

  void setSite(double lat, double lon, String name) {
    _latitude = lat;
    _longitude = lon;
    _siteName = name;
    _persistSite();
    _recomputeSky();
    _safeNotify();
  }

  void addNote(String text) {
    if (text.trim().isEmpty) return;
    _notes.add(
      SkyNote(
        text: text.trim(),
        createdAt: observationTime,
        starId: _selectedStarId,
      ),
    );
    _persistNotes();
    _safeNotify();
  }

  void deleteNote(int index) {
    if (index < 0 || index >= _notes.length) return;
    _notes.removeAt(index);
    _persistNotes();
    _safeNotify();
  }

  String _starNameFor(String id) {
    for (final s in kStarCatalogue) {
      if (s.id == id) return s.name;
    }
    return id;
  }

  // ══════════════════════════════════════════════════════════════════════
  // Helpers
  // ══════════════════════════════════════════════════════════════════════

  String _wrap(String text, int width, {int indent = 0}) {
    if (text.isEmpty) return '';
    final words = text.split(' ');
    final lines = <String>[];
    var current = StringBuffer(' ' * indent);
    var col = indent;
    for (final w in words) {
      if (col + w.length + 1 > width && col > indent) {
        lines.add(current.toString());
        current = StringBuffer(' ' * indent);
        col = indent;
      }
      current.write(w);
      col += w.length;
      if (w != words.last) {
        current.write(' ');
        col++;
      }
    }
    lines.add(current.toString());
    return lines.join('\n');
  }

  // ══════════════════════════════════════════════════════════════════════
  // Persistence
  // ══════════════════════════════════════════════════════════════════════

  Future<void> _loadPrefs() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final paletteName = _prefs!.getString(_prefsPalette);
      if (paletteName != null) _palette = Palette.byName(paletteName);
      _crtEnabled = _prefs!.getBool(_prefsCrt) ?? true;
      final lat = _prefs!.getDouble(_prefsSiteLat);
      final lon = _prefs!.getDouble(_prefsSiteLon);
      final name = _prefs!.getString(_prefsSiteName);
      if (lat != null && lon != null && name != null) {
        _latitude = lat;
        _longitude = lon;
        _siteName = name;
      }
      _observer = _prefs!.getString(_prefsObserver) ?? 'guest';
      _loggedIn = _observer != 'guest';

      final raw = _prefs!.getStringList(_prefsNotes) ?? const <String>[];
      _notes
        ..clear()
        ..addAll(raw.map(SkyNote.decode).whereType<SkyNote>());
    } catch (_) {
      // Persistence is a convenience; never block the terminal on it.
    }
    _safeNotify();
  }

  Future<void> _persistNotes() async {
    try {
      await _prefs?.setStringList(
        _prefsNotes,
        _notes.map((n) => n.encode()).toList(),
      );
    } catch (_) {
      /* ignore */
    }
  }

  Future<void> _persistPalette() async {
    try {
      await _prefs?.setString(_prefsPalette, _palette.label);
    } catch (_) {
      /* ignore */
    }
  }

  Future<void> _persistCrt() async {
    try {
      await _prefs?.setBool(_prefsCrt, _crtEnabled);
    } catch (_) {
      /* ignore */
    }
  }

  Future<void> _persistSite() async {
    try {
      await _prefs?.setDouble(_prefsSiteLat, _latitude);
      await _prefs?.setDouble(_prefsSiteLon, _longitude);
      await _prefs?.setString(_prefsSiteName, _siteName);
    } catch (_) {
      /* ignore */
    }
  }

  Future<void> _persistObserver() async {
    try {
      await _prefs?.setString(_prefsObserver, _observer);
    } catch (_) {
      /* ignore */
    }
  }
}

/// Callbacks the console uses to drive the studio. Implemented by
/// StudioController; kept as an interface so the terminal stays testable.
abstract class CommandBridge {
  List<({String id, String name, bool enabled, String provider, String state})>
      agentSummary();
  void runAgentTask(String agentId, String task);
  void runFleet(String task);
  List<({String id, String label, String kind, bool ready, String masked})>
      providerSummary();
  void setProviderKey(String providerId, String key);
  int get configuredKeys;
  List<String> effectNames();
  String currentEffect();
  void setEffect(String name);
  void randomiseEffect();
}

/// A single observing-log entry.
class SkyNote {
  SkyNote({required this.text, required this.createdAt, this.starId});

  final String text;
  final DateTime createdAt;
  final String? starId;

  String encode() =>
      '${createdAt.toIso8601String()}\u0001${starId ?? ''}\u0001$text';

  static SkyNote? decode(String raw) {
    final parts = raw.split('\u0001');
    if (parts.length < 3) return null;
    final t = DateTime.tryParse(parts[0]);
    if (t == null) return null;
    final starId = parts[1].isEmpty ? null : parts[1];
    final text = parts.sublist(2).join('\u0001');
    return SkyNote(text: text, createdAt: t, starId: starId);
  }
}

/// ASCII banner drawn by `banner` and on first boot.
const List<String> bannerLines = <String>[
  '   ███████╗████████╗ █████╗ ██████╗ ██╗     ██╗ ██████╗ ██╗  ██╗████████╗',
  '   ██╔════╝╚══██╔══╝██╔══██╗██╔══██╗██║     ██║██╔════╝ ██║  ██║╚══██╔══╝',
  '   ███████╗   ██║   ███████║██████╔╝██║     ██║██║  ███╗███████║   ██║   ',
  '   ╚════██║   ██║   ██╔══██║██╔══██╗██║     ██║██║   ██║██╔══██║   ██║   ',
  '   ███████║   ██║   ██║  ██║██║  ██║███████╗██║╚██████╔╝██║  ██║   ██║   ',
  '   ╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝ ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ',
];
