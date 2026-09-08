#!/usr/bin/env bash
# Couche A — met en place le chantier d'un agent AVANT qu'il ne travaille :
#   issue -> branche -> fichier de suivi -> commit dummy -> PR Draft.
# Déterministe, aucun appel modèle.
#
# Entrées (variables d'environnement) :
#   ROLE, TASK, TITLE, ASSIGNEE, BASE_BRANCH, RUN_ID, MODEL, REPO (owner/name)
#   GH_TOKEN
# Sorties ($GITHUB_OUTPUT) : issue, pr, branch, tracking, slug, base_branch
set -euo pipefail

: "${ROLE:?}" "${TASK:?}" "${RUN_ID:?}" "${REPO:?}"
ASSIGNEE="${ASSIGNEE:-ocots}"
BASE_BRANCH="${BASE_BRANCH:-$(gh repo view "$REPO" --json defaultBranchRef -q .defaultBranchRef.name)}"
TITLE="${TITLE:-$ROLE}"
MODEL="${MODEL:-?}"

slugify() { echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g' | cut -c1-40; }
SLUG="$(slugify "$TITLE")"; [ -n "$SLUG" ] || SLUG="$(slugify "$ROLE")"

BRANCH="agent/${SLUG}-${RUN_ID}"
TRACKING=".agents/runs/${SLUG}-${RUN_ID}.md"
RUN_URL="https://github.com/${REPO}/actions/runs/${RUN_ID}"
now() { date -u +%FT%TZ; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# --- label (idempotent) ---
gh label create agent --repo "$REPO" --color 5319e7 \
  --description "Travail mené par un agent IA" 2>/dev/null || true

# --- issue ---
cat > "$tmp/issue.md" <<EOF
**Rôle :** \`$ROLE\`

**Tâche :**
$TASK

---
- Branche : \`$BRANCH\`
- Suivi (plan + journal + bilan) : \`$TRACKING\`
- Modèle : \`$MODEL\`
- Run : $RUN_URL

_Ouverte automatiquement par la base d'agents (\`ocourses/agents\`)._
EOF
ISSUE_URL="$(gh issue create --repo "$REPO" --title "[agent] $TITLE" \
  --body-file "$tmp/issue.md" --label agent --assignee "$ASSIGNEE")"
ISSUE="${ISSUE_URL##*/}"

# --- branche + fichier de suivi + commit dummy ---
git config user.name  "ocourses-agent"
git config user.email "agent@users.noreply.github.com"
git switch -c "$BRANCH" "origin/$BASE_BRANCH" 2>/dev/null || git switch -c "$BRANCH"

mkdir -p .agents/runs
cat > "$TRACKING" <<EOF
# Suivi — $TITLE

| Champ | Valeur |
|-------|--------|
| Rôle | \`$ROLE\` |
| Issue | #$ISSUE |
| Branche | \`$BRANCH\` |
| Modèle | \`$MODEL\` |
| Run | $RUN_URL |
| Démarré | $(now) |

## Tâche

$TASK

## Plan

_À rédiger par l'agent : liste d'étapes cochables._

## Journal

- $(now) — chantier initialisé (issue #$ISSUE, branche, PR Draft)

## Bilan

_À rédiger par l'agent en fin de run._
EOF

git add "$TRACKING"
git commit -m "chore(agent): initialise le suivi de $ROLE (#$ISSUE)"
git push -u origin "$BRANCH"

# --- PR Draft ---
cat > "$tmp/pr.md" <<EOF
Closes #$ISSUE

**Rôle :** \`$ROLE\`
**Tâche :** $TASK

PR ouverte en **Draft** par un agent (\`ocourses/agents\`). Le travail arrive en
commits ; un commentaire de bilan sera ajouté à la fin. Le suivi complet (plan,
journal, bilan) est dans \`$TRACKING\`. **Relecture humaine avant fusion.**
EOF
PR_URL="$(gh pr create --repo "$REPO" --draft --base "$BASE_BRANCH" --head "$BRANCH" \
  --title "[agent] $TITLE" --body-file "$tmp/pr.md" --assignee "$ASSIGNEE")"
PR="${PR_URL##*/}"

{
  echo "issue=$ISSUE"
  echo "pr=$PR"
  echo "branch=$BRANCH"
  echo "tracking=$TRACKING"
  echo "slug=$SLUG"
  echo "base_branch=$BASE_BRANCH"
} >> "${GITHUB_OUTPUT:-/dev/stdout}"

echo "Chantier prêt : issue #$ISSUE, PR #$PR, branche $BRANCH"
