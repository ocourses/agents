#!/usr/bin/env bash
# Couche A — clôture le chantier APRÈS le travail d'OpenCode :
#   maj du suivi -> push -> commentaire de bilan sur la PR.
# La PR reste en Draft (relecture humaine).
#
# Entrées (variables d'environnement) :
#   REPO, PR, BRANCH, TRACKING, OUTCOME (success|failure), RUN_ID, GH_TOKEN
set -euo pipefail

: "${REPO:?}" "${PR:?}" "${BRANCH:?}" "${TRACKING:?}"
OUTCOME="${OUTCOME:-success}"
RUN_URL="https://github.com/${REPO}/actions/runs/${RUN_ID:-?}"
now="$(date -u +%FT%TZ)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# Garde-fou cwd : TRACKING est un chemin relatif au clone du dépôt CIBLE
# (celui de $REPO), pas à ocourses/agents d'où ce script est lui-même
# invoqué. Lancé depuis le mauvais répertoire, `git add -A`/`commit`/`push`
# ci-dessous agiraient sur un tout autre dépôt (silencieusement : TRACKING
# absent n'est pas une erreur pour l'étape suivante) — arrêt explicite ici
# plutôt que ce silence. Incident réel : run local du 2026-09-17.
[ -f "$TRACKING" ] || {
  echo "::error::TRACKING introuvable ($TRACKING) — ce script doit être lancé depuis le clone de $REPO, pas depuis ocourses/agents." >&2
  exit 1
}

git config user.name  "ocourses-agent"
git config user.email "agent@users.noreply.github.com"

# --- maj du suivi + push de tout ce qui traîne ---
if [ -f "$TRACKING" ]; then
  if [ "$OUTCOME" = "success" ]; then
    printf '\n- %s — run terminé (%s)\n' "$now" "$RUN_URL" >> "$TRACKING"
  else
    printf '\n- %s — **run interrompu** (%s) — bilan partiel\n' "$now" "$RUN_URL" >> "$TRACKING"
  fi
fi
git add -A
git commit -m "chore(agent): clôture du suivi" || echo "rien à committer"
git push origin "HEAD:${BRANCH}" || true

# --- bilan = section "## Bilan" du fichier de suivi ---
if [ -f "$TRACKING" ]; then
  awk '
    /^##[[:space:]]+Bilan[[:space:]]*$/ { f=1; next }
    /^##[[:space:]]/                    { f=0 }
    f                                  { print }
  ' "$TRACKING" | awk 'NF {p=1} p' > "$tmp/bilan.md"
fi

{
  if [ "$OUTCOME" != "success" ]; then
    echo "> ⚠️ Run interrompu avant la fin — bilan partiel."
    echo
  fi
  if [ -s "$tmp/bilan.md" ] && ! grep -qi "À rédiger par l'agent" "$tmp/bilan.md"; then
    cat "$tmp/bilan.md"
  else
    echo "_L'agent n'a pas produit de bilan._ Voir le suivi \`$TRACKING\` et les commits de la branche."
  fi
  echo
  echo "---"
  echo "_Run : ${RUN_URL} · suivi : \`${TRACKING}\`_"
} > "$tmp/comment.md"

gh pr comment "$PR" --repo "$REPO" --body-file "$tmp/comment.md"

echo "Chantier clôturé (outcome: $OUTCOME) — PR #$PR laissée en Draft."
