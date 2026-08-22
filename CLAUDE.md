# Boîte à Outils

## Vue d'ensemble

Application mobile Flutter (iOS + Android) qui regroupe plusieurs outils utilitaires sous une interface **simple et intuitive**. Structure "feature-first" : chaque outil vit dans son propre module sous `lib/features/<outil>/`, en suivant la séparation View / ViewModel / Repository / Service recommandée par le [guide d'architecture officiel Flutter](https://docs.flutter.dev/app-architecture). Cette convention de dossiers par feature est une pratique communautaire répandue, pas une prescription officielle de Flutter — seule la séparation en couches l'est.

## Stack technique

- **Flutter (Dart)** — un seul codebase pour iOS et Android
- **Gestion d'état** : à trancher au moment du scaffold (Provider ou Riverpod), pas encore figé
- **Aucun backend** pour le MVP — tout le traitement (conversion, lecture PDF) se fait localement sur l'appareil

## Premier outil : Convertisseur & Visualiseur PDF

Convertit des fichiers en PDF et permet de les visualiser directement dans l'app.

### Portée v1

- **Entrées supportées** : images (JPG/PNG) et fichiers texte/markdown (.txt/.md)
  - HEIC (format par défaut des photos iPhone) **explicitement exclu de la v1** : ni `pw.MemoryImage` (package `pdf`) ni `package:image` (dont il dépend pour le décodage) ne savent décoder le HEIC — vérifié dans le code source en Phase 2. Le sélecteur de fichiers n'affiche que `.jpg/.jpeg/.png`, un HEIC n'apparaît donc même pas comme option. Réévaluer si un besoin réel apparaît (nécessiterait un package de décodage HEIC dédié).
- **Sortie** : PDF généré localement, prévisualisable et partageable
- **Visualisation** : tout PDF (généré par l'app ou importé depuis le téléphone) s'ouvre dans un lecteur intégré
- Hors périmètre v1 : conversion de fichiers Office (docx/xlsx/pptx) — nécessiterait un moteur de rendu ou un service cloud, reporté à une version ultérieure

### Flux utilisateur (implémenté)

1. Écran d'accueil → carte "Convertisseur PDF"
2. Un seul point d'entrée principal : bouton "Convertir un fichier" → un unique sélecteur natif filtré sur `jpg/jpeg/png/txt/md`, **sélection multiple activée** (comportement par défaut de `FilePicker.pickFiles` en v12). Le type est déduit du nom de fichier après sélection (pas de champ `extension` dans l'API `file_picker` installée — vérifié en Phase 4) et route vers la bonne conversion :
   - Plusieurs images (ou une seule) sélectionnées → **combinées en un seul PDF**, une image par page, dans l'ordre de sélection.
   - Un seul fichier texte sélectionné → converti seul.
   - Mélange images+texte, ou plusieurs fichiers texte à la fois → message d'erreur clair expliquant l'alternative (pas de plantage).
3. Génération du PDF (texte mis en page automatiquement sur plusieurs pages via `pw.MultiPage`)
4. États visuels explicites : indicateur de chargement pendant la génération, bannière + SnackBar de confirmation au succès, message d'erreur clair (y compris un message dédié si un HEIC est détecté)
5. Depuis l'écran de résultat : "Voir le PDF" (lecteur intégré), "Aperçu / Imprimer", "Partager" (feuille de partage OS) et **"Télécharger"** (boîte "Enregistrer sous" native via `FilePicker.saveFile` — l'utilisateur choisit l'emplacement : Téléchargements, Fichiers, Drive…)
6. Action secondaire distincte "Ouvrir un PDF existant" : permet d'ouvrir n'importe quel PDF du téléphone (pas seulement ceux générés par l'app) dans le même lecteur intégré

### Packages retenus

| Rôle | Package | Version (à revérifier au moment du scaffold) | Licence |
|---|---|---|---|
| Génération PDF | `pdf` | 3.13.0 | Apache-2.0 |
| Aperçu / partage / impression | `printing` | 5.15.0 | Apache-2.0 (même écosystème que `pdf`) |
| Sélection de fichiers | `file_picker` | 12.0.0 (API v12, breaking change récent) | MIT |
| Lecteur PDF | `flutter_pdfview` | 1.4.5 | MIT |

`syncfusion_flutter_pdfviewer` et `pdfx` ont été évalués et écartés pour la v1 : Syncfusion impose l'enregistrement d'une clé de licence même en usage gratuit (conditions d'éligibilité communautaire) ; `flutter_pdfview` couvre le besoin mobile-only (Android/iOS) sans cette friction. `pdfx` reste une option de repli si le support desktop/web devient nécessaire.

Détail complet de la recherche documentaire et plan d'implémentation phasé : [`plans/01-pdf-converter-viewer.md`](plans/01-pdf-converter-viewer.md).

## État actuel

**Feature 1 (Convertisseur & Visualiseur PDF) implémentée et vérifiée**, y compris son amélioration post-v1 (sélection multiple d'images + téléchargement, Phase 5) — chaque phase (1 à 5 + vérification finale) a eu une vérification indépendante (analyze, tests, greps anti-patterns, builds réels) qui a confirmé les affirmations de l'agent d'implémentation plutôt que de les prendre pour acquises.

- Projet Flutter dans `boite_a_outils/` (structure feature-first : `lib/core/`, `lib/features/pdf_tool/{data,presentation}/`)
- `flutter analyze` et `flutter test` (3 tests) : clean
- Build Android release réussi (`app-release.apk`, 61.1MB)
- Build iOS **non vérifié dans cet environnement** (host Windows — `flutter build` n'expose même pas la sous-commande `ios` sans macOS). À vérifier sur un Mac avant toute publication iOS.
- Test manuel du parcours complet sur appareil/émulateur réel : **pas encore fait** (pas d'émulateur disponible dans cet environnement de dev) — à faire avant de considérer la feature prête pour un usage réel.

### Backlog connu (non bloquant)
- `_convert()` dans `pdf_tool_screen.dart` appelle `setState` dans ses branches d'erreur sans guard `mounted` local — sûr aujourd'hui (aucun `await` dans ces branches précises) mais fragile si un futur edit y ajoute un appel asynchrone. À durcir en faisant remonter l'erreur à l'appelant plutôt que d'appeler `setState` depuis `_convert` lui-même.
- Icône de succès en `Colors.green` codé en dur plutôt qu'un token de thème.
- Portée HEIC à réévaluer si un besoin réel apparaît (voir section ci-dessus).

Prochaine étape suggérée : test manuel sur émulateur/appareil, puis planifier le 2e outil de la boîte à outils.
