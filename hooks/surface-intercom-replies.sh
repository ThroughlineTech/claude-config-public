#!/usr/bin/env bash
# UserPromptSubmit hook — surfaces unread intercom replies from inbox.jsonl
# using an append-only file + byte-offset cursor.
#
# CRITICAL: the cursor advance happens INSIDE the successful-parse branch of
# the loop, never at end-of-loop after a skip. A torn/incomplete line must
# remain unread so the listener can finish flushing it and the hook will
# re-read it on the next invocation. Inverting this silently loses replies.

set -euo pipefail

INBOX="${INTERCOM_INBOX:-$HOME/.local/state/intercom/inbox.jsonl}"
CURSOR="${INTERCOM_CURSOR:-$HOME/.local/state/intercom/inbox.cursor}"

[ -f "$INBOX" ] || exit 0

start=0
if [ -f "$CURSOR" ]; then
  start=$(cat "$CURSOR")
fi

size=$(wc -c < "$INBOX" | tr -d ' ')
if [ "$start" -ge "$size" ]; then
  exit 0
fi

offset="$start"
surfaced=0

# Read from cursor to EOF, one line at a time.
# Each loop iteration either: parses + surfaces + advances cursor, OR breaks
# without touching cursor (torn line).
while IFS= read -r line || [ -n "$line" ]; do
  # bytes consumed by this line (content + terminating newline if present)
  line_bytes=$((${#line} + 1))

  if parsed=$(printf '%s' "$line" | jq -c . 2>/dev/null); then
    if [ "$surfaced" -eq 0 ]; then
      echo "[intercom replies — you MUST surface these to the user at the top of your response before answering anything else; summarize status and result of each reply in plain language:]"
      surfaced=1
    fi
    echo "  $parsed"
    offset=$((offset + line_bytes))
    printf '%s' "$offset" > "$CURSOR"
  else
    # torn/malformed line — stop, leave cursor where it is.
    break
  fi
done < <(tail -c +$((start + 1)) "$INBOX")

exit 0
