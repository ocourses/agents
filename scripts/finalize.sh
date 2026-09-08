#!/usr/bin/env bash
# Couche A — clôture le chantier d'un agent APRÈS son travail :
#   maj du fichier de suivi -> commit/push -> commentaire de bilan sur la PR.
# La PR reste en Draft (relecture humaine).
#
# Entrées (variables d'environnement) :
#   REPO, PR, TRACKING, SUMMARY, OUTCOME (success|failure)
set -euo pipefail

: "${REPO:?}" "${PR:?}" "${TRACKING:?}" "${SUMMARY:?}"
OUTCOME="${OUTCOME:-success}"
RUN_URL="https://github.com/${REPO}/actions/runs/${GITHUB_RUN_ID:-?}"
now="$(date -u +%FT%TZ)"

git config user.name  "ocourses-agent"
git config user.email "agent@users.noreply.github.com"

# --- fichier de suivi ---------------------------------------------------
if [ -f "$TRACKING" ]; then
  if [ "$OUTCOME" = "success" ]; then
    sed -i.bak 's/- \[ \] Plan d.action rédigé/- [x] Plan d'\''action rédigé/' "$TRACKING" || true
    sed -i.bak 's/- \[ \] Travail réalisé/- [x] Travail réalisé/' "$TRACKING" || true
    sed -i.bak 's/- \[ \] Terminé/- [x] Terminé/' "$TRACKING" || true
    printf '\n- %s — travail terminé (%s)\n' "$now" "$RUN_URL" >> "$TRACKING"
  else
    printf '\n- %s — **interrompu** (%s) — voir le transcript\n' "$now" "$RUN_URL" >> "$TRACKING"
  fi
  rm -f "${TRACKING}.bak"
  git add "$TRACKING"
  git commit -m "chore(agent): met à jour le suivi" || true
  git push || true
fi

# --- commentaire de bilan sur la PR ----------------------------------
if [ -f "$SUMMARY" ]; then
  {
    if [ "$OUTCOME" != "success" ]; then
      echo "> ⚠️ Run interrompu avant la fin — bilan partiel."
      echo
    fi
    cat "$SUMMARY"
    echo
    echo "---"
    echo "_Bilan produit par l'agent · run : $RUN_URL_"
  } | gh pr comment "$PR" --repo "$REPO" --body-file -
else
  gh pr comment "$PR" --repo "$REPO" --body \
    "L'agent n'a pas produit de bilan (outcome: $OUTCOME). Voir le run : $RUN_URL"
fi

echo "Chantier clôturé (outcome: $OUTCOME) — PR #$PR laissée en Draft."
