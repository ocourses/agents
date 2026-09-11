#!/usr/bin/env bash
# File d'attente globale — dépile la plus ancienne issue `template-migration`
# non traitée, TOUS DÉPÔTS DE COURS CONFONDUS (config/course-repos.txt), lui
# envoie l'agent de migration, et ATTEND LA FIN avant de rendre la main.
#
# C'est ce qui rend le verrou global réel : `queue.yml` (l'appelant) tourne
# toujours DANS ocourses/agents, donc sa `concurrency:` s'applique vraiment à
# travers tous les dépôts de cours — contrairement à `agent.yml`
# (workflow_call), dont la concurrency est scopée au dépôt appelant et ne
# protège qu'à l'intérieur d'un seul dépôt (GitHub Actions ne sérialise pas
# nativement entre dépôts). Un tick = une issue ; le tick suivant (cron)
# dépile la suivante.
#
# Ne traite que les issues `template-migration` (checker template-migration)
# — pas `conventions-style` : il n'existe pas de correcteur automatique sûr
# pour les règles qui demandent du jugement (P2, P3, P5). Seul `nettoyer`
# (ocots-conventions) corrige mécaniquement, et seulement une partie de C4 ;
# pas branché ici pour l'instant.
#
# Entrées :
#   GH_TOKEN            PAT (PAS le github.token par défaut : celui-ci n'a de
#                        portée que sur ocourses/agents) avec, sur chaque
#                        dépôt de config/course-repos.txt : Issues (lire/écrire),
#                        Actions (lire/écrire), Contents (lire), Metadata (lire).
#   COURSE_REPOS_FILE   défaut: config/course-repos.txt
#   DISPATCH_WORKFLOW   défaut: agent-migrate-latex.yml
set -euo pipefail

COURSE_REPOS_FILE="${COURSE_REPOS_FILE:-config/course-repos.txt}"
DISPATCH_WORKFLOW="${DISPATCH_WORKFLOW:-agent-migrate-latex.yml}"
QUEUE_LABEL="template-migration"
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
    --description "Migration déjà envoyée à la file d'attente" 2>/dev/null || true
  gh label create "$FAILED_LABEL" --repo "$repo" --color b60205 \
    --description "Run de migration en échec — vérifier avant de remettre en file" 2>/dev/null || true
  gh issue list --repo "$repo" --label "$QUEUE_LABEL" --state open \
    --json number,title,createdAt,labels --limit 200 2>/dev/null \
  | jq -c --arg repo "$repo" '.[] | . + {repo: $repo}' >> "$tmp/candidates.jsonl" || true
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
number="$(printf '%s' "$pick" | jq -r '.number')"
title="$(printf '%s' "$pick" | jq -r '.title')"
target="${title#\[migration\] }"

echo "Choisi : $repo#$number — $target"

# Marquer avant de déclencher : un seul tick actif à la fois (verrou global),
# donc pas de risque de double-pick, mais la trace reste utile.
gh issue edit "$number" --repo "$repo" --add-label "$DISPATCHED_LABEL" >/dev/null

echo "Déclenchement : $DISPATCH_WORKFLOW -f target=$target sur $repo"
gh workflow run "$DISPATCH_WORKFLOW" --repo "$repo" -f "target=$target"

sleep 8
run_json="$(gh run list --repo "$repo" --workflow "$DISPATCH_WORKFLOW" --limit 1 \
  --json databaseId,url,status,createdAt)"
run_id="$(printf '%s' "$run_json" | jq -r '.[0].databaseId')"
run_url="$(printf '%s' "$run_json" | jq -r '.[0].url')"

if [ -z "$run_id" ] || [ "$run_id" = "null" ]; then
  gh issue edit "$number" --repo "$repo" --add-label "$FAILED_LABEL" >/dev/null
  gh issue comment "$number" --repo "$repo" \
    --body "⚠️ Déclenchement envoyé mais aucun run retrouvé sur \`$DISPATCH_WORKFLOW\` — vérifier à la main (workflow absent sur ce dépôt ? PAT sans \`actions:write\` ?)." >/dev/null
  echo "::error::run introuvable après dispatch"
  exit 1
fi

gh issue comment "$number" --repo "$repo" \
  --body "File d'attente : run déclenché → $run_url (\`$DISPATCH_WORKFLOW\`, cible \`$target\`)." >/dev/null

echo "Run : $run_url — attente de la fin (tient le verrou global)…"
set +e
gh run watch "$run_id" --repo "$repo" --exit-status
rc=$?
set -e

pr_title="[agent] Migration ${target}"
pr_json="$(gh pr list --repo "$repo" --state open --search "in:title \"${pr_title}\"" \
  --json number,url --limit 5 2>/dev/null || echo '[]')"
pr_url="$(printf '%s' "$pr_json" | jq -r '.[0].url // empty')"

if [ "$rc" -eq 0 ] && [ -n "$pr_url" ]; then
  gh issue comment "$number" --repo "$repo" \
    --body "Run terminé → PR ouverte : $pr_url (reste en **Draft**, relecture humaine avant fusion)." >/dev/null
  gh issue close "$number" --repo "$repo" --reason completed >/dev/null
  echo "OK : $pr_url"
else
  gh issue edit "$number" --repo "$repo" --add-label "$FAILED_LABEL" >/dev/null
  gh issue comment "$number" --repo "$repo" \
    --body "⚠️ Run terminé en échec, ou sans PR retrouvée : $run_url. **Pas de nouvelle tentative automatique** — vérifier (logs du run, fichier de suivi \`.agents/runs/\`), puis retirer le label \`$FAILED_LABEL\` pour remettre en file." >/dev/null
  echo "ÉCHEC (rc=$rc) — voir $run_url"
fi
