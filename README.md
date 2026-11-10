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

<img width="693" height="639" alt="image" src="https://github.com/user-attachments/assets/b9ce4b3e-59f0-49d3-85e3-dcef6da76d7b" />

## Cas d'usage

### 1. Retrouver les touches volume sur un multi-sortie
Tu as créé un « Périphérique à sortie multiple » (enceintes + BlackHole, par exemple) et les touches volume sont
grisées. Active SuperVolume : elles règlent chaque sous-périphérique du groupe, avec le HUD habituel.
Avec les enceintes seules, macOS garde la main, SuperVolume ne s'en mêle pas.

### 2. Envoyer la musique dans une visio (WorkAdventure, Teams, Meet…) sans le reste
Tu veux que les autres entendent Spotify, mais pas YouTube ni les notifications, et tu veux l'entendre toi aussi.

1. Audio MIDI : crée un périphérique à sortie multiple avec tes enceintes **et** BlackHole 2ch.
2. SuperVolume → « Routage des apps » → Spotify → ce périphérique multi-sortie.
3. Dans l'outil de visio, choisis **BlackHole 2ch comme micro**.
4. Laisse BlackHole à **1,0** (Audio MIDI) : c'est le niveau que reçoivent les autres.
5. Menu → « Sortie à piloter » → **Suivre la sortie active du Mac** : les touches volume règlent tes enceintes
   sans toucher à BlackHole. Le curseur « Volume local » de Spotify règle ce que **toi** tu entends, indépendamment
   des autres apps.

```
Spotify ──► multi-sortie ─┬─► BlackHole   (100 %, fixe)  → la visio
                          └─► Enceintes   (volume local) → toi
Chrome, YouTube… ────────────► Enceintes seulement (défaut du Mac)
```

> La visio n'entend alors plus ton micro, puisque son entrée est BlackHole. Pour parler **et** diffuser, crée dans
> Audio MIDI un périphérique agrégé (micro + BlackHole 2ch) et choisis-le comme entrée.

### 3. Isoler une app pour un stream ou un enregistrement
Route l'app vers **BlackHole seul** : son audio quitte les enceintes et arrive uniquement dans OBS, QuickTime
ou ton outil de capture (source = BlackHole 2ch). Rien d'autre du Mac ne s'y mélange.

### 4. Régler le volume d'une app indépendamment des autres
Menu → l'app → **« Défaut du Mac (volume réglable) »**, puis le curseur « Volume local ». L'app reste sur ta sortie
habituelle, mais avec son propre volume : Chrome moins fort que Spotify, par exemple. Les touches volume restent
le réglage général.

### 5. Une app par périphérique
Spotify sur le casque, Teams sur les enceintes, un navigateur sur un écran HDMI : chaque app a sa destination,
mémorisée et réappliquée dès qu'elle rejoue du son. Si le périphérique est débranché, l'app retombe sur le défaut
du Mac.

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
depuis lui l'est également (à 0,34, le signal perd environ 33 dB). Si tu l'utilises comme source de capture ou
de visio, garde-le à 1,0 : décoche-le dans « Sous-périphériques pilotés », ou règle les touches sur les enceintes.

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
SuperVolume --status                       # sortie pilotée, sous-périphériques, volumes
SuperVolume --devices                      # toutes les sorties et la composition des multi-sorties
SuperVolume --procs                        # processus audio et clé d'app utilisée pour le routage
SuperVolume --set 0.5                      # règle le volume de la sortie pilotée
SuperVolume --set-device BlackHole 1.0     # règle le volume d'un périphérique précis
SuperVolume --post-key up|down|mute        # touche média synthétique
SuperVolume --route-test <clé> <périph> <s> [volume]   # route une app quelques secondes, affiche les niveaux
SuperVolume --listen <périph> <s>          # niveau reçu en entrée d'un périphérique (ex. BlackHole)
```

## Licence

MIT
