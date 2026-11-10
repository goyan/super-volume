# SuperVolume

Les touches volume du Mac ne marchent pas sur un périphérique à sortie multiple (Audio MIDI + BlackHole…).
SuperVolume les fait fonctionner : même principe que « Super Volume Keys » de SoundSource, en open source.

- App barre de menus, ~1 Mo, Swift natif, binaire universel (Apple Silicon + Intel), macOS 14.2+
- Touches volume + / − / mute interceptées **uniquement** quand la sortie n'a pas de volume natif ; sinon macOS garde la main
- Suit la sortie active, ou force un périphérique de ton choix
- Pilote chaque sous-périphérique du multi-sortie (case à cocher par périphérique)
- `Option + Maj` : pas fins (1/64)
- **Routage par app** : envoie l'audio d'une app (Spotify…) vers n'importe quelle sortie, virtuelle (BlackHole) ou multi-sortie, mémorisé par app
- **Volume local par app** : curseur dans le menu, appliqué aux sorties locales seulement ; les périphériques virtuels (BlackHole) restent à 100 %
- Mises à jour automatiques (Sparkle) + « Rechercher des mises à jour… »

<img width="387" height="387" alt="image" src="https://github.com/user-attachments/assets/1686dca4-06c9-47d4-8dc6-41a35bf0d4f3" />

## Installation

1. Télécharge le `.dmg` dans les [Releases](https://github.com/goyan/super-volume/releases/latest) et glisse l'app dans `/Applications`.
2. L'app n'est pas notarisée : au premier lancement, clic droit → Ouvrir
   (ou `xattr -dr com.apple.quarantine /Applications/SuperVolume.app`).
3. Autorise **Accessibilité** (Réglages Système → Confidentialité et sécurité). Nécessaire pour intercepter les touches.

> La signature est ad-hoc : après une mise à jour, macOS peut redemander l'Accessibilité.

## Fonctionnement

À chaque appui, l'app regarde la sortie à piloter. Si macOS sait déjà régler son volume, la touche passe.
Sinon, SuperVolume règle le volume de chaque sous-périphérique du groupe (`VirtualMainVolume` via CoreAudio),
sans driver audio. Attention : un sous-périphérique comme BlackHole est atténué aussi, donc ce qui s'enregistre
depuis lui l'est également.

## Routage par app

Menu → « Routage des apps » → l'app → le périphérique de destination (ou « Défaut du Mac » pour défaire).
SuperVolume capte l'audio de l'app avec un *process tap* CoreAudio (macOS 14.2+, sans driver), coupe sa sortie
d'origine et la rejoue sur la destination. Pour l'entendre aux enceintes **et** dans BlackHole, route-la vers un
périphérique multi-sortie qui contient les deux. La permission « Capture audio » est demandée au premier routage.
Chaque app routée a un curseur « Volume local » : il baisse les enceintes sans toucher à ce que reçoit BlackHole.
« Défaut du Mac (volume réglable) » donne ce curseur à une app qui n'a pas de routage particulier.
Latence ajoutée : quelques dizaines de ms au plus.

## Build

```bash
./build.sh      # build/SuperVolume.app + build/SuperVolume-<version>.dmg
./release.sh    # publie la release GitHub (gh + clé Sparkle dans le trousseau)
```

Diagnostic sans les touches physiques :

```bash
SuperVolume --status                 # sortie, sous-périphériques, volumes
SuperVolume --set 0.5                # règle le volume
SuperVolume --post-key up|down|mute  # touche média synthétique
```

## Licence

MIT
