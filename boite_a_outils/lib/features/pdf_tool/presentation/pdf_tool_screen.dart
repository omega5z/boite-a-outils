import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';

import '../data/pdf_conversion_service.dart';
import 'pdf_viewer_screen.dart';

/// Écran de l'outil "Convertisseur PDF".
///
/// Phase 4 : flux réduit à un seul point d'entrée principal — un bouton
/// "Convertir un fichier" qui ouvre un unique `file_picker` filtré sur
/// jpg/jpeg/png/txt/md, puis choisit `imagesToPdf` ou `textToPdf`
/// (`PdfConversionService`) selon l'extension du/des fichier(s) choisi(s).
/// "Ouvrir un PDF existant" reste une action secondaire distincte (c'est de
/// la visualisation, pas de la conversion), visuellement en retrait
/// (`OutlinedButton`) par rapport au bouton principal (`FilledButton`).
///
/// Phase 5 : le picker autorise nativement la sélection multiple
/// (`pickFiles` a `allowMultiple = true` par défaut dans file_picker
/// 12.0.0 — vérifié en lisant `file_picker-12.0.0/lib/src/file_picker.dart`
/// avant d'écrire ce fichier). [_convertSelection] partitionne la liste
/// sélectionnée par extension : plusieurs images (aucun texte) → un seul
/// PDF combiné, une image par page, dans l'ordre de sélection ; exactement
/// un fichier texte (aucune image) → flux `textToPdf` inchangé ; mélange
/// images+texte ou plusieurs fichiers texte → erreur claire, pas de
/// combinaison partielle.
///
/// Note extension de fichier : `PlatformFile` (file_picker 12.0.0,
/// `file_picker_platform_interface-*/lib/src/platform_file.dart`) n'expose
/// **pas** de getter `extension` — seulement `name`, `uri`, `path`, `xFile`,
/// `length()`, `readAsBytes()`, `readAsByteStream()` (vérifié en lisant le
/// code source installé avant d'écrire ce fichier). L'extension est donc
/// dérivée manuellement du suffixe de `PlatformFile.name` par
/// [_extensionOf], jamais d'un champ `.extension` qui n'existe pas dans
/// cette version du package.
///
/// Note HEIC : le sélecteur unique utilise `FileType.custom` avec
/// `allowedExtensions: ['jpg', 'jpeg', 'png', 'txt', 'md']` — le HEIC n'y
/// figure jamais, donc l'utilisateur ne peut normalement pas le sélectionner
/// (voir KNOWN LIMITATION dans `pdf_conversion_service.dart` : ni
/// `pw.MemoryImage` ni `package:image`, dont il dépend, ne savent le
/// décoder). Un garde-fou défensif reste en place dans [_convertSelection]
/// au cas où une extension imprévue franchirait quand même le filtre du
/// picker sur une plateforme donnée.
class PdfToolScreen extends StatefulWidget {
  const PdfToolScreen({super.key});

  @override
  State<PdfToolScreen> createState() => _PdfToolScreenState();
}

enum _Status { idle, loading, success, error }

class _PdfToolScreenState extends State<PdfToolScreen> {
  final _conversionService = PdfConversionService();

  static const _imageExtensions = {'jpg', 'jpeg', 'png'};
  static const _textExtensions = {'txt', 'md'};

  _Status _status = _Status.idle;
  String? _errorMessage;
  String? _generatedFilePath;
  Uint8List? _generatedBytes;

  /// Dérive l'extension (en minuscules, sans le point) du nom de fichier,
  /// ou `null` si le nom n'en comporte pas. Voir la note de classe : il n'y
  /// a pas de getter `PlatformFile.extension` dans file_picker 12.0.0.
  String? _extensionOf(PlatformFile file) {
    final name = file.name;
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == name.length - 1) return null;
    return name.substring(dotIndex + 1).toLowerCase();
  }

  Future<void> _pickAndConvert() async {
    setState(() {
      _status = _Status.loading;
      _errorMessage = null;
    });

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'txt', 'md'],
        dialogTitle:
            'Choisir un ou plusieurs fichiers à convertir (images à '
            'combiner, ou un seul fichier texte)',
      );

      if (!mounted) return;

      if (result.isEmpty) {
        setState(() => _status = _Status.idle);
        return;
      }

      final converted = await _convertSelection(result);
      if (!mounted || converted == null) return;

      await _saveAndShow(converted.bytes, converted.kind);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _Status.error;
        _errorMessage = 'Échec de la conversion : $e';
      });
    }
  }

  /// Partitionne la sélection (potentiellement multiple depuis la Phase 5)
  /// par extension et route vers la bonne conversion. Retourne `null` (après
  /// avoir déjà mis à jour l'état d'erreur avec un message clair) si la
  /// sélection n'est pas convertible :
  /// - un des fichiers a un `path` null (accès refusé par la plateforme) ;
  /// - un format n'est pas reconnu (garde-fou défensif, le picker filtre
  ///   déjà sur jpg/jpeg/png/txt/md) ;
  /// - la sélection mélange images et texte ;
  /// - plusieurs fichiers texte sont sélectionnés à la fois.
  ///
  /// Sinon : une ou plusieurs images (aucun texte) → un seul PDF combiné via
  /// `imagesToPdf`, une image par page, dans l'ordre de sélection. Exactement
  /// un fichier texte (aucune image) → flux `textToPdf` existant, inchangé.
  Future<({String kind, Uint8List bytes})?> _convertSelection(
    List<PlatformFile> files,
  ) async {
    for (final file in files) {
      if (file.path == null) {
        setState(() {
          _status = _Status.error;
          _errorMessage =
              "Impossible d'accéder au fichier sélectionné : ${file.name}.";
        });
        return null;
      }
    }

    final images = <PlatformFile>[];
    final texts = <PlatformFile>[];
    final unsupported = <PlatformFile>[];

    for (final file in files) {
      final extension = _extensionOf(file);
      if (extension != null && _imageExtensions.contains(extension)) {
        images.add(file);
      } else if (extension != null && _textExtensions.contains(extension)) {
        texts.add(file);
      } else {
        unsupported.add(file);
      }
    }

    if (unsupported.isNotEmpty) {
      final extension = _extensionOf(unsupported.first);
      if (extension == 'heic' || extension == 'heif') {
        setState(() {
          _status = _Status.error;
          _errorMessage =
              'Format HEIC/HEIF non pris en charge : ce format de photo '
              "(par défaut sur iPhone) ne peut pas être décodé par l'outil "
              'de conversion. Convertissez la photo en JPG ou PNG puis '
              'réessayez.';
        });
      } else {
        setState(() {
          _status = _Status.error;
          _errorMessage =
              'Format de fichier non pris en charge'
              '${extension != null ? ' (.$extension)' : ''}. '
              'Formats acceptés : images JPG/PNG ou texte .txt/.md.';
        });
      }
      return null;
    }

    if (images.isNotEmpty && texts.isNotEmpty) {
      setState(() {
        _status = _Status.error;
        _errorMessage =
            'Mélanger images et texte dans une même sélection n\'est pas '
            'pris en charge. Choisissez plusieurs images à combiner, ou un '
            'seul fichier texte.';
      });
      return null;
    }

    if (texts.length > 1) {
      setState(() {
        _status = _Status.error;
        _errorMessage =
            'Un seul fichier texte à la fois est pris en charge. '
            'Sélectionnez des images pour combiner plusieurs pages.';
      });
      return null;
    }

    if (images.isNotEmpty) {
      final paths = images.map((file) => file.path!).toList();
      final bytes = await _conversionService.imagesToPdf(paths);
      if (!mounted) return null;
      return (kind: 'images', bytes: bytes);
    }

    final content = await File(texts.single.path!).readAsString();
    if (!mounted) return null;
    final bytes = await _conversionService.textToPdf(content);
    return (kind: 'texte', bytes: bytes);
  }

  Future<void> _saveAndShow(Uint8List bytes, String kind) async {
    final directory = await getApplicationDocumentsDirectory();
    if (!mounted) return;

    final filename =
        'conversion_${kind}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final file = File('${directory.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    if (!mounted) return;

    setState(() {
      _status = _Status.success;
      _generatedFilePath = file.path;
      _generatedBytes = bytes;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('PDF généré avec succès.')),
    );
  }

  Future<void> _openExistingPdf() async {
    setState(() {
      _status = _Status.loading;
      _errorMessage = null;
    });

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        dialogTitle: 'Ouvrir un PDF existant',
      );

      if (!mounted) return;

      if (result.isEmpty) {
        setState(() => _status = _Status.idle);
        return;
      }

      final path = result.first.path;
      if (path == null) {
        setState(() {
          _status = _Status.error;
          _errorMessage = "Impossible d'accéder au fichier sélectionné.";
        });
        return;
      }

      setState(() => _status = _Status.idle);
      _openViewer(path);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _Status.error;
        _errorMessage = "Échec de l'ouverture du PDF : $e";
      });
    }
  }

  /// Bouton "Télécharger" (Phase 5) : ouvre une vraie boîte de dialogue
  /// "Enregistrer sous" native via `FilePicker.saveFile` — signature vérifiée
  /// dans `file_picker-12.0.0/lib/src/file_picker.dart:217-238` avant
  /// d'écrire cette méthode (`required String fileName`,
  /// `required Uint8List bytes`, retourne `Future<Uri?>`, `null` si
  /// l'utilisateur annule). Ce n'est délibérément pas une réutilisation du
  /// bouton "Partager" existant (`Printing.sharePdf`), qui ouvre la feuille
  /// de partage système plutôt qu'un sélecteur d'emplacement de fichier.
  Future<void> _downloadPdf() async {
    final bytes = _generatedBytes;
    if (bytes == null) return;

    final suggestedName =
        _generatedFilePath?.split(Platform.pathSeparator).last ??
            'document.pdf';

    try {
      final savedUri = await FilePicker.saveFile(
        fileName: suggestedName,
        bytes: bytes,
        mimeType: 'application/pdf',
        dialogTitle: 'Enregistrer le PDF sous...',
      );
      if (!mounted) return;

      if (savedUri != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF enregistré avec succès.')),
        );
      }
      // savedUri == null : l'utilisateur a annulé, rien à afficher.
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Échec de l'enregistrement du PDF : $e")),
      );
    }
  }

  void _openViewer(String path) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => PdfViewerScreen(filePath: path)),
    );
  }

  void _reset() {
    setState(() {
      _status = _Status.idle;
      _errorMessage = null;
      _generatedFilePath = null;
      _generatedBytes = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Convertisseur PDF')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    switch (_status) {
      case _Status.loading:
        return const _LoadingIndicator();
      case _Status.success:
        return _buildSuccess();
      case _Status.error:
      case _Status.idle:
        return _buildIdleOrError();
    }
  }

  Widget _buildIdleOrError() {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.picture_as_pdf, size: 64, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          'Convertissez une image (JPG/PNG) ou un texte (.txt/.md) en PDF, '
          'ou ouvrez un PDF existant.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        if (_errorMessage != null) ...[
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, color: theme.colorScheme.error),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _errorMessage!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        FilledButton.icon(
          onPressed: _pickAndConvert,
          icon: const Icon(Icons.upload_file),
          label: const Text('Convertir un fichier'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _openExistingPdf,
          icon: const Icon(Icons.picture_as_pdf),
          label: const Text('Ouvrir un PDF existant'),
        ),
        const SizedBox(height: 24),
        Text(
          'Le format HEIC (photos iPhone par défaut) n\'est pas pris en '
          'charge : convertissez-le en JPG/PNG avant import.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildSuccess() {
    final theme = Theme.of(context);
    final bytes = _generatedBytes!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_circle, color: Colors.green, size: 48),
        const SizedBox(height: 12),
        Text('PDF généré avec succès', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          _generatedFilePath ?? '',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () => _openViewer(_generatedFilePath!),
          icon: const Icon(Icons.picture_as_pdf),
          label: const Text('Voir le PDF'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => Printing.layoutPdf(onLayout: (_) async => bytes),
          icon: const Icon(Icons.visibility),
          label: const Text('Aperçu / Imprimer'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => Printing.sharePdf(
            bytes: bytes,
            filename: _generatedFilePath?.split(Platform.pathSeparator).last ??
                'document.pdf',
          ),
          icon: const Icon(Icons.share),
          label: const Text('Partager'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _downloadPdf,
          icon: const Icon(Icons.download),
          label: const Text('Télécharger'),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _reset,
          child: const Text('Convertir un autre fichier'),
        ),
      ],
    );
  }
}

/// Indicateur de chargement explicite affiché pendant la génération du PDF
/// (Phase 4, Tâche 2 : "un état de chargement pendant la génération").
class _LoadingIndicator extends StatelessWidget {
  const _LoadingIndicator();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(
          'Conversion en cours…',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}
