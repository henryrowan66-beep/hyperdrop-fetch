#!/usr/bin/env bash
# HyperDrop fetch job: resolve job -> yt-dlp -> upload to HyperDrop -> commit results/<id>.json
set -uo pipefail
HD_URL="${HD_URL:-https://hyperdrop.hyperdrop-4bd713.workers.dev}"

# ---- 1. resolve job ------------------------------------------------------
if [ -n "${INPUT_URL:-}" ]; then
  URL="$INPUT_URL"; NAME="${INPUT_NAME:-}"; ID="manual-${GITHUB_RUN_ID}"
else
  # job files added/changed in the commits of this push (works with full history)
  if [ -n "${BEFORE_SHA:-}" ] && git cat-file -e "$BEFORE_SHA" 2>/dev/null; then
    f=$(git diff --name-only --diff-filter=AM "$BEFORE_SHA" HEAD -- 'jobs/*.json' | tail -1)
  fi
  [ -z "${f:-}" ] && f=$(git log -1 --name-only --diff-filter=AM --pretty=format: -- 'jobs/*.json' | grep json | tail -1)
  [ -z "${f:-}" ] && { echo "no job file in this push"; exit 0; }
  echo "job file: $f"
  URL=$(jq -r .url "$f"); NAME=$(jq -r '.name // empty' "$f"); ID=$(basename "$f" .json)
fi
echo "job=$ID url=$URL name=${NAME:-<auto>}"
[ -f "results/$ID.json" ] && echo "note: results/$ID.json exists, will be overwritten"

# ---- 2. tools --------------------------------------------------------------
sudo apt-get update -qq >/dev/null && sudo apt-get install -y -qq ffmpeg >/dev/null
python3 -m pip install -q -U yt-dlp requests
yt-dlp --version

# ---- 3. download -----------------------------------------------------------
mkdir -p out
TEMPLATE='out/%(title).120B [%(id)s].%(ext)s'; [ -n "$NAME" ] && TEMPLATE="out/${NAME}.%(ext)s"
COOKIE_ARGS=()
RAW="${YT_COOKIES_B64:-}"
if [ -n "$RAW" ]; then
  if printf '%s' "$RAW" | grep -q "youtube.com"; then printf '%s\n' "$RAW" > cookies.txt; else printf '%s' "$RAW" | base64 -d > cookies.txt 2>/dev/null; fi
  COOKIE_ARGS=(--cookies cookies.txt); COOKIE_LINES=$(grep -c "youtube.com" cookies.txt || true); echo "using cookies ($COOKIE_LINES youtube lines)"
fi
COOKIE_LINES="${COOKIE_LINES:-0}"

STATUS=failed
FMT='bv*[height<=1080][ext=mp4]+ba[ext=m4a]/b[height<=1080][ext=mp4]/bv*+ba/b'
: > yt-dlp.log
for CLIENT in default tv mweb; do
  echo "=== attempt with player_client=$CLIENT ===" | tee -a yt-dlp.log
  if yt-dlp --no-playlist --newline --restrict-filenames "${COOKIE_ARGS[@]}" -f "$FMT" \
       --extractor-args "youtube:player_client=$CLIENT" --merge-output-format mp4 -o "$TEMPLATE" "$URL" 2>&1 | tee -a yt-dlp.log; then
    STATUS=ok; ATTEMPT_CLIENT=$CLIENT; break
  fi
  case "$URL" in *youtube.com*|*youtu.be*) ;; *) break;; esac   # only retry clients for YouTube
done
ls -la out || true
rm -f cookies.txt

# ---- 4. upload -------------------------------------------------------------
if [ "$STATUS" = ok ] && [ -n "$(ls -A out 2>/dev/null)" ]; then
  curl -sO "$HD_URL/hd_upload.py"
  f=$(ls -S out/* | head -1)
  HD_URL="$HD_URL" python3 hd_upload.py "$f" | tee result.json || STATUS=failed
else
  STATUS=failed
fi

# ---- 5. record -------------------------------------------------------------
mkdir -p results
if [ "$STATUS" = ok ] && [ -s result.json ]; then
  jq -n --arg id "$ID" --arg url "$URL" --arg run "$RUN_URL" --slurpfile r result.json \
    --arg cl "$COOKIE_LINES" --arg client "${ATTEMPT_CLIENT:-}" '{id:$id,url:$url,status:"ok",run:$run,cookieLines:($cl|tonumber),client:$client,result:$r[0],finished:(now|todate)}' > "results/$ID.json"
else
  err=$(grep -iE "ERROR|=== attempt|WARNING.*(cookie|sign in)" yt-dlp.log 2>/dev/null | tail -8 | tr '\n' ' ' | cut -c1-1200)
  jq -n --arg id "$ID" --arg url "$URL" --arg run "$RUN_URL" --arg err "${err:-unknown error}" \
    --arg cl "$COOKIE_LINES" '{id:$id,url:$url,status:"failed",error:$err,cookieLines:($cl|tonumber),run:$run,finished:(now|todate)}' > "results/$ID.json"
fi
cat "results/$ID.json"
{ echo "## HyperDrop fetch: $ID"; echo '```json'; cat "results/$ID.json"; echo '```'; } >> "$GITHUB_STEP_SUMMARY"
git config user.name hyperdrop-bot; git config user.email bot@hyperdrop
git add results/ && git commit -qm "result: $ID [skip ci]" || true
for i in 1 2 3; do git pull --rebase -q && git push -q && break || sleep 3; done
[ "$STATUS" = ok ]
