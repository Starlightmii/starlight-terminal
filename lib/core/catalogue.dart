import 'dart:math' as math;

/// A single catalogue entry in the terminal's star index.
class Star {
  const Star({
    required this.id,
    required this.name,
    required this.bayer,
    required this.constellation,
    required this.raHours,
    required this.decDegrees,
    required this.magnitude,
    required this.spectral,
    required this.distanceLy,
    required this.note,
    this.altitude = 0,
    this.azimuth = 0,
  });

  final String id;

  /// Proper name, e.g. "Vega".
  final String name;

  /// Bayer designation, e.g. "Alpha Lyrae".
  final String bayer;

  /// IAU three-letter constellation abbreviation + full name.
  final String constellation;

  /// Right ascension, in hours (0..24).
  final double raHours;

  /// Declination, in degrees (-90..90).
  final double decDegrees;

  /// Apparent visual magnitude (lower = brighter).
  final double magnitude;

  /// Spectral class string, e.g. "A0V".
  final String spectral;

  /// Distance in light years (0 if unknown).
  final double distanceLy;

  /// One-line observing note shown in the detail pane.
  final String note;

  /// Current computed altitude above horizon, in degrees.
  final double altitude;

  /// Current computed azimuth, in degrees.
  final double azimuth;

  double get rightAscensionDegrees => raHours * 15.0;

  Star copyWithAltAz(double alt, double az) => Star(
    id: id,
    name: name,
    bayer: bayer,
    constellation: constellation,
    raHours: raHours,
    decDegrees: decDegrees,
    magnitude: magnitude,
    spectral: spectral,
    distanceLy: distanceLy,
    note: note,
    altitude: alt,
    azimuth: az,
  );
}

/// The built-in catalogue — 41 naked-eye stars, brightest first.
const List<Star> kStarCatalogue = <Star>[
  Star(
    id: 'sirius',
    name: 'Sirius',
    bayer: 'Alpha Canis Majoris',
    constellation: 'CMa / Canis Major',
    raHours: 6.7525,
    decDegrees: -16.716,
    magnitude: -1.46,
    spectral: 'A1V',
    distanceLy: 8.6,
    note: 'Brightest star in the night sky. Flashes colours when low.',
  ),
  Star(
    id: 'canopus',
    name: 'Canopus',
    bayer: 'Alpha Carinae',
    constellation: 'Car / Carina',
    raHours: 6.399,
    decDegrees: -52.696,
    magnitude: -0.74,
    spectral: 'A9II',
    distanceLy: 310,
    note: 'Second brightest. Used as a spacecraft navigation beacon.',
  ),
  Star(
    id: 'arcturus',
    name: 'Arcturus',
    bayer: 'Alpha Bootis',
    constellation: 'Boo / Boötes',
    raHours: 14.261,
    decDegrees: 19.182,
    magnitude: -0.05,
    spectral: 'K1.5III',
    distanceLy: 36.7,
    note: 'Orange giant. Follow the arc of the Big Dipper handle to find it.',
  ),
  Star(
    id: 'vega',
    name: 'Vega',
    bayer: 'Alpha Lyrae',
    constellation: 'Lyr / Lyra',
    raHours: 18.615,
    decDegrees: 38.784,
    magnitude: 0.03,
    spectral: 'A0V',
    distanceLy: 25.0,
    note: 'Was the pole star ~12,000 BCE; will be again in ~13,000 years.',
  ),
  Star(
    id: 'capella',
    name: 'Capella',
    bayer: 'Alpha Aurigae',
    constellation: 'Aur / Auriga',
    raHours: 5.278,
    decDegrees: 45.998,
    magnitude: 0.08,
    spectral: 'G8III',
    distanceLy: 42.9,
    note: 'A four-star system masquerading as one point of light.',
  ),
  Star(
    id: 'rigel',
    name: 'Rigel',
    bayer: 'Beta Orionis',
    constellation: 'Ori / Orion',
    raHours: 5.242,
    decDegrees: -8.202,
    magnitude: 0.13,
    spectral: 'B8Ia',
    distanceLy: 860,
    note:
        'Blue supergiant foot of Orion. Luminous enough to be seen from 800 ly.',
  ),
  Star(
    id: 'procyon',
    name: 'Procyon',
    bayer: 'Alpha Canis Minoris',
    constellation: 'CMi / Canis Minor',
    raHours: 7.655,
    decDegrees: 5.225,
    magnitude: 0.34,
    spectral: 'F5IV',
    distanceLy: 11.5,
    note: 'Completes the Winter Triangle with Sirius and Betelgeuse.',
  ),
  Star(
    id: 'betelgeuse',
    name: 'Betelgeuse',
    bayer: 'Alpha Orionis',
    constellation: 'Ori / Orion',
    raHours: 5.919,
    decDegrees: 7.407,
    magnitude: 0.42,
    spectral: 'M1Ia',
    distanceLy: 548,
    note: 'Red supergiant that will go supernova within ~100,000 years.',
  ),
  Star(
    id: 'achernar',
    name: 'Achernar',
    bayer: 'Alpha Eridani',
    constellation: 'Eri / Eridanus',
    raHours: 1.629,
    decDegrees: -57.237,
    magnitude: 0.46,
    spectral: 'B6V',
    distanceLy: 139,
    note: 'The flattest known star — its equator bulges by 50%.',
  ),
  Star(
    id: 'hadar',
    name: 'Hadar',
    bayer: 'Beta Centauri',
    constellation: 'Cen / Centaurus',
    raHours: 14.064,
    decDegrees: -60.373,
    magnitude: 0.61,
    spectral: 'B1III',
    distanceLy: 390,
    note: 'The pointer nearest the Southern Cross, with Alpha Cen.',
  ),
  Star(
    id: 'altair',
    name: 'Altair',
    bayer: 'Alpha Aquilae',
    constellation: 'Aql / Aquila',
    raHours: 19.846,
    decDegrees: 8.868,
    magnitude: 0.76,
    spectral: 'A7V',
    distanceLy: 16.7,
    note: 'Third vertex of the Summer Triangle. Spins in under 9 hours.',
  ),
  Star(
    id: 'acrux',
    name: 'Acrux',
    bayer: 'Alpha Crucis',
    constellation: 'Cru / Crux',
    raHours: 12.443,
    decDegrees: -63.099,
    magnitude: 0.77,
    spectral: 'B0.5IV',
    distanceLy: 321,
    note: 'Brightest star of the Southern Cross.',
  ),
  Star(
    id: 'aldebaran',
    name: 'Aldebaran',
    bayer: 'Alpha Tauri',
    constellation: 'Tau / Taurus',
    raHours: 4.599,
    decDegrees: 16.509,
    magnitude: 0.85,
    spectral: 'K5III',
    distanceLy: 65.3,
    note: 'The "follower" — the bull\'s eye, chasing the Pleiades.',
  ),
  Star(
    id: 'antares',
    name: 'Antares',
    bayer: 'Alpha Scorpii',
    constellation: 'Sco / Scorpius',
    raHours: 16.49,
    decDegrees: -26.432,
    magnitude: 0.96,
    spectral: 'M1.5Iab',
    distanceLy: 550,
    note: 'Rival of Mars — named for its red colour.',
  ),
  Star(
    id: 'spica',
    name: 'Spica',
    bayer: 'Alpha Virginis',
    constellation: 'Vir / Virgo',
    raHours: 13.42,
    decDegrees: -11.161,
    magnitude: 0.98,
    spectral: 'B1V',
    distanceLy: 250,
    note: 'Follow the arc from the Dipper to Arcturus, then spike on to Spica.',
  ),
  Star(
    id: 'pollux',
    name: 'Pollux',
    bayer: 'Beta Geminorum',
    constellation: 'Gem / Gemini',
    raHours: 7.755,
    decDegrees: 28.026,
    magnitude: 1.14,
    spectral: 'K0III',
    distanceLy: 33.8,
    note: 'Nearest giant star to the Sun, with a confirmed exoplanet.',
  ),
  Star(
    id: 'fomalhaut',
    name: 'Fomalhaut',
    bayer: 'Alpha Piscis Austrini',
    constellation: 'PsA / Piscis Austrinus',
    raHours: 22.961,
    decDegrees: -29.622,
    magnitude: 1.16,
    spectral: 'A3V',
    distanceLy: 25.1,
    note: 'The Lonely Star of autumn — no bright neighbours nearby.',
  ),
  Star(
    id: 'deneb',
    name: 'Deneb',
    bayer: 'Alpha Cygni',
    constellation: 'Cyg / Cygnus',
    raHours: 20.69,
    decDegrees: 45.28,
    magnitude: 1.25,
    spectral: 'A2Ia',
    distanceLy: 2600,
    note: 'One of the most luminous stars known — 200,000× the Sun.',
  ),
  Star(
    id: 'mimosa',
    name: 'Mimosa',
    bayer: 'Beta Crucis',
    constellation: 'Cru / Crux',
    raHours: 12.795,
    decDegrees: -59.689,
    magnitude: 1.25,
    spectral: 'B0.5IV',
    distanceLy: 280,
    note: 'Second brightest of the Southern Cross; pulses gently.',
  ),
  Star(
    id: 'regulus',
    name: 'Regulus',
    bayer: 'Alpha Leonis',
    constellation: 'Leo / Leo',
    raHours: 10.139,
    decDegrees: 11.967,
    magnitude: 1.35,
    spectral: 'B7V',
    distanceLy: 79.3,
    note: 'The Little King — sits almost exactly on the ecliptic.',
  ),
  Star(
    id: 'adhara',
    name: 'Adhara',
    bayer: 'Epsilon Canis Majoris',
    constellation: 'CMa / Canis Major',
    raHours: 6.977,
    decDegrees: -28.972,
    magnitude: 1.5,
    spectral: 'B2II',
    distanceLy: 430,
    note: 'Was the brightest star in the sky 4.7 million years ago.',
  ),
  Star(
    id: 'castor',
    name: 'Castor',
    bayer: 'Alpha Geminorum',
    constellation: 'Gem / Gemini',
    raHours: 7.577,
    decDegrees: 31.888,
    magnitude: 1.58,
    spectral: 'A1V',
    distanceLy: 51.0,
    note: 'A sextuple system — six stars bound in one dance.',
  ),
  Star(
    id: 'shaula',
    name: 'Shaula',
    bayer: 'Lambda Scorpii',
    constellation: 'Sco / Scorpius',
    raHours: 17.56,
    decDegrees: -37.104,
    magnitude: 1.62,
    spectral: 'B1.5IV',
    distanceLy: 570,
    note: 'The raised stinger of the scorpion.',
  ),
  Star(
    id: 'bellatrix',
    name: 'Bellatrix',
    bayer: 'Gamma Orionis',
    constellation: 'Ori / Orion',
    raHours: 5.418,
    decDegrees: 6.35,
    magnitude: 1.64,
    spectral: 'B2III',
    distanceLy: 250,
    note: 'The Amazon Star — Orion\'s left shoulder.',
  ),
  Star(
    id: 'elnath',
    name: 'Elnath',
    bayer: 'Beta Tauri',
    constellation: 'Tau / Taurus',
    raHours: 5.438,
    decDegrees: 28.608,
    magnitude: 1.65,
    spectral: 'B7III',
    distanceLy: 134,
    note: 'Shared between Taurus and Auriga — the bull\'s northern horn.',
  ),
  Star(
    id: 'miaplacidus',
    name: 'Miaplacidus',
    bayer: 'Beta Carinae',
    constellation: 'Car / Carina',
    raHours: 9.22,
    decDegrees: -69.717,
    magnitude: 1.67,
    spectral: 'A1III',
    distanceLy: 113,
    note: 'Name means "placid waters". Southern keel of Argo Navis.',
  ),
  Star(
    id: 'alnilam',
    name: 'Alnilam',
    bayer: 'Epsilon Orionis',
    constellation: 'Ori / Orion',
    raHours: 5.604,
    decDegrees: -1.202,
    magnitude: 1.69,
    spectral: 'B0Ia',
    distanceLy: 2000,
    note: 'The central star of Orion\'s Belt — the middle one.',
  ),
  Star(
    id: 'alnitak',
    name: 'Alnitak',
    bayer: 'Zeta Orionis',
    constellation: 'Ori / Orion',
    raHours: 5.679,
    decDegrees: -1.943,
    magnitude: 1.77,
    spectral: 'O9.5Ib',
    distanceLy: 1260,
    note: 'Eastern belt star; its nearby Flame Nebula is a photo target.',
  ),
  Star(
    id: 'mintaka',
    name: 'Mintaka',
    bayer: 'Delta Orionis',
    constellation: 'Ori / Orion',
    raHours: 5.533,
    decDegrees: -0.299,
    magnitude: 2.23,
    spectral: 'O9.5II',
    distanceLy: 1200,
    note: 'Western belt star — sits almost exactly on the celestial equator.',
  ),
  Star(
    id: 'dubhe',
    name: 'Dubhe',
    bayer: 'Alpha Ursae Majoris',
    constellation: 'UMa / Ursa Major',
    raHours: 11.062,
    decDegrees: 61.751,
    magnitude: 1.79,
    spectral: 'K0III',
    distanceLy: 123,
    note: 'Points the way to Polaris with Merak — the Pointers.',
  ),
  Star(
    id: 'mirfak',
    name: 'Mirfak',
    bayer: 'Alpha Persei',
    constellation: 'Per / Perseus',
    raHours: 3.405,
    decDegrees: 49.861,
    magnitude: 1.79,
    spectral: 'F5Ib',
    distanceLy: 510,
    note: 'Heart of the Alpha Persei Moving Cluster.',
  ),
  Star(
    id: 'wezen',
    name: 'Wezen',
    bayer: 'Delta Canis Majoris',
    constellation: 'CMa / Canis Major',
    raHours: 7.14,
    decDegrees: -26.393,
    magnitude: 1.83,
    spectral: 'F8Ia',
    distanceLy: 1600,
    note: 'A yellow-white supergiant 500× the Sun\'s diameter.',
  ),
  Star(
    id: 'sargas',
    name: 'Sargas',
    bayer: 'Theta Scorpii',
    constellation: 'Sco / Scorpius',
    raHours: 17.622,
    decDegrees: -42.998,
    magnitude: 1.87,
    spectral: 'F0II',
    distanceLy: 270,
    note: 'Sumerians called it "the bright one of the scorpion tail".',
  ),
  Star(
    id: 'kaus-australis',
    name: 'Kaus Australis',
    bayer: 'Epsilon Sagittarii',
    constellation: 'Sgr / Sagittarius',
    raHours: 18.403,
    decDegrees: -34.385,
    magnitude: 1.85,
    spectral: 'B9.5III',
    distanceLy: 143,
    note: 'Brightest star of the Teapot; near the galactic centre.',
  ),
  Star(
    id: 'avior',
    name: 'Avior',
    bayer: 'Epsilon Carinae',
    constellation: 'Car / Carina',
    raHours: 8.375,
    decDegrees: -59.51,
    magnitude: 1.86,
    spectral: 'K3III',
    distanceLy: 630,
    note: 'An eclipsing binary whose brightness dips every 2.7 years.',
  ),
  Star(
    id: 'alkaid',
    name: 'Alkaid',
    bayer: 'Eta Ursae Majoris',
    constellation: 'UMa / Ursa Major',
    raHours: 13.792,
    decDegrees: 49.313,
    magnitude: 1.86,
    spectral: 'B3V',
    distanceLy: 104,
    note: 'The tip of the Big Dipper handle — the "arc" pointer to Arcturus.',
  ),
  Star(
    id: 'menkalinan',
    name: 'Menkalinan',
    bayer: 'Beta Aurigae',
    constellation: 'Aur / Auriga',
    raHours: 5.992,
    decDegrees: 44.947,
    magnitude: 1.9,
    spectral: 'A1IV',
    distanceLy: 81,
    note: 'Two nearly identical stars eclipsing each other every 4 days.',
  ),
  Star(
    id: 'atria',
    name: 'Atria',
    bayer: 'Alpha Trianguli Australis',
    constellation: 'TrA / Triangulum Australe',
    raHours: 16.811,
    decDegrees: -69.028,
    magnitude: 1.91,
    spectral: 'K2II',
    distanceLy: 391,
    note: 'Name is a contraction of its Bayer designation: A-Tri-A.',
  ),
  Star(
    id: 'alhena',
    name: 'Alhena',
    bayer: 'Gamma Geminorum',
    constellation: 'Gem / Gemini',
    raHours: 6.629,
    decDegrees: 16.399,
    magnitude: 1.93,
    spectral: 'A1.5IV',
    distanceLy: 109,
    note: 'The bright star in the Twins\' feet.',
  ),
  Star(
    id: 'polaris',
    name: 'Polaris',
    bayer: 'Alpha Ursae Minoris',
    constellation: 'UMi / Ursa Minor',
    raHours: 2.53,
    decDegrees: 89.264,
    magnitude: 1.98,
    spectral: 'F7Ib',
    distanceLy: 433,
    note: 'The North Star — within 1° of the celestial pole. Cepheid variable.',
  ),
  Star(
    id: 'alphard',
    name: 'Alphard',
    bayer: 'Alpha Hydrae',
    constellation: 'Hya / Hydra',
    raHours: 9.46,
    decDegrees: -8.658,
    magnitude: 1.98,
    spectral: 'K3II',
    distanceLy: 177,
    note: 'The "solitary one" — alone in a dark stretch of Hydra.',
  ),
];

/// Convert equatorial coordinates to local horizontal coordinates.
///
/// [lstDegrees] is local sidereal time expressed in degrees.
/// Returns (altitude, azimuth) in degrees, azimuth measured from north.
({double altitude, double azimuth}) equatorialToHorizontal({
  required double raDegrees,
  required double decDegrees,
  required double lstDegrees,
  required double latitude,
}) {
  final ha = (lstDegrees - raDegrees) * math.pi / 180.0;
  final dec = decDegrees * math.pi / 180.0;
  final lat = latitude * math.pi / 180.0;

  final sinAlt =
      math.sin(dec) * math.sin(lat) +
      math.cos(dec) * math.cos(lat) * math.cos(ha);
  final alt = math.asin(sinAlt.clamp(-1.0, 1.0));

  final cosAz =
      (math.sin(dec) - math.sin(alt) * math.sin(lat)) /
      (math.cos(alt) * math.cos(lat));
  var az = math.acos(cosAz.clamp(-1.0, 1.0));
  if (math.sin(ha) > 0) az = 2 * math.pi - az;

  return (altitude: alt * 180.0 / math.pi, azimuth: az * 180.0 / math.pi);
}

/// Local sidereal time in degrees for a given instant and longitude.
double localSiderealDegrees(DateTime utc, double longitudeDegrees) {
  // Julian date from Unix epoch.
  final jd = utc.millisecondsSinceEpoch / 86400000.0 + 2440587.5;
  final d = jd - 2451545.0;
  // GMST in degrees (Meeus, low precision — plenty for a sky display).
  var gmst = 280.46061837 + 360.98564736629 * d;
  gmst = gmst % 360.0;
  if (gmst < 0) gmst += 360.0;
  var lst = gmst + longitudeDegrees;
  lst = lst % 360.0;
  if (lst < 0) lst += 360.0;
  return lst;
}

/// Compass point for an azimuth in degrees.
String compassPoint(double azimuth) {
  const names = [
    'N',
    'NNE',
    'NE',
    'ENE',
    'E',
    'ESE',
    'SE',
    'SSE',
    'S',
    'SSW',
    'SW',
    'WSW',
    'W',
    'WNW',
    'NW',
    'NNW',
  ];
  var a = azimuth % 360.0;
  if (a < 0) a += 360.0;
  final idx = ((a / 22.5).round()) % 16;
  return names[idx];
}

/// Rough moon phase: 0.0 = new, 0.5 = full, 1.0 = new again.
double moonPhase(DateTime utc) {
  // Reference new moon: 2000-01-06 18:14 UTC.
  final reference = DateTime.utc(2000, 1, 6, 18, 14);
  const synodic = 29.530588853;
  final days = utc.difference(reference).inSeconds / 86400.0;
  var phase = (days % synodic) / synodic;
  if (phase < 0) phase += 1.0;
  return phase;
}

String moonPhaseName(double phase) {
  if (phase < 0.03 || phase > 0.97) return 'New Moon';
  if (phase < 0.22) return 'Waxing Crescent';
  if (phase < 0.28) return 'First Quarter';
  if (phase < 0.47) return 'Waxing Gibbous';
  if (phase < 0.53) return 'Full Moon';
  if (phase < 0.72) return 'Waning Gibbous';
  if (phase < 0.78) return 'Last Quarter';
  return 'Waning Crescent';
}

/// An 8-cell glyph for the current moon phase.
String moonGlyph(double phase) {
  const glyphs = ['●', '◔', '◑', '◕', '○', '◕', '◑', '◔'];
  var idx = ((phase * 8) + 0.5).floor() % 8;
  if (idx < 0) idx += 8;
  return glyphs[idx];
}
