# SuperVolume

Les touches volume du Mac ne marchent pas sur un périphérique à sortie multiple (Audio MIDI + BlackHole…).
SuperVolume les fait fonctionner : même principe que « Super Volume Keys » de SoundSource, en open source.

- App barre de menus, ~1 Mo, Swift natif, binaire universel (Apple Silicon + Intel), macOS 13+
- Touches volume + / − / mute interceptées **uniquement** quand la sortie n'a pas de volume natif ; sinon macOS garde la main
- Suit la sortie active, ou force un périphérique de ton choix
- Pilote chaque sous-périphérique du multi-sortie (case à cocher par périphérique)
- `Option + Maj` : pas fins (1/64)
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
