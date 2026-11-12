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
- **Copie vers un périphérique virtuel** : l'app joue sur ta sortie active (casque, enceintes…) **et** part en parallèle
  vers BlackHole à 100 %, même quand tu changes de sortie. Plus besoin de multi-sortie pour diffuser dans une visio
- Mises à jour automatiques (Sparkle) + « Rechercher des mises à jour… »

<img width="693" height="639" alt="image" src="https://github.com/user-attachments/assets/b9ce4b3e-59f0-49d3-85e3-dcef6da76d7b" />

## Cas d'usage

### 1. Retrouver les touches volume sur un multi-sortie
Tu as créé un « Périphérique à sortie multiple » (enceintes + BlackHole, par exemple) et les touches volume sont
grisées. Active SuperVolume : elles règlent chaque sous-périphérique du groupe, avec le HUD habituel.
Avec les enceintes seules, macOS garde la main, SuperVolume ne s'en mêle pas.

### 2. Envoyer la musique dans une visio (WorkAdventure, Teams, Meet…) sans le reste
Tu veux que les autres entendent Spotify à 100 %, mais pas YouTube ni les notifications, et tu veux l'entendre toi
aussi, sur ta sortie du moment : enceintes, ou casque dès qu'il est branché (Bluetooth compris).

1. SuperVolume → « Routage des apps » → Spotify → **« Défaut du Mac (volume réglable) »**.
2. Même sous-menu → « Copier aussi vers » → **BlackHole 2ch**.
3. Laisse BlackHole à **1,0** (`SuperVolume --set-device BlackHole 1.0`) : c'est le niveau que reçoivent les autres.
4. Le curseur « Volume local » de Spotify règle ce que **toi** tu entends ; la copie vers BlackHole reste à 100 %.

```
Spotify ─┬─► sortie active du Mac (casque / enceintes)  volume local → toi
         └─► BlackHole 2ch                              100 %, fixe  → la visio
Chrome, YouTube… ──► sortie active du Mac seulement
```

Côté visio :

| Réglage | Valeur |
|---|---|
| Entrée de diffusion (ex. WorkAdventure → Jam Spotify → « Entrée audio ») | **BlackHole 2ch** |
| Micro pour parler | **Micro MacBook Pro** (voir ci-dessous) |
| Haut-parleur | **Par défaut** (suit la sortie du Mac) |
| À ne jamais faire | choisir BlackHole comme haut-parleur : la voix des autres repartirait dans la diffusion |

> **Casque Bluetooth** : dès qu'une app (Teams, la visio) utilise son micro, le casque passe en mode « appel »
> (16 kHz mono) et ton écoute se dégrade. Prends le micro du Mac dans tes visios pour le garder en stéréo.
>
> **Pourquoi pas un multi-sortie Audio MIDI ?** Ses sous-périphériques sont figés : avec « enceintes + BlackHole »,
> Spotify reste sur les enceintes même quand ton casque est la sortie active.
>
> Pour un outil qui n'a qu'une seule entrée (Teams, Meet) : choisir BlackHole comme micro coupe ta voix. Pour parler
> **et** diffuser, crée dans Audio MIDI un périphérique agrégé (micro + BlackHole 2ch) et choisis-le comme entrée.

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
d'origine et la rejoue sur la destination. Pour l'entendre sur ta sortie **et** l'envoyer dans BlackHole, utilise
« Copier aussi vers » : la copie part à 100 % vers un périphérique virtuel, en plus de la destination. Elle survit
aux changements de sortie ; si la copie est débranchée, la destination continue seule. La permission « Capture audio » est demandée au premier routage.
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
