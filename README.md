# EasyLoger

<p align="center">
  <img src="EasySeloger/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" width="160" alt="Icône EasyLoger">
</p>

EasyLoger est une application SwiftUI pour macOS et iPadOS qui centralise et organise une recherche immobilière. Elle permet d’importer des annonces SeLoger, de compléter les informations importantes et de suivre chaque bien jusqu’à la visite.

## Fonctionnalités

- Import assisté d’une annonce SeLoger depuis son URL
- Ajout et modification manuels d’un bien
- Gestion des prix, surfaces, pièces, chambres et prix au mètre carré
- Classement par statut : à étudier, contact demandé, contacté, visite programmée, visité, à revisiter ou écarté
- Date de visite, coordonnées du contact et commentaires personnels
- Galerie de photos avec import de fichiers ou ajout par URL
- Favoris et filtre dédié
- Géocodage d’une adresse précise avec affichage sur Apple Plans
- Carte interactive en plein écran sur iPad par double-tap
- Ouverture de l’adresse dans Apple Plans sur macOS par double-clic
- Export et restauration de toutes les données au format JSON

## Technologies

- Swift et SwiftUI
- MapKit pour les cartes et le géocodage
- WebKit pour l’import assisté des annonces
- Observation pour la gestion de l’état
- Stockage local avec `UserDefaults` et fichiers JSON

## Prérequis

- Xcode 27 ou version ultérieure
- macOS 27 ou version ultérieure
- iPadOS 27 ou version ultérieure
- Un compte développeur Apple configuré dans Xcode pour l’installation sur un appareil physique

## Installation

1. Clonez le dépôt :

   ```bash
   git clone <URL_DU_DEPOT>
   cd EasyLoger
   ```

2. Ouvrez `EasyLoger.xcodeproj` dans Xcode.
3. Sélectionnez le target **EasyLoger**.
4. Configurez votre équipe de développement dans **Signing & Capabilities** si nécessaire.
5. Choisissez **My Mac** ou un iPad comme destination, puis lancez l’application.

## Utilisation

### Importer une annonce

Utilisez **Importer SeLoger**, saisissez ou collez l’URL de l’annonce, puis chargez la page. Après une éventuelle validation des cookies ou de la vérification du site, lancez l’import.

La structure des sites web peut évoluer. Si certaines informations ne sont pas détectées, elles peuvent être complétées manuellement dans EasyLoger.

### Utiliser la carte

Lorsqu’une localisation précise est renseignée, EasyLoger résout l’adresse et positionne le bien sur la carte.

- Sur iPad, effectuez un double-tap sur la carte pour l’afficher en plein écran.
- Sur macOS, effectuez un double-clic pour ouvrir l’adresse dans Apple Plans.

### Sauvegarder les données

Dans **Réglages**, utilisez **Exporter les données** pour créer une sauvegarde JSON. Cette sauvegarde contient les biens, favoris, commentaires, statuts et champs modifiés.

L’import d’une sauvegarde remplace les données actuellement présentes après confirmation.

## Données et confidentialité

Les biens, favoris et préférences sont conservés localement sur l’appareil. EasyLoger accède au réseau uniquement pour charger les annonces, les photos distantes et les services nécessaires à Apple Plans.

## Structure du projet

```text
EasySeloger/
├── Assets.xcassets/   # Icônes et couleurs
├── ContentView.swift  # Modèles, import, stockage et interface principale
└── MyApp.swift        # Point d’entrée de l’application
```

## Avertissement

EasyLoger est un outil indépendant et n’est ni affilié à SeLoger ni approuvé par SeLoger. Les marques et contenus tiers appartiennent à leurs propriétaires respectifs.
