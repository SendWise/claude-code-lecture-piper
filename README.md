# lecture-piper

Écouter en vocal français, **en local**, la dernière réponse de Claude Code, tout en gardant le texte affiché à l'écran.

Vous tapez `lecture-piper` comme message dans Claude Code : la réponse précédente est lue à voix haute par [Piper TTS](https://github.com/rhasspy/piper). Aucun texte n'est envoyé à un service tiers, aucun token n'est consommé (le message n'atteint jamais le modèle).

Conçu et testé sur **Windows + WSL/Ubuntu 24.04**, Claude Code 2.1.x.

## Pourquoi

Lire de longs textes à l'écran n'est pas confortable pour tout le monde. Les extensions navigateur de lecture vocale envoient le texte à des serveurs distants ; `espeak-ng` reste local mais donne une voix robotique. Piper offre une voix neuronale correcte, 100 % hors ligne.

## Prérequis

- Windows avec WSL 2 et une distribution Ubuntu (testé sur 24.04)
- Claude Code installé et fonctionnel dans WSL
- `powershell.exe` accessible depuis WSL (c'est le cas par défaut) : WSL n'ayant pas de carte son ALSA, le `.wav` est joué côté Windows
- Paquets : `jq`, `python3-venv`, `wget` (`setsid`, `sed`, `grep`, `find`, `pkill` sont déjà présents)

```bash
sudo apt update && sudo apt install -y jq python3-venv wget
```

## Installation

### 1. Cloner le dépôt

```bash
git clone https://github.com/SendWise/claude-code-lecture-piper.git
cd claude-code-lecture-piper
```

Le clone est recommandé plutôt qu'un copier-coller depuis une page web : les scripts contiennent des blocs `sed` multilignes qui se cassent facilement au collage.

### 2. Installer Piper dans un environnement virtuel dédié

```bash
python3 -m venv "$HOME/piper-venv"
"$HOME/piper-venv/bin/pip" install piper-tts
```

Testé avec `piper-tts` 1.7.0.

### 3. Récupérer la voix française

```bash
mkdir -p "$HOME/piper-voices"
cd "$HOME/piper-voices"
wget https://huggingface.co/rhasspy/piper-voices/resolve/main/fr/fr_FR/siwis/medium/fr_FR-siwis-medium.onnx
wget https://huggingface.co/rhasspy/piper-voices/resolve/main/fr/fr_FR/siwis/medium/fr_FR-siwis-medium.onnx.json
cd -
```

Les **deux** fichiers sont nécessaires : le `.onnx` est le modèle, le `.onnx.json` décrit sa configuration. Le script attend le chemin complet du `.onnx`, pas le nom court de la voix.

D'autres voix françaises existent (`fr_FR-upmc-medium`, `fr_FR-gilles-low`) : voir le [catalogue des voix Piper](https://huggingface.co/rhasspy/piper-voices).

### 4. Installer les scripts

```bash
cp scripts/lecture-piper.sh "$HOME/lecture-piper.sh"
cp scripts/hook-userpromptsubmit.sh "$HOME/.claude/hook-userpromptsubmit.sh"
chmod +x "$HOME/lecture-piper.sh" "$HOME/.claude/hook-userpromptsubmit.sh"
```

### 5. Déclarer le hook

Dans `~/.claude/settings.json`, ajouter le bloc `hooks` (voir `examples/settings.hooks.json` pour un fichier complet) :

```json
"hooks": {
  "UserPromptSubmit": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "$HOME/.claude/hook-userpromptsubmit.sh",
          "timeout": 10
        }
      ]
    }
  ]
}
```

Deux points de vigilance :

- `timeout` est un champ **du handler de hook**, pas une option globale. Placé à la racine du fichier, il est silencieusement ignoré.
- Si le hook ne se déclenche pas, remplacer `$HOME` par le chemin absolu (`/home/votre-utilisateur/.claude/hook-userpromptsubmit.sh`).

Vérifier la validité du fichier : `jq . ~/.claude/settings.json`

### 6. Tester

Hors de Claude Code, directement :

```bash
~/lecture-piper.sh "Bonjour, ceci est un test de lecture vocale."
```

Puis dans Claude Code : poser une question, attendre la réponse, envoyer `lecture-piper` comme message unique. Le message jaune « Lecture audio lancee. » confirme le déclenchement.

## Utilisation

| Action | Comment |
| --- | --- |
| Lire la dernière réponse | envoyer `lecture-piper` seul comme message |
| Interrompre / relancer | renvoyer `lecture-piper` : la lecture en cours est coupée net |
| Lire un texte arbitraire | `~/lecture-piper.sh "votre texte"` |

Le déclencheur est sensible à la casse et doit être le message entier (les espaces autour sont tolérés). `Lecture-piper` ou `lecture-piper stp` passent au modèle normalement.

## Configuration

Toutes les variables se surchargent par l'environnement, sans modifier les scripts :

| Variable | Défaut | Rôle |
| --- | --- | --- |
| `PIPER_BIN` | `$HOME/piper-venv/bin/piper` | binaire Piper |
| `PIPER_MODEL` | `$HOME/piper-voices/fr_FR-siwis-medium.onnx` | fichier de modèle de voix |
| `WAV_OUT` | `$HOME/claude_voice.wav` | fichier audio temporaire |
| `PIPER_LENGTH_SCALE` | `1.0` | vitesse : < 1 accélère, > 1 ralentit |

`PIPER_LENGTH_SCALE` agit sur la synthèse elle-même, pas sur une accélération audio brute : l'intonation reste naturelle.

## Comment ça marche

1. Le hook `UserPromptSubmit` reçoit le message sur son entrée standard et le compare à `lecture-piper`.
2. Si ça correspond, il lance `lecture-piper.sh` dans une **session détachée** (`setsid`, tous les descripteurs redirigés) puis retourne `exit 2`, ce qui bloque l'envoi au modèle.
3. `lecture-piper.sh` récupère le texte : soit l'argument passé, soit la dernière réponse assistant du fichier `.jsonl` de transcription le plus récent dans `~/.claude/projects`.
4. Le texte est nettoyé par `sed` (markdown, heures, dates, symboles) avant synthèse : zéro coût en tokens.
5. Piper génère le `.wav`, `powershell.exe` le joue via `Media.SoundPlayer`.

Le détachement est le point critique : `PlaySync()` est bloquant, et sans `setsid` + redirection des descripteurs, le hook attendait la fin de la lecture complète et expirait au bout de 30 s sur les textes longs. Un simple `&` ne suffit pas, le processus fils héritant du `stdout` du hook. Avec le détachement, le hook rend la main en ~25 ms quelle que soit la longueur du texte.

Les alternatives écartées et le détail du raisonnement sont dans [`docs/choix-techniques.md`](docs/choix-techniques.md).

## Comportements connus et limites

- **En début de session, `lecture-piper` relit la dernière réponse de la session précédente.** Le script cherche le `.jsonl` le plus récent dans tout `~/.claude/projects`, sans filtrer sur la session courante. Comportement volontairement conservé, sans danger, mais surprenant.
- **Le filet `pkill -f claude_voice.wav` dépend du nom du fichier.** Si vous changez `WAV_OUT`, ce garde-fou (contre une lecture orpheline après un arrêt brutal de WSL) ne fonctionne plus.
- **Dates : le jour et le mois doivent faire deux chiffres.** `08/09` est lu « 8 septembre », `8/9` est laissé tel quel. Contrainte assumée : sans elle, `3/4` deviendrait « 3 avril ». Les dates au format américain `MM/JJ` seraient inversées.
- **Chiffres romains non traités** : « XIXe siècle » est prononcé comme un mot. Un correctif d'exemple figure dans `docs/choix-techniques.md`.
- **Pas de pause/reprise**, `PlaySync()` n'étant pas pilotable.
- Le comportement des hooks Claude Code varie selon les versions et l'interface (CLI, VSCode). Tester en isolation avant de conclure :
  ```bash
  echo '{"prompt":"lecture-piper"}' | ~/.claude/hook-userpromptsubmit.sh; echo "exit=$?"
  ```

## Dépannage

| Symptôme | Piste |
| --- | --- |
| `UserPromptSubmit hook timed out after 30s` | le détachement `setsid` ou la redirection des descripteurs est absente du hook |
| Claude répond « je ne comprends pas » | le hook n'est pas déclenché : vérifier le chemin dans `settings.json` et le bit exécutable |
| Deux voix superposées | PID file corrompu ou processus PowerShell orphelin : `pkill -f claude_voice.wav` |
| Aucun son | tester `powershell.exe -c "[console]::beep(800,300)"` depuis WSL |
| Erreur de modèle introuvable | vérifier que `PIPER_MODEL` pointe vers un `.onnx` existant, et que le `.onnx.json` est à côté |
| Journal | `~/.claude/lecture-piper.log` |

## Licence

MIT, voir [LICENSE](LICENSE).
