# Plan 01 — Convertisseur & Visualiseur PDF (première feature de Boîte à Outils)

Décisions verrouillées avec l'utilisateur avant ce plan :
- Stack : **Flutter** (iOS + Android, un seul codebase)
- Portée v1 de la conversion : **images (JPG/PNG/HEIC) + fichiers texte/markdown → PDF**. Les formats Office (docx/xlsx/pptx) et "n'importe quel fichier" sont explicitement hors périmètre v1.

Chaque phase est conçue pour être exécutée dans un nouveau contexte de chat, en s'appuyant sur `CLAUDE.md` (résumé produit/app) et ce fichier (référence technique).

---

## Phase 0 — Documentation Discovery (fait)

Recherche menée sur pub.dev / GitHub / docs.flutter.dev / syncfusion.com. Résumé consolidé ci-dessous ; **ne pas re-planifier cette recherche**, seulement revérifier les numéros de version au moment du scaffold (Phase 1) car ils évoluent vite.

### Allowed APIs (citer ces sources, ne pas inventer d'API)

**Génération PDF — package `pdf` (DavBfr), v3.13.0, Apache-2.0** — https://pub.dev/packages/pdf
```dart
import 'package:pdf/widgets.dart' as pw;

final pdf = pw.Document();
pdf.addPage(pw.Page(
  pageFormat: PdfPageFormat.a4,
  build: (pw.Context context) => pw.Center(child: pw.Text('Hello World')),
));
final bytes = await pdf.save(); // Uint8List
```
Image dans une page : `pw.MemoryImage(File(path).readAsBytesSync())` → `pw.Image(image)`.

⚠️ **Anti-pattern guard** : la signature exacte de `pw.MultiPage` (nécessaire pour faire couler du texte long sur plusieurs pages) **n'a pas été vérifiée** par la recherche Phase 0. Avant de l'utiliser en Phase 2, ouvrir https://pub.dev/documentation/pdf/latest/widgets/MultiPage-class.html (ou l'API doc locale du package une fois installé) et confirmer les paramètres réels — ne pas deviner la signature.

**Aperçu / partage / impression — package `printing`, v5.15.0, Apache-2.0** — https://pub.dev/packages/printing
```dart
await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => doc.save());
await Printing.sharePdf(bytes: await doc.save(), filename: 'my-document.pdf');
// Widget de preview intégrable dans un écran :
PdfPreview(build: (format) => doc.save());
```

**Sélection de fichiers — package `file_picker`, v12.0.0 (API breaking récente), MIT** — https://pub.dev/packages/file_picker
```dart
final images = await FilePicker.pickFiles(type: FileType.image);
final texts = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['txt', 'md']);
```
⚠️ v12 retourne une `List<PlatformFile>` **vide** en cas d'annulation (pas `null`). Les anciens exemples en ligne utilisant `FilePicker.platform.pickFiles()` → `FilePickerResult?` correspondent à une API pré-v12 : **ne pas mélanger les deux styles**.

**Lecteur PDF — package `flutter_pdfview`, v1.4.5, MIT, Android+iOS uniquement** — https://pub.dev/packages/flutter_pdfview
```dart
import 'package:flutter_pdfview/flutter_pdfview.dart';

PDFView(
  filePath: path,
  onRender: (pages) => setState(() {}),
  onViewCreated: (controller) => _controller.complete(controller),
)
```

**Permissions**
- iOS : ajouter `NSPhotoLibraryUsageDescription` dans `Info.plist` (requis même pour le picker de `file_picker`). Ajouter `LSSupportsOpeningDocumentsInPlace` seulement si l'app doit éditer le fichier original in-place (pas nécessaire pour la v1, on ne fait que lire).
- Android : `file_picker` gère lui-même les permissions runtime via Storage Access Framework — **ne pas ajouter `permission_handler` ou de permissions manifest spéculativement**. N'ajouter `permission_handler` (v13.0.1) que si un flux personnalisé hors SAF/share-sheet devient nécessaire.

### Anti-patterns à éviter
- Ne pas utiliser `syncfusion_flutter_pdfviewer` pour la v1 (clé de licence à enregistrer, contraintes d'éligibilité communautaire) sauf besoin explicite de recherche texte/annotations.
- Ne pas assumer que `file_picker` décode le HEIC — c'est un simple sélecteur de fichier/octets, pas un transcodeur. Voir spike Phase 2.
- Ne pas ajouter de permissions Android/iOS "au cas où" — seulement celles requises par les packages effectivement utilisés.
- Ne pas mélanger l'API `file_picker` pré-v12 (`FilePicker.platform.pickFiles()` → nullable) avec l'API v12 (`FilePicker.pickFiles()` → liste non-nullable).

### Confiance / gaps restants
- Haute confiance : API `pdf`/`printing` de base, licences et plateformes de `flutter_pdfview`/`pdfx`, conditions Syncfusion.
- Confiance moyenne : numéros de version exacts (à reconfirmer via `flutter pub add <package>` en Phase 1, qui résout toujours la dernière version stable réelle).
- Gap à combler en Phase 2 : signature de `pw.MultiPage`, faisabilité du décodage HEIC.

---

## Phase 1 — Scaffold du projet Flutter

**Objectif** : projet Flutter qui compile et lance un écran d'accueil vide avec une carte "Convertisseur PDF" (non fonctionnelle à ce stade).

Tâches :
1. `flutter create boite_a_outils` (ou nom choisi) dans `C:\Users\antoa\projet\BoiteAOutil`.
2. Ajouter les dépendances via `flutter pub add pdf printing file_picker flutter_pdfview` — **laisser `flutter pub add` résoudre les versions réelles**, ne pas copier les numéros de version de la Phase 0 tels quels dans `pubspec.yaml`.
3. Créer la structure de dossiers feature-first :
   ```
   lib/
     core/            # widgets partagés, thème, routing
     features/
       pdf_tool/
         data/         # services de conversion, accès fichiers
         presentation/ # écrans, widgets
   ```
4. Écran d'accueil (`lib/core/home_screen.dart` ou équivalent) avec une grille/liste de cartes-outils ; une seule carte pour l'instant : "Convertisseur PDF" (navigation vers un écran placeholder).
5. Déclarer `NSPhotoLibraryUsageDescription` dans `ios/Runner/Info.plist`.

**Vérification** :
- `flutter analyze` sans erreur
- `flutter run` lance l'app sur un émulateur/simulateur et affiche l'écran d'accueil avec la carte PDF
- `pubspec.yaml` contient bien les 4 dépendances, versions résolues automatiquement

**Anti-pattern guard** : ne pas préremplir `pubspec.yaml` avec les numéros de version de la Phase 0 — ils datent de la recherche et peuvent être obsolètes.

---

## Phase 2 — Conversion (images + texte → PDF)

**Objectif** : depuis l'écran "Convertisseur PDF", sélectionner un ou plusieurs fichiers image/texte et générer un PDF local.

Tâches :
1. **Spike HEIC** (à faire en premier, avant le reste de la phase) : sélectionner un fichier HEIC via `file_picker`, vérifier si `pw.MemoryImage(bytes)` l'affiche correctement dans une page PDF. Si non, évaluer l'ajout du package `image` (decode HEIC → PNG/JPEG en mémoire) avant de le passer à `pw.MemoryImage`. Documenter le résultat dans ce fichier (mettre à jour cette section une fois vérifié).

   **Résultat (vérifié par lecture de code source, pas de test end-to-end device faute d'émulateur/fichier HEIC réel) :** `pw.MemoryImage` (pub cache `pdf-3.13.0/lib/src/widgets/image_provider.dart`) délègue le décodage à `image.findDecoderForData(bytes)` du package `image`, résolu en dépendance transitive à la version 4.9.2 (cf. `pubspec.lock`). La liste des décodeurs de `image-4.9.2/lib/src/formats/formats.dart` (`findDecoderForData`) est : JPEG, PNG, GIF, WebP, TIFF, PSD, EXR, BMP, PNM, TGA, ICO, PVR — **aucun décodeur HEIC/HEIF**. **HEIC n'est donc PAS supporté** par `pw.MemoryImage`/`package:image` dans les versions installées ; ajouter un package de décodage HEIC dédié serait nécessaire pour le supporter et est explicitement hors périmètre v1. Contre-mesure retenue (implémentée en Phase 2) : `PdfToolScreen` utilise `FileType.custom, allowedExtensions: ['jpg','jpeg','png']` (au lieu de `FileType.image`, qui inclut le HEIC natif iOS) pour que l'utilisateur ne puisse tout simplement pas sélectionner un fichier HEIC — plus simple et plus sûr qu'un message d'erreur après une conversion échouée.
2. **Vérifier `pw.MultiPage`** dans la doc API du package `pdf` installé (`flutter pub deps` puis doc locale, ou https://pub.dev/documentation/pdf/latest/) avant de l'utiliser pour le texte long.

   **Résultat (vérifié en lisant `pdf-3.13.0/lib/src/widgets/multi_page.dart`) :**
   ```dart
   MultiPage({
     PageTheme? pageTheme,
     PdfPageFormat? pageFormat,
     required BuildListCallback build,
     MainAxisAlignment mainAxisAlignment = MainAxisAlignment.start,
     CrossAxisAlignment crossAxisAlignment = CrossAxisAlignment.start,
     BuildCallback? header,
     BuildCallback? footer,
     ThemeData? theme,
     int maxPages = 20,
     PageOrientation? orientation,
     EdgeInsetsGeometry? margin,
     TextDirection? textDirection,
   })
   ```
   où `typedef BuildListCallback = List<Widget> Function(Context context)` (`pdf-3.13.0/lib/src/widgets/page.dart`).
3. Implémenter `lib/features/pdf_tool/data/pdf_conversion_service.dart` :
   - `Future<Uint8List> imagesToPdf(List<String> imagePaths)` — une image par page, en suivant le snippet Allowed APIs ci-dessus.
   - `Future<Uint8List> textToPdf(String content)` — utiliser `pw.MultiPage` (signature vérifiée à l'étape 2) pour gérer le débordement sur plusieurs pages.
4. Écran de sélection : bouton "Choisir des fichiers" → `file_picker` (API v12, cf. snippet Allowed APIs) filtré sur images et `.txt`/`.md`.
5. Après génération, sauvegarder les bytes dans un fichier local (`path_provider` pour le dossier documents de l'app — **à ajouter aux dépendances si pas déjà présent**, vérifier sur pub.dev avant usage) et proposer `Printing.sharePdf` / `Printing.layoutPdf` pour l'aperçu/partage natif.

**Vérification** :
- Convertir un JPG réel → fichier `.pdf` créé, s'ouvre correctement dans une visionneuse externe (ex. lecteur PDF du téléphone) pour confirmer que le PDF n'est pas corrompu
- Convertir un `.txt` de plusieurs pages → PDF multi-pages généré sans texte tronqué
- Cas HEIC : documenté comme fonctionnel ou comme limitation connue (avec message d'erreur clair côté UI si non supporté)
- `flutter analyze` sans erreur ; `grep -r "pw.MultiPage" lib/` correspond bien à la signature vérifiée en doc, pas à une signature devinée

---

## Phase 3 — Visualisation PDF

**Objectif** : ouvrir n'importe quel PDF (généré par l'app ou importé depuis le téléphone) dans un lecteur intégré.

Tâches :
1. Ajouter `flutter_pdfview` (déjà dans `pubspec.yaml` depuis Phase 1).
2. Créer `lib/features/pdf_tool/presentation/pdf_viewer_screen.dart` utilisant le widget `PDFView` (snippet Allowed APIs ci-dessus) — prend un `filePath` en paramètre de route.
3. Brancher la navigation :
   - Depuis l'écran de conversion (Phase 2), bouton "Voir le PDF" après génération → ouvre le viewer sur le fichier généré.
   - Ajouter une entrée "Ouvrir un PDF existant" sur l'écran de l'outil PDF, utilisant `file_picker` filtré sur `FileType.custom, allowedExtensions: ['pdf']` → ouvre le même viewer.

**Vérification** :
- Un PDF généré en Phase 2 s'ouvre et se feuillette (page suivante/précédente, zoom) dans le viewer
- Un PDF existant importé depuis le stockage du téléphone s'ouvre également
- `flutter analyze` sans erreur

---

## Phase 4 — Interface simple et intuitive (polish UX)

**Objectif** : le flux complet (accueil → sélection → conversion → aperçu/visualisation → partage) doit être compréhensible sans explication, en 2-3 taps.

Tâches :
1. Réduire l'écran outil PDF à un flux linéaire unique : un bouton principal clair ("Convertir un fichier") plutôt que plusieurs options concurrentes.
2. États visuels explicites : chargement pendant la génération PDF, message d'erreur clair si le format n'est pas supporté (ex. HEIC non décodable), confirmation visuelle une fois le PDF prêt.
3. Icônes/labels cohérents avec le thème Material par défaut de Flutter (pas de dépendance UI supplémentaire pour la v1).
4. Vérifier l'accessibilité de base : tailles de police lisibles, contraste suffisant, zones tactiles ≥ 44px.

**Vérification** :
- Parcours manuel complet : ouvrir l'app → convertir une image → visualiser le PDF → partager, sans blocage ni écran orphelin
- Aucun texte de debug ou placeholder restant à l'écran

---

## Phase 5 — Sélection multiple d'images + téléchargement (amélioration post-v1)

Décisions verrouillées avec l'utilisateur pour cette phase :
- Sélection multiple limitée aux **images** : plusieurs images sélectionnées → un seul PDF combiné, une image par page, dans l'ordre de sélection. Le mélange images+texte dans une même sélection et le multi-texte restent hors périmètre (message d'erreur clair si tenté).
- "Télécharger" = vraie boîte de dialogue "Enregistrer sous" (pas une réutilisation du bouton "Partager" existant).

### Allowed APIs (vérifiées en lisant le code source installé de `file_picker-12.0.0`, pas deviné)

**Sélection multiple** — `file_picker-12.0.0/lib/src/file_picker.dart:40` : `pickFiles()` a déjà `allowMultiple = true` par défaut (le paramètre est marqué `@Deprecated('use pickFile for single-file selection...')` — la sélection multiple est le comportement standard de `pickFiles`, il n'y a rien à activer). Le code actuel (Phase 4) appelle déjà `pickFiles` mais ne lit que `result.first` — il suffit de traiter `result` (la `List<PlatformFile>` entière).

**Enregistrer sous** — `file_picker-12.0.0/lib/src/file_picker.dart:217-238` :
```dart
static Future<Uri?> saveFile({
  required String fileName,
  required Uint8List bytes,
  String mimeType = 'application/octet-stream',
  String? dialogTitle,
  String? initialDirectory,
  FileType type = FileType.any,
  List<String>? allowedExtensions,
  Function(FilePickerStatus)? onFileSaving,
  // + options Windows/Linux/Web sans intérêt ici (mobile)
})
```
Retourne l'`Uri` du fichier enregistré, ou `null` si l'utilisateur annule. Doc du package : "Opens a save file dialog to let the user select a location and a file name to save [bytes] to."

### Tâches
1. `_pickAndConvert` : traiter toute la liste `result`, pas seulement `result.first`. Partitionner par extension (`_imageExtensions`/`_textExtensions`) :
   - Plusieurs images (ou une seule) et aucun texte → `imagesToPdf(paths)` avec tous les chemins, dans l'ordre de `result`.
   - Exactement un fichier texte et aucune image → flux `textToPdf` existant, inchangé.
   - Mélange images+texte dans la même sélection → erreur claire : "Mélanger images et texte dans une même sélection n'est pas pris en charge. Choisissez plusieurs images à combiner, ou un seul fichier texte."
   - Plusieurs fichiers texte → erreur claire : "Un seul fichier texte à la fois est pris en charge. Sélectionnez des images pour combiner plusieurs pages."
   - Un des fichiers sélectionnés a un `path` null → erreur claire nommant le fichier concerné, ne pas planter sur les autres.
   - Adapter le `dialogTitle` du picker pour mentionner la sélection multiple.
2. Ajouter un bouton "Télécharger" sur l'écran de succès (`_buildSuccess`), à côté de "Partager" : appelle `FilePicker.saveFile(fileName: ..., bytes: _generatedBytes!, mimeType: 'application/pdf', dialogTitle: 'Enregistrer le PDF sous...')`. Gérer le retour `null` (annulation, pas d'erreur affichée) vs un `Uri` non-null (confirmation visible, ex. SnackBar).
3. Mettre à jour les tests : `pdf_conversion_service_test.dart` (cas plusieurs images → PDF combiné, vérifier taille plausible en plus du header `%PDF`), `widget_test.dart` si le texte de l'écran idle change.

**Vérification** :
- `flutter analyze` sans erreur
- Tests : conversion de plusieurs images en un seul PDF combiné (vérifier `%PDF` + taille cohérente avec le nombre d'images)
- Cas d'erreur (mélange, multi-texte, path null) couverts par un message clair, pas de crash
- `grep -rn "FilePicker.platform.pickFiles" lib/` → vide (toujours l'API v12 statique)
- Parcours manuel (si device/émulateur disponible) : sélectionner 3 images → un PDF de 3 pages ; bouton Télécharger → boîte "Enregistrer sous" natif s'ouvre

---

## Phase finale — Vérification globale

1. `flutter analyze` sans erreur ni warning sur tout le projet.
2. `grep -r "FilePicker.platform.pickFiles" lib/` → doit être **vide** (confirme qu'on n'a pas mélangé l'API pré-v12 et v12 de `file_picker`).
3. `grep -r "SyncfusionLicense\|syncfusion_flutter_pdfviewer" lib/ pubspec.yaml` → doit être **vide** (confirme qu'on n'a pas dérivé vers Syncfusion en cours de route).
4. Build release à blanc pour les deux plateformes : `flutter build apk` et (si environnement macOS disponible) `flutter build ios --no-codesign`.
5. Test manuel du parcours complet sur un appareil/émulateur réel pour chaque OS cible.
6. Relire `CLAUDE.md` et le mettre à jour si le flux, les packages ou la portée ont changé pendant l'implémentation.
