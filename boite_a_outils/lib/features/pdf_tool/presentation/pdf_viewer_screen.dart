import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';

/// Écran de visualisation d'un PDF (généré par l'app ou importé depuis le
/// téléphone) via le lecteur natif `flutter_pdfview`.
///
/// Paramètres du widget [PDFView] vérifiés dans le code source installé
/// (`flutter_pdfview-1.4.5/lib/src/pdf_view.dart` et `.../src/types.dart`) :
/// `filePath`, `onRender` (`void Function(int? pages)`), `onError`
/// (`void Function(dynamic error)`), `onPageError`
/// (`void Function(int? page, dynamic error)`).
class PdfViewerScreen extends StatefulWidget {
  const PdfViewerScreen({super.key, required this.filePath});

  /// Chemin local du fichier PDF à afficher.
  final String filePath;

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  String? _errorMessage;
  int? _pageCount;

  String get _fileName => widget.filePath.split(Platform.pathSeparator).last;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_fileName),
        bottom: _pageCount != null
            ? PreferredSize(
                preferredSize: const Size.fromHeight(20),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '$_pageCount page(s)',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              )
            : null,
      ),
      body: _errorMessage != null ? _buildError() : _buildViewer(),
    );
  }

  Widget _buildViewer() {
    return PDFView(
      filePath: widget.filePath,
      onRender: (pages) {
        setState(() => _pageCount = pages);
      },
      onError: (error) {
        setState(() {
          _errorMessage = "Impossible d'ouvrir ce PDF : $error";
        });
      },
      onPageError: (page, error) {
        setState(() {
          _errorMessage = 'Erreur lors de l\'affichage de la page $page : $error';
        });
      },
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ),
      ),
    );
  }
}
