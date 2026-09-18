#!/bin/bash
PIDFILE="$HOME/.claude/lecture-piper.pid"
LOG="$HOME/.claude/lecture-piper.log"

input=$(cat)
prompt=$(printf '%s' "$input" | jq -r '.prompt // ""' \
         | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')

[ "$prompt" = "lecture-piper" ] || exit 0

# Coupe une lecture précédente encore en cours (setsid : PGID = PID du script)
if [ -f "$PIDFILE" ]; then
  oldpid=$(cat "$PIDFILE" 2>/dev/null)
  if [ -n "$oldpid" ] && grep -qa 'lecture-piper' /proc/"$oldpid"/cmdline 2>/dev/null; then
    kill -TERM -"$oldpid" 2>/dev/null
  fi
  rm -f "$PIDFILE"
fi

# Filet de securite : coupe une lecture orpheline dont le PID file a disparu
pkill -f claude_voice.wav 2>/dev/null

# Détachement complet : nouvelle session, aucun descripteur partagé avec le hook
setsid "$HOME/lecture-piper.sh" </dev/null >>"$LOG" 2>&1 &

echo "Lecture audio lancée." >&2
exit 2