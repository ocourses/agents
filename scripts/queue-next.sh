#!/usr/bin/env bash
# File d'attente globale — dépile la plus ancienne tâche éligible, TOUS
# DÉPÔTS DE COURS CONFONDUS (config/course-repos.txt) et TOUTES NATURES
# CONFONDUES (migration + triage conventions), l'envoie au bon workflow, et
# ATTEND LA FIN avant de rendre la main.
#
# C'est ce qui rend le verrou global réel : `queue.yml` (l'appelant) tourne
# toujours DANS ocourses/agents, donc sa `concurrency:` s'applique vraiment à
# travers tous les dépôts de cours — contrairement à `agent.yml`
# (workflow_call), dont la concurrency est scopée au dépôt appelant et ne
# protège qu'à l'intérieur d'un seul dépôt (GitHub Actions ne sérialise pas
# nativement entre dépôts). Un tick = une tâche ; le tick suivant (cron)
# dépile la suivante.
#
# Deux natures de tâches, deux workflows cibles :
#
#   label source              -> workflow                        -> rôle
#   template-migration        -> agent-migrate-latex.yml          -> latex-template-migrator
#   conventions-candidate     -> agent-review-conventions.yml     -> conventions-reviewer
#
# `conventions-candidate` (sortie brute de checkers/conventions.sh) n'est
# JAMAIS traité comme un verdict : l'agent conventions-reviewer relit et
# décide (confirme -> conventions-style, ou rejette -> ferme). Comme il
# appelle Albert, il passe par cette même file — pas de traitement à part.
#
# Entrées :
#   GH_TOKEN            PAT (PAS le github.token par défaut : celui-ci n'a de
#                        portée que sur ocourses/agents) avec, sur chaque
#                        dépôt de config/course-repos.txt : Issues (lire/écrire),
#                        Actions (lire/écrire), Contents (lire), Metadata (lire).
#   COURSE_REPOS_FILE   défaut: config/course-repos.txt
set -euo pipefail

COURSE_REPOS_FILE="${COURSE_REPOS_FILE:-config/course-repos.txt}"
DISPATCHED_LABEL="agent:dispatched"
FAILED_LABEL="agent:failed"

: "${GH_TOKEN:?GH_TOKEN requis (PAT dédié, voir en-tête du script)}"
[ -f "$COURSE_REPOS_FILE" ] || { echo "::error::$COURSE_REPOS_FILE introuvable"; exit 1; }

mapfile -t repos < <(grep -vE '^[[:space:]]*(#|$)' "$COURSE_REPOS_FILE")
[ "${#repos[@]}" -gt 0 ] || { echo "Aucun dépôt listé dans $COURSE_REPOS_FILE — rien à faire."; exit 0; }
echo "Dépôts surveillés : ${repos[*]}"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
: > "$tmp/candidates.jsonl"

for repo in "${repos[@]}"; do
  gh label create "$DISPATCHED_LABEL" --repo "$repo" --color 5319e7 \
    --description "Tâche déjà envoyée à la file d'attente" 2>/dev/null || true
  gh label create "$FAILED_LABEL" --repo "$repo" --color b60205 \
    --description "Run en échec — vérifier avant de remettre en file" 2>/dev/null || true

  gh issue list --repo "$repo" --label "template-migration" --state open \
    --json number,title,createdAt,labels --limit 200 2>/dev/null \
  | jq -c --arg repo "$repo" --arg kind "migration" \
      '.[] | . + {repo: $repo, kind: $kind}' >> "$tmp/candidates.jsonl" || true

  gh issue list --repo "$repo" --label "conventions-candidate" --state open \
    --json number,title,createdAt,labels --limit 200 2>/dev/null \
  | jq -c --arg repo "$repo" --arg kind "conventions" \
      '.[] | . + {repo: $repo, kind: $kind}' >> "$tmp/candidates.jsonl" || true
done

jq -s --arg d "$DISPATCHED_LABEL" --arg f "$FAILED_LABEL" '
  [ .[] | select(([.labels[].name] | index($d)) == null and ([.labels[].name] | index($f)) == null) ]
  | sort_by(.createdAt)
' "$tmp/candidates.jsonl" > "$tmp/eligible.json"

n="$(jq 'length' "$tmp/eligible.json")"
echo "Candidats éligibles : $n"
if [ "$n" -eq 0 ]; then
  echo "File vide : rien à traiter."
  exit 0
fi

pick="$(jq -c '.[0]' "$tmp/eligible.json")"
repo="$(printf '%s' "$pick" | jq -r '.repo')"
kind="$(printf '%s' "$pick" | jq -r '.kind')"
number="$(printf '%s' "$pick" | jq -r '.number')"
title="$(printf '%s' "$pick" | jq -r '.title')"

case "$kind" in
  migration)    dispatch_workflow="agent-migrate-latex.yml" ;;
  conventions)  dispatch_workflow="agent-review-conventions.yml" ;;
  *) echo "::error::nature de tâche inconnue : $kind"; exit 1 ;;
esac
target="${title#\[*\] }"

echo "Choisi : $repo#$number [$kind] — $target"

# Marquer avant de déclencher : un seul tick actif à la fois (verrou global),
# donc pas de risque de double-pick, mais la trace reste utile.
gh issue edit "$number" --repo "$repo" --add-label "$DISPATCHED_LABEL" >/dev/null

if [ "$kind" = "migration" ]; then
  echo "Déclenchement : $dispatch_workflow -f target=$target sur $repo"
  gh workflow run "$dispatch_workflow" --repo "$repo" -f "target=$target"
else
  echo "Déclenchement : $dispatch_workflow -f target=$target -f issue=$number sur $repo"
  gh workflow run "$dispatch_workflow" --repo "$repo" -f "target=$target" -f "issue=$number"
fi

sleep 8
run_json="$(gh run list --repo "$repo" --workflow "$dispatch_workflow" --limit 1 \
  --json databaseId,url,status,createdAt)"
run_id="$(printf '%s' "$run_json" | jq -r '.[0].databaseId')"
run_url="$(printf '%s' "$run_json" | jq -r '.[0].url')"

if [ -z "$run_id" ] || [ "$run_id" = "null" ]; then
  gh issue edit "$number" --repo "$repo" --add-label "$FAILED_LABEL" >/dev/null
  gh issue comment "$number" --repo "$repo" \
    --body "⚠️ Déclenchement envoyé mais aucun run retrouvé sur \`$dispatch_workflow\` — vérifier à la main (workflow absent sur ce dépôt ? PAT sans \`actions:write\` ?)." >/dev/null
  echo "::error::run introuvable après dispatch"
  exit 1
fi

gh issue comment "$number" --repo "$repo" \
  --body "File d'attente : run déclenché → $run_url (\`$dispatch_workflow\`, cible \`$target\`)." >/dev/null

echo "Run : $run_url — attente de la fin (tient le verrou global)…"
set +e
gh run watch "$run_id" --repo "$repo" --exit-status
rc=$?
set -e

# ---------------------------------------------------------------------------
# Vérification du succès : le critère dépend de la nature de la tâche.
# ---------------------------------------------------------------------------
success=0
if [ "$kind" = "migration" ]; then
  pr_title="[agent] Migration ${target}"
  pr_json="$(gh pr list --repo "$repo" --state open --search "in:title \"${pr_title}\"" \
    --json number,url --limit 5 2>/dev/null || echo '[]')"
  pr_url="$(printf '%s' "$pr_json" | jq -r '.[0].url // empty')"
  if [ "$rc" -eq 0 ] && [ -n "$pr_url" ]; then
    success=1
    gh issue comment "$number" --repo "$repo" \
      --body "Run terminé → PR ouverte : $pr_url (reste en **Draft**, relecture humaine avant fusion)." >/dev/null
    gh issue close "$number" --repo "$repo" --reason completed >/dev/null
    echo "OK : $pr_url"
  fi
else
  # conventions-reviewer traite l'issue lui-même (ferme, ou retire le label
  # conventions-candidate en promouvant conventions-style) : on vérifie son
  # état après coup, on ne referme/edite rien ici.
  state_json="$(gh issue view "$number" --repo "$repo" --json state,labels 2>/dev/null || echo '{}')"
  state="$(printf '%s' "$state_json" | jq -r '.state // "OPEN"')"
  still_candidate="$(printf '%s' "$state_json" | jq -r '([.labels[]?.name] // []) | index("conventions-candidate") != null')"
  if [ "$rc" -eq 0 ] && { [ "$state" = "CLOSED" ] || [ "$still_candidate" = "false" ]; }; then
    success=1
    echo "OK : candidat traité par l'agent (état: $state)"
  fi
fi

if [ "$success" -ne 1 ]; then
  gh issue edit "$number" --repo "$repo" --add-label "$FAILED_LABEL" >/dev/null
  gh issue comment "$number" --repo "$repo" \
    --body "⚠️ Run terminé en échec, ou sans résultat exploitable : $run_url. **Pas de nouvelle tentative automatique** — vérifier (logs du run, fichier de suivi \`.agents/runs/\`), puis retirer le label \`$FAILED_LABEL\` pour remettre en file." >/dev/null
  echo "ÉCHEC (rc=$rc) — voir $run_url"
fi
