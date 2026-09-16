#!/usr/bin/env bash
# Couche A — met en place le chantier d'un agent AVANT qu'il ne travaille :
#   issue -> branche -> fichier de suivi -> commit dummy -> PR Draft.
# Déterministe, aucun appel modèle.
#
# Entrées (variables d'environnement) :
#   ROLE, TASK, TITLE, ASSIGNEE, BASE_BRANCH, RUN_ID, MODEL, REPO (owner/name)
#   GH_TOKEN
#   LINK_ISSUE   optionnel — numéro d'une issue métier qui existe déjà avant
#                le run (template-migration, conventions-candidate,
#                conventions-style). Si fourni, AUCUNE issue de suivi n'est
#                créée : LINK_ISSUE sert elle-même de fil de suivi. Sans ça,
#                une issue de suivi dédiée est créée comme avant.
#   CLOSE_ON_MERGE  défaut "true" — si différent de "false", la PR ferme
#                nativement ("Closes #N") l'issue de suivi (dédiée, ou
#                LINK_ISSUE) à sa fusion. À mettre à "false" pour un rôle de
#                TRIAGE (conventions-reviewer) dont la PR ne livre aucun
#                correctif de contenu et dont LINK_ISSUE peut rester ouverte
#                après fusion (promue conventions-style, en attente d'un
#                rôle correcteur) : la fermer à la fusion la sortirait de la
#                file sans que le correctif n'ait jamais eu lieu (bug
#                rencontré sur mesure-integration-enseignants#125 / PR #169).
# Sorties ($GITHUB_OUTPUT) : issue, pr, branch, tracking, slug, base_branch, task
#   task = TASK potentiellement enrichie du body de LINK_ISSUE (cf. plus bas) —
#   c'est CETTE valeur que le step suivant (run-opencode.sh) doit utiliser,
#   pas l'input `task=` brut, sous peine de perdre l'enrichissement.
set -euo pipefail

: "${ROLE:?}" "${TASK:?}" "${RUN_ID:?}" "${REPO:?}"
ASSIGNEE="${ASSIGNEE:-ocots}"
LINK_ISSUE="${LINK_ISSUE:-}"
CLOSE_ON_MERGE="${CLOSE_ON_MERGE:-true}"
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
# Avec LINK_ISSUE : elle EST le fil de suivi, pas de doublon créé. Sans elle
# (migration lancée hors file, rôle sans issue d'origine) : on en ouvre une.
if [ -n "$LINK_ISSUE" ]; then
  ISSUE="$LINK_ISSUE"
  gh issue edit "$ISSUE" --repo "$REPO" --add-label agent --add-assignee "$ASSIGNEE" >/dev/null
  gh issue comment "$ISSUE" --repo "$REPO" --body "$(cat <<EOF
Prise en charge par le rôle \`$ROLE\` — branche \`$BRANCH\`, run $RUN_URL.
Suivi (plan + journal + bilan) : \`$TRACKING\`.
EOF
)" >/dev/null

  # La tâche fournie par le workflow appelant (`task=`) peut rester générique
  # ("migre le document") : le détail concret (ex. pour une issue LEGACY, la
  # liste des noms d'alias trouvés par le checker) vit dans le BODY de
  # l'issue liée, pas dans l'input. Sans cet ajout, l'agent n'a aucun moyen
  # de le voir et peut conclure « rien à faire » à tort (cf. ocourses/agents#10).
  # `|| true` : un body illisible (permissions, issue supprimée entre-temps)
  # ne doit pas faire échouer tout le chantier, juste laisser TASK inchangée.
  ISSUE_BODY="$(gh issue view "$ISSUE" --repo "$REPO" --json body -q '.body // ""' 2>/dev/null || true)"
  if [ -n "$ISSUE_BODY" ]; then
    TASK="$(printf "%s\n\n---\n\n**Contenu de l'issue liée #%s :**\n\n%s\n" "$TASK" "$ISSUE" "$ISSUE_BODY")"
  fi
else
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
fi

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
# LINK_ISSUE vaut déjà ISSUE ci-dessus (pas de doublon) : une seule ligne
# "Closes #N" suffit, elle ferme l'issue métier d'origine à la fusion — sauf
# CLOSE_ON_MERGE=false (rôle de triage, cf. en-tête), où fermer à la fusion
# sortirait l'issue de la file avant que le vrai correctif n'ait eu lieu.
CLOSES_LINE=""
[ "$CLOSE_ON_MERGE" = "false" ] || CLOSES_LINE="Closes #$ISSUE"$'\n\n'
cat > "$tmp/pr.md" <<EOF
${CLOSES_LINE}**Rôle :** \`$ROLE\`
**Tâche :** $TASK

---
- 🔧 Run (job de l'agent) : $RUN_URL
- 📋 Suivi (plan + journal + bilan) : \`$TRACKING\`
- 🤖 Modèle : \`$MODEL\`

PR ouverte en **Draft** par un agent (\`ocourses/agents\`). Le travail arrive en
commits ; un commentaire de bilan sera ajouté à la fin. **Relecture humaine avant
fusion.**
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
  # TASK peut contenir des sauts de ligne (body d'issue enrichi) : forme
  # multiligne officielle des sorties GitHub Actions, délimiteur imprévisible
  # pour éviter toute collision avec le contenu.
  task_delim="TASK_${RUN_ID}_$$"
  echo "task<<$task_delim"
  echo "$TASK"
  echo "$task_delim"
} >> "${GITHUB_OUTPUT:-/dev/stdout}"

echo "Chantier prêt : issue #$ISSUE, PR #$PR, branche $BRANCH"
