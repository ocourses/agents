#!/usr/bin/env bash
# Couche A — met en place le chantier d'un agent AVANT qu'il ne travaille :
#   issue -> branche -> fichier de suivi -> commit dummy -> PR Draft.
# Tout est déterministe (aucun appel modèle ici).
#
# Entrées (variables d'environnement) :
#   ROLE, TASK, TITLE, ASSIGNEE, BASE_BRANCH, RUN_ID, MODEL, REPO (owner/name)
# Sorties : écrites dans $GITHUB_OUTPUT (issue, pr, branch, tracking, plan,
#           summary, slug).
set -euo pipefail

: "${ROLE:?}" "${TASK:?}" "${RUN_ID:?}" "${REPO:?}"
ASSIGNEE="${ASSIGNEE:-ocots}"
BASE_BRANCH="${BASE_BRANCH:-$(gh repo view "$REPO" --json defaultBranchRef -q .defaultBranchRef.name)}"
TITLE="${TITLE:-$ROLE}"

slugify() { echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g' | cut -c1-40; }
SLUG="$(slugify "$TITLE")"
[ -n "$SLUG" ] || SLUG="$(slugify "$ROLE")"

BRANCH="agent/${SLUG}-${RUN_ID}"
TRACKING=".agents/runs/${SLUG}-${RUN_ID}.md"
PLAN=".agents/plans/${SLUG}-${RUN_ID}.md"
# Le bilan est transitoire (commentaire de PR) : hors de l'arbre suivi.
SUMMARY="_agent_logs/${SLUG}-${RUN_ID}.summary.md"
RUN_URL="https://github.com/${REPO}/actions/runs/${GITHUB_RUN_ID:-$RUN_ID}"

# --- label (idempotent) ---------------------------------------------------
gh label create agent --repo "$REPO" --color 5319e7 \
  --description "Travail mené par un agent IA" 2>/dev/null || true

# --- issue --------------------------------------------------------------
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/issue.md" <<EOF
**Rôle :** \`$ROLE\`

**Tâche :**
$TASK

---
- Branche de travail : \`$BRANCH\`
- Suivi : \`$TRACKING\`
- Plan d'action : \`$PLAN\`
- Modèle : \`${MODEL:-?}\`
- Run : $RUN_URL

_Issue ouverte automatiquement par la base d'agents (\`ocourses/agents\`)._
EOF
ISSUE_URL="$(gh issue create --repo "$REPO" --title "[agent] $TITLE" \
  --body-file "$tmp/issue.md" --label agent --assignee "$ASSIGNEE")"
ISSUE="${ISSUE_URL##*/}"

# --- branche + fichier de suivi + commit dummy -------------------------
git config user.name  "ocourses-agent"
git config user.email "agent@users.noreply.github.com"
git switch -c "$BRANCH" "origin/$BASE_BRANCH" 2>/dev/null || git switch -c "$BRANCH"

mkdir -p .agents/runs .agents/plans
cat > "$TRACKING" <<EOF
# Suivi — $TITLE

| Champ | Valeur |
|-------|--------|
| Rôle | \`$ROLE\` |
| Issue | #$ISSUE |
| Branche | \`$BRANCH\` |
| Modèle | \`${MODEL:-?}\` |
| Run | $RUN_URL |
| Démarré | $(date -u +%FT%TZ) |

## Tâche

$TASK

## Avancement

- [x] Chantier initialisé (issue, branche, PR Draft)
- [ ] Plan d'action rédigé
- [ ] Travail réalisé
- [ ] Terminé

## Journal

- $(date -u +%FT%TZ) — chantier initialisé
EOF

git add "$TRACKING"
git commit -m "chore(agent): initialise le suivi de $ROLE (#$ISSUE)"
git push -u origin "$BRANCH"

# --- PR Draft ---------------------------------------------------------
cat > "$tmp/pr.md" <<EOF
Closes #$ISSUE

**Rôle :** \`$ROLE\`
**Tâche :** $TASK

PR ouverte en **Draft** par un agent. Le plan d'action puis le travail arrivent
en commits suivants ; un commentaire de bilan sera ajoute a la fin. Relecture
humaine avant passage en « Ready ».
EOF
PR_URL="$(gh pr create --repo "$REPO" --draft --base "$BASE_BRANCH" --head "$BRANCH" \
  --title "[agent] $TITLE" --body-file "$tmp/pr.md" --assignee "$ASSIGNEE")"
PR="${PR_URL##*/}"

# --- sorties ---------------------------------------------------------
{
  echo "issue=$ISSUE"
  echo "pr=$PR"
  echo "branch=$BRANCH"
  echo "tracking=$TRACKING"
  echo "plan=$PLAN"
  echo "summary=$SUMMARY"
  echo "slug=$SLUG"
  echo "base_branch=$BASE_BRANCH"
} >> "${GITHUB_OUTPUT:-/dev/stdout}"

echo "Chantier prêt : issue #$ISSUE, PR #$PR, branche $BRANCH"
