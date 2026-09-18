# Choix techniques et impasses

Ce document garde la trace du raisonnement, pas seulement du résultat. Il évite à quiconque reprend le projet de refaire les mêmes essais.

## Moteur vocal

| Piste | Verdict |
| --- | --- |
| Extensions navigateur (CastReader, ArticleAudio) | écartées : le texte part sur des serveurs tiers. ArticleAudio ne gère pas le français. |
| `espeak-ng` | 100 % local mais voix trop robotique à l'usage prolongé. |
| **Piper TTS** | retenu : voix neuronale, entièrement locale, français correct. |

## Mécanisme de déclenchement

Quatre approches testées avant d'arriver à une solution stable.

1. **Hook `Stop` avec vérification du dernier message.** Lit bien la réponse, mais si `lecture-piper` est envoyé seul, Claude Code le traite comme une vraie question et génère une réponse parasite (« je ne comprends pas »), qui se fait lire à la place du bon texte.
2. **Commande slash `/lecture-piper`.** Censée exécuter un script shell sans passer par le modèle ; en pratique Claude Code l'interprète comme un skill et invoque quand même le modèle. Tokens consommés, comportement imprévisible.
3. **Hook `UserPromptSubmit` avec `shouldProceed: false`.** La documentation présente ce champ comme bloquant. Sans effet dans la version testée (2.1.261) : le prompt était envoyé malgré tout.
4. **Hook `UserPromptSubmit` avec `exit 2`** — retenu. Le code de sortie 2 bloque effectivement l'envoi au modèle et affiche le message d'erreur du hook à l'écran, sans générer de réponse.

## Le timeout de 30 secondes

Symptôme initial : sur une réponse longue, `UserPromptSubmit hook timed out after 30s, output discarded`. Le `exit 2` n'ayant pas le temps de s'exécuter, `lecture-piper` repartait vers le modèle.

Cause réelle, plus large que l'hypothèse de départ : ce n'est pas la synthèse Piper qui dépassait 30 s, c'est `PlaySync()` qui est **bloquant**. Le hook attendait donc la fin de la lecture complète, quelle que soit la vitesse de Piper.

Ce que dit la [documentation des hooks](https://code.claude.com/docs/en/hooks) :

- `timeout` se configure par handler de hook, en secondes. Défaut 600 pour les hooks `command`, abaissé à 30 sur `UserPromptSubmit`.
- Un hook qui atteint son timeout est annulé et **sa sortie est jetée** : il ne rend aucune décision.
- `UserPromptSubmit` bloque le traitement du modèle jusqu'à la fin du hook.

Deux corrections écartées :

- **Augmenter le timeout** : possible, mais l'interface resterait gelée pendant toute la lecture. `timeout: 600` déplacerait le problème sans le résoudre.
- **`async: true`** : un hook asynchrone n'est pas attendu, donc son `exit 2` ne bloque plus rien. C'est l'inverse de l'effet recherché.

Solution retenue : détachement complet du processus de synthèse (`setsid` + `</dev/null >>"$LOG" 2>&1`), puis `exit 2` immédiat. Mesuré à 25 ms, indépendamment de la longueur du texte.

## Coupure d'une lecture en cours

Le `kill -TERM -PID` (tiret devant le PID) tue **tout le groupe de processus**, Piper et le `powershell.exe` qui joue le son. Sans le tiret, deux `lecture-piper` enchaînés donnent deux audios superposés.

Deux garde-fous ajoutés après tests :

- Vérification via `/proc/<pid>/cmdline` avant de tuer, pour ne jamais viser un PID recyclé appartenant à un autre processus.
- `pkill -f claude_voice.wav` avant le lancement, contre une lecture orpheline dont le PID file a disparu (arrêt brutal de WSL en cours de lecture).

## Nettoyage du texte

Tout le nettoyage se fait en `sed`, avant la synthèse : aucun appel au modèle, donc zéro token.

Traités : markdown (gras, italique, titres, listes), heures (`12h30` → « 12 heures 30 »), symboles courants (€, %, &), dates `JJ/MM` et `JJ/MM/AAAA`.

Sur les dates, le jour et le mois doivent faire deux chiffres. Sans cette contrainte, `3/4` serait lu « 3 avril » et `1/2` « 1er février ». Dans un texte technique, une fraction est plus fréquente qu'une date écrite `3/4`. Conséquence assumée : `8/9` n'est pas converti.

Non traité par décision : les chiffres romains. « XIXe siècle » est prononcé comme un mot. Correctif possible, volontairement limité aux cas courants plutôt qu'un convertisseur générique, à placer avant la ligne `sed -E 's/&/ et /g'` :

```bash
sed -E 's/\bXIXe\b/dix-neuvième/g; s/\bXXe\b/vingtième/g; s/\bXXIe\b/vingt-et-unième/g; s/\bXVIIIe\b/dix-huitième/g' | \
```

## Enseignements de la campagne de tests

**Un test mal calibré ne teste rien.** Le premier test de PID file orphelin utilisait une phrase trop courte : le script se terminait avant le `kill`, le `trap` nettoyait, et le scénario testé ne se produisait jamais.

**SIGKILL ne tue pas les enfants.** Un `kill -9` sur `lecture-piper.sh` laisse `powershell.exe` orphelin, qui continue à jouer le son. Cas de test uniquement : en usage réel le hook coupe le groupe entier.

**`jq` valide la forme, pas le placement.** Le `"timeout": 10` avait d'abord été mis à la racine de `settings.json` au lieu du handler. JSON valide, clé simplement ignorée.

**Le pipeline `echo "$TEXTE" | sed` tient sur les caractères spéciaux** à condition de garder les guillemets autour de la variable : guillemets, apostrophes, `$`, accents passent sans expansion.

## Pistes non retenues pour l'instant

- Pause/reprise au clavier : nécessite d'abandonner `PlaySync()` pour un lecteur pilotable (VLC en ligne de commande, ou `MediaPlayer` en PowerShell) plus un raccourci clavier global.
- Lecture d'un passage précis plutôt que de toute la réponse.
- Ciblage de la session courante : le hook reçoit `session_id` et `transcript_path` dans son JSON d'entrée. Réserve : la documentation précise que le fichier de transcription est écrit de façon **asynchrone** et peut être en retard sur la conversation en mémoire, ce qui risquerait de faire relire l'avant-dernière réponse.
- Extension au-delà de Claude Code.
