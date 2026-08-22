import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Service de conversion de fichiers (images, texte) vers PDF.
///
/// S'appuie sur le package `pdf` (DavBfr) v3.13.0 — voir
/// `plans/01-pdf-converter-viewer.md` (Phase 0/2) pour la recherche
/// documentaire complète et les sources citées ci-dessous.
class PdfConversionService {
  /// Convertit une liste de chemins d'images en un PDF, une image par page.
  ///
  /// ## KNOWN LIMITATION — HEIC non supporté
  /// Vérifié en Phase 2 en lisant le code source installé de
  /// `pw.MemoryImage` (pub cache :
  /// `pdf-3.13.0/lib/src/widgets/image_provider.dart`), qui délègue le
  /// décodage à `image.findDecoderForData(bytes)` du package `image`
  /// (résolu en dépendance transitive à la version 4.9.2, cf.
  /// `pubspec.lock`). La liste des décodeurs testés par
  /// `findDecoderForData` (pub cache :
  /// `image-4.9.2/lib/src/formats/formats.dart`) est : JPEG, PNG, GIF,
  /// WebP, TIFF, PSD, EXR, BMP, PNM, TGA, ICO, PVR — **aucun décodeur
  /// HEIC/HEIF**. Un HEIC passé à `pw.MemoryImage` lève donc une
  /// `PdfException` ("Unable to guess the image type"). Contre-mesure
  /// côté UI : `PdfToolScreen` ne propose que jpg/jpeg/png dans le
  /// sélecteur de fichiers image, donc aucun HEIC ne devrait jamais
  /// atteindre cette méthode (voir commentaire dans
  /// `pdf_tool_screen.dart`).
  Future<Uint8List> imagesToPdf(List<String> imagePaths) async {
    final document = pw.Document();

    for (final path in imagePaths) {
      final bytes = File(path).readAsBytesSync();
      final image = pw.MemoryImage(bytes);
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) => pw.Center(child: pw.Image(image)),
        ),
      );
    }

    return document.save();
  }

  /// Convertit un texte brut en PDF, en laissant le contenu se répartir
  /// automatiquement sur plusieurs pages si besoin.
  ///
  /// Signature de `pw.MultiPage` vérifiée dans le code source installé
  /// (pub cache : `pdf-3.13.0/lib/src/widgets/multi_page.dart`, classe
  /// `MultiPage extends Page`) :
  /// ```dart
  /// MultiPage({
  ///   PageTheme? pageTheme,
  ///   PdfPageFormat? pageFormat,
  ///   required BuildListCallback build,
  ///   MainAxisAlignment mainAxisAlignment = MainAxisAlignment.start,
  ///   CrossAxisAlignment crossAxisAlignment = CrossAxisAlignment.start,
  ///   BuildCallback? header,
  ///   BuildCallback? footer,
  ///   ThemeData? theme,
  ///   int maxPages = 20,
  ///   PageOrientation? orientation,
  ///   EdgeInsetsGeometry? margin,
  ///   TextDirection? textDirection,
  /// })
  /// ```
  /// où `typedef BuildListCallback = List<Widget> Function(Context context)`
  /// (pub cache : `pdf-3.13.0/lib/src/widgets/page.dart`). Le débordement
  /// sur plusieurs pages est automatique : `generate()` calcule l'espace
  /// libre restant par page et crée une nouvelle page dès qu'un widget ne
  /// tient plus, jusqu'à `maxPages` (20 par défaut).
  Future<Uint8List> textToPdf(String content) async {
    final document = pw.Document();
    final lines = content.split('\n');

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) => [
          for (final line in lines)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Text(line),
            ),
        ],
      ),
    );

    return document.save();
  }
}
