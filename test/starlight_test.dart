import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/catalogue.dart';
import 'package:flutter_app/core/console_engine.dart';
import 'package:flutter_app/core/palette.dart';

void main() {
  group('coordinate maths', () {
    test('a star on the meridian sits at alt = 90 - |dec - lat|', () {
      const ra = 100.0;
      final h = equatorialToHorizontal(
        raDegrees: ra,
        decDegrees: 40.0,
        lstDegrees: ra,
        latitude: 40.0,
      );
      expect(h.altitude, closeTo(90.0, 0.001));
    });

    test('north celestial pole altitude equals observer latitude', () {
      final h = equatorialToHorizontal(
        raDegrees: 0,
        decDegrees: 90,
        lstDegrees: 0,
        latitude: 51.5,
      );
      expect(h.altitude, closeTo(51.5, 0.001));
    });

    test('altitude and azimuth stay in physical bounds all day', () {
      for (final s in kStarCatalogue) {
        for (var lst = 0.0; lst < 360.0; lst += 15.0) {
          final h = equatorialToHorizontal(
            raDegrees: s.rightAscensionDegrees,
            decDegrees: s.decDegrees,
            lstDegrees: lst,
            latitude: 51.4779,
          );
          expect(h.altitude, inInclusiveRange(-90.0, 90.0));
          expect(h.azimuth, inInclusiveRange(0.0, 360.0));
        }
      }
    });

    test('sidereal time advances about 15 degrees per hour', () {
      final t0 = DateTime.utc(2024, 5, 13, 20);
      final t1 = t0.add(const Duration(hours: 1));
      var d = localSiderealDegrees(t1, 0) - localSiderealDegrees(t0, 0);
      if (d < 0) d += 360;
      expect(d, closeTo(15.04, 0.4));
    });
  });

  group('moon phase', () {
    test('known new moon reads as new', () {
      final p = moonPhase(DateTime.utc(2000, 1, 6, 18, 14));
      expect(p, lessThan(0.02));
      expect(moonPhaseName(p), 'New Moon');
    });

    test('phase stays inside [0,1)', () {
      for (var d = 0; d < 400; d += 7) {
        final p = moonPhase(DateTime.utc(2024, 1, 1).add(Duration(days: d)));
        expect(p, greaterThanOrEqualTo(0.0));
        expect(p, lessThan(1.0));
      }
    });

    test('full moon reads as full', () {
      final p = moonPhase(DateTime.utc(2024, 4, 23, 23, 49));
      expect(moonPhaseName(p), 'Full Moon');
    });
  });

  group('markup parser', () {
    test('splits emphasis runs', () {
      final chunks = parseMarkup('type *help* now');
      expect(chunks.map((c) => c.text).join(), 'type help now');
      expect(chunks.where((c) => c.emphasised).length, 1);
      expect(chunks.firstWhere((c) => c.emphasised).text, 'help');
    });

    test('unbalanced marker degrades gracefully', () {
      final chunks = parseMarkup('5 * 3');
      expect(chunks.any((c) => c.text.contains('*')), isTrue);
    });

    test('plain text yields a single chunk', () {
      final chunks = parseMarkup('nothing special');
      expect(chunks.length, 1);
      expect(chunks.single.emphasised, isFalse);
    });
  });

  group('formatting helpers', () {
    test('right ascension', () {
      expect(fmtRa(6.7525), '06h 45m');
    });

    test('magnitude keeps its sign', () {
      expect(fmtMag(-1.46), '−1.46');
      expect(fmtMag(2.0), '+2.00');
    });

    test('compass points land on the cardinals', () {
      expect(compassPoint(0), 'N');
      expect(compassPoint(90), 'E');
      expect(compassPoint(180), 'S');
      expect(compassPoint(270), 'W');
    });

    test('meters never overrun their width', () {
      for (final f in [-1.0, 0.0, 0.5, 1.0, 2.0]) {
        expect(meter(f, width: 10).length, 10);
      }
    });

    test('clip never exceeds the requested width', () {
      expect(clip('abcdef', 3).length, 3);
      expect(clip('ab', 5), 'ab');
    });
  });

  group('palette', () {
    test('lookup is case-insensitive and falls back to phosphor', () {
      expect(Palette.byName('AMBER').id, TerminalPalette.amber);
      expect(Palette.byName('nope').id, TerminalPalette.phosphor);
    });

    test('cycling visits every palette exactly once', () {
      var p = Palette.phosphor;
      final seen = <TerminalPalette>{};
      for (var i = 0; i < Palette.all.length; i++) {
        seen.add(p.id);
        p = p.next();
      }
      expect(seen.length, Palette.all.length);
      expect(p.id, TerminalPalette.phosphor);
    });
  });

  group('catalogue integrity', () {
    test('every star has a unique id and sane coordinates', () {
      final ids = kStarCatalogue.map((s) => s.id).toSet();
      expect(ids.length, kStarCatalogue.length);
      for (final s in kStarCatalogue) {
        expect(s.raHours, inInclusiveRange(0.0, 24.0));
        expect(s.decDegrees, inInclusiveRange(-90.0, 90.0));
        expect(s.magnitude, lessThan(3.0));
        expect(s.name, isNotEmpty);
      }
    });

    test('catalogue is large enough to feel real', () {
      expect(kStarCatalogue.length, greaterThanOrEqualTo(35));
    });
  });
}
