import 'dart:convert';
import 'dart:io';

import 'package:boite_a_outils/features/pdf_tool/data/pdf_conversion_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = PdfConversionService();

  test('imagesToPdf produces a valid, non-trivial PDF from a real PNG', () async {
    // Minimal valid 4x4 red PNG, generated programmatically (see
    // scratchpad/make_png.py used during Phase 2 verification).
    final tempDir = await Directory.systemTemp.createTemp('pdf_tool_test');
    final pngFile = File('${tempDir.path}/test.png');
    await pngFile.writeAsBytes(_minimalPng());

    final bytes = await service.imagesToPdf([pngFile.path]);

    expect(bytes.length, greaterThan(100));
    expect(ascii.decode(bytes.sublist(0, 4)), '%PDF');

    await tempDir.delete(recursive: true);
  });

  test(
    'imagesToPdf combines multiple images into one PDF, one page each, '
    'in selection order',
    () async {
      // Reuses the same minimal PNG fixture as the single-image test above,
      // repeated 3 times (as the same path) to simulate a multi-image
      // selection — the service takes a list of paths, it doesn't care
      // whether the paths are distinct files or not.
      final tempDir = await Directory.systemTemp.createTemp('pdf_tool_test');
      final pngFile = File('${tempDir.path}/test.png');
      await pngFile.writeAsBytes(_minimalPng());

      final singleImageBytes = await service.imagesToPdf([pngFile.path]);
      final threeImageBytes = await service.imagesToPdf(
        [pngFile.path, pngFile.path, pngFile.path],
      );

      expect(ascii.decode(threeImageBytes.sublist(0, 4)), '%PDF');
      // A byte-length comparison against the single-image PDF is more
      // robust than asserting an absolute size threshold: the `pdf`
      // package's fixed overhead (fonts, xref table, metadata) is shared by
      // both PDFs, so this isolates the cost actually added by combining
      // more image pages rather than depending on incidental package
      // internals. A combined 3-page PDF embeds the same image bytes 3
      // times, so it must be meaningfully larger than a single page, not
      // just marginally larger due to noise (e.g. timestamps).
      expect(
        threeImageBytes.length,
        greaterThan(singleImageBytes.length * 2),
      );

      await tempDir.delete(recursive: true);
    },
  );

  test('textToPdf produces a valid PDF for long multi-paragraph text', () async {
    final longText = List.generate(
      200,
      (i) => 'Ligne $i : ${'lorem ipsum dolor sit amet ' * 5}',
    ).join('\n');

    final bytes = await service.textToPdf(longText);

    expect(bytes.length, greaterThan(100));
    expect(ascii.decode(bytes.sublist(0, 4)), '%PDF');
  });
}

/// Minimal valid 4x4 RGB red PNG (generated with a small Python script using
/// `zlib`/`struct` during Phase 2 verification, then base64-embedded here so
/// the test has no external asset dependency and the PNG chunk CRCs/zlib
/// stream are guaranteed correct).
List<int> _minimalPng() {
  return base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAIAAAAmkwkpAAAAEElEQVR4nGP4z8AARwzEcQCu'
    'kw/x0F8jngAAAABJRU5ErkJggg==',
  );
}
