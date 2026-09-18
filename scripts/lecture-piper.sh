#!/bin/bash
PIDFILE="$HOME/.claude/lecture-piper.pid"
echo $$ > "$PIDFILE"
trap 'rm -f "$PIDFILE"' EXIT

# Récupère le texte : soit en argument direct, soit depuis la dernière transcription
if [ -n "$1" ]; then
  TEXTE="$1"
else
  DERNIER_JSONL=$(find ~/.claude/projects -name "*.jsonl" -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-)
  TEXTE=$(grep '"type":"assistant"' "$DERNIER_JSONL" | tail -n 1 | jq -r '.message.content[0].text // empty')
fi

# Nettoyage du texte pour la lecture
TEXTE_PROPRE=$(echo "$TEXTE" | \
  sed -E 's/\*\*([^*]+)\*\*/\1/g' | \
  sed -E 's/\*([^*]+)\*/\1/g' | \
  sed -E 's/^#+\s*//g' | \
  sed -E 's/^[-*]\s+/. /g' | \
  sed -E 's/([0-9]{1,2})h([0-9]{2})/\1 heures \2/g' | \
  sed -E 's/€/ euros/g' | \
  sed -E 's/%/ pourcent/g' | \
  sed -E 's/&/ et /g' | \
  sed -E '
    s#\b([0-9]{2})/01(/([0-9]{2}|[0-9]{4}))?\b#\1 janvier \3#g
    s#\b([0-9]{2})/02(/([0-9]{2}|[0-9]{4}))?\b#\1 février \3#g
    s#\b([0-9]{2})/03(/([0-9]{2}|[0-9]{4}))?\b#\1 mars \3#g
    s#\b([0-9]{2})/04(/([0-9]{2}|[0-9]{4}))?\b#\1 avril \3#g
    s#\b([0-9]{2})/05(/([0-9]{2}|[0-9]{4}))?\b#\1 mai \3#g
    s#\b([0-9]{2})/06(/([0-9]{2}|[0-9]{4}))?\b#\1 juin \3#g
    s#\b([0-9]{2})/07(/([0-9]{2}|[0-9]{4}))?\b#\1 juillet \3#g
    s#\b([0-9]{2})/08(/([0-9]{2}|[0-9]{4}))?\b#\1 août \3#g
    s#\b([0-9]{2})/09(/([0-9]{2}|[0-9]{4}))?\b#\1 septembre \3#g
    s#\b([0-9]{2})/10(/([0-9]{2}|[0-9]{4}))?\b#\1 octobre \3#g
    s#\b([0-9]{2})/11(/([0-9]{2}|[0-9]{4}))?\b#\1 novembre \3#g
    s#\b([0-9]{2})/12(/([0-9]{2}|[0-9]{4}))?\b#\1 décembre \3#g
    s/\b0([1-9]) (janvier|février|mars|avril|mai|juin|juillet|août|septembre|octobre|novembre|décembre)/\1 \2/g
    s/\b1 (janvier|février|mars|avril|mai|juin|juillet|août|septembre|octobre|novembre|décembre)/1er \1/g
    s/  +/ /g
  ')

# Génère l'audio et le joue
VITESSE="${2:-${PIPER_LENGTH_SCALE:-1.0}}"
PIPER_BIN="${PIPER_BIN:-$HOME/piper-venv/bin/piper}"
PIPER_MODEL="${PIPER_MODEL:-$HOME/piper-voices/fr_FR-siwis-medium.onnx}"
WAV_OUT="${WAV_OUT:-$HOME/claude_voice.wav}"
echo "$TEXTE_PROPRE" | "$PIPER_BIN" -m "$PIPER_MODEL" --length-scale "$VITESSE" --output_file "$WAV_OUT"
powershell.exe -c "(New-Object Media.SoundPlayer '$(wslpath -w "$WAV_OUT")').PlaySync()"