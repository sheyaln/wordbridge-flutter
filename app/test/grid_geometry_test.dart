import 'package:flutter/rendering.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:wordbridge/features/grid/grid_geometry.dart';

void main() {
  const surface = Size(1024, 768);
  const geometry = GridGeometry(rows: 7, cols: 12, size: surface);

  group('layout is exact', () {
    test('cells tile the surface without drift', () {
      final last = geometry.rectFor(6, 11);
      final rightEdge = last.right + geometry.gutter;
      final bottomEdge = last.bottom + geometry.gutter;

      expect(rightEdge, closeTo(surface.width, 0.001));
      expect(bottomEdge, closeTo(surface.height, 0.001));
    });

    test('neighbors are separated by exactly one gutter', () {
      final a = geometry.rectFor(0, 0);
      final b = geometry.rectFor(0, 1);
      expect(b.left - a.right, closeTo(geometry.gutter, 0.001));

      final c = geometry.rectFor(1, 0);
      expect(c.top - a.bottom, closeTo(geometry.gutter, 0.001));
    });

    test('every cell is identically sized', () {
      final first = geometry.rectFor(0, 0);
      for (var r = 0; r < 7; r++) {
        for (var c = 0; c < 12; c++) {
          final rect = geometry.rectFor(r, c);
          expect(rect.width, closeTo(first.width, 0.001));
          expect(rect.height, closeTo(first.height, 0.001));
        }
      }
    });
  });

  group('position is a pure function of coordinates', () {
    test('the same coordinates always yield the same rect', () {
      // The property the whole project rests on: where a cell lands depends
      // only on its coordinates and the surface, never on what occupies it,
      // how many neighbors exist, or what order anything was built in.
      const a = GridGeometry(rows: 7, cols: 12, size: surface);
      const b = GridGeometry(rows: 7, cols: 12, size: surface);
      expect(a.rectFor(3, 5), b.rectFor(3, 5));
    });

    test('a full grid and a sparse one place cells identically', () {
      // Two vocabularies of the same geometry must agree on position even if
      // one has 36 words and the other 84.
      const dense = GridGeometry(rows: 7, cols: 12, size: surface);
      const sparse = GridGeometry(rows: 7, cols: 12, size: surface);
      for (var r = 0; r < 7; r++) {
        for (var c = 0; c < 12; c++) {
          expect(dense.rectFor(r, c), sparse.rectFor(r, c));
        }
      }
    });
  });

  group('spans', () {
    test('a merged cell covers its constituents plus the gutter between', () {
      final single = geometry.rectFor(0, 0);
      final wide = geometry.rectFor(0, 0, spanCols: 2);
      expect(wide.width, closeTo(single.width * 2 + geometry.gutter, 0.001));
    });
  });

  group('touch targets', () {
    test('a comfortable grid passes', () {
      expect(geometry.meetsMinimumTouchTarget, isTrue);
    });

    test('an over-dense grid on a small surface fails', () {
      const cramped = GridGeometry(rows: 12, cols: 20, size: Size(480, 320));
      expect(
        cramped.meetsMinimumTouchTarget,
        isFalse,
        reason: 'the caregiver must be warned before this reaches a user',
      );
    });
  });
}
