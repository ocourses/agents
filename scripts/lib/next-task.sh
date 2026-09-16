#!/usr/bin/env bash
# Sélection de la prochaine tâche éligible — extrait de queue-next.sh pour
# être appelé aussi par un tick local (voir LOCAL-QUEUE.md), sans dupliquer
# la logique : SOURCE UNIQUE pour l'ordre de la file (la plus ancienne
# d'abord, tous dépôts de COURSE_REPOS_FILE et toutes natures confondues) et
# pour le mapping label -> rôle -> titre -> tâche. Le chemin automatisé
# (queue-next.sh) et le chemin manuel doivent voir exactement la même
# prochaine tâche et lui donner exactement le même travail à faire — toute
# divergence entre les deux romprait la promesse « même décorum, même
# critère de succès » que fait LOCAL-QUEUE.md.
#
# Ne réclame rien (voir scripts/claim-issue.sh) : ne fait que lire, nettoyer
# les réclamations abandonnées, et choisir. Le ramasse-miettes tourne ici
# (pas seulement dans queue-next.sh) pour qu'un tick local en bénéficie
# aussi, sans dépendre du cron de queue.yml.
#
# Entrées :
#   GH_TOKEN            PAT (ou GH_TOKEN équivalent) avec, sur chaque dépôt
#                        de COURSE_REPOS_FILE : Issues (lire/écrire, pour le
#                        ramasse-miettes).
#   COURSE_REPOS_FILE   défaut: config/course-repos.txt
#   STALE_HOURS         au-delà, une réclamation sans résolution est
#                        considérée abandonnée (défaut 3).
#
# Sortie : UNE LIGNE JSON sur stdout, rien d'autre (tous les messages
# informatifs vont sur stderr, pour rester capturable proprement par
# `result="$(bash next-task.sh)"`).
#   Rien d'éligible : {"eligible_count":0}
#   Sinon           : {"eligible_count":N,"repo":"owner/repo",
#                      "kind":"migration|conventions|fix","number":123,
#                      "title":"[migration] poly/foo.tex","target":"poly/foo.tex",
#                      "role":"latex-template-migrator",
#                      "workflow":"agent-migrate-latex.yml",
#                      "task_title":"Migration poly/foo.tex","task":"..."}
#   task_title/task reproduisent EXACTEMENT les inputs title=/task= que les
#   trois workflows agent-migrate-latex.yml / agent-review-conventions.yml /
#   agent-fix-conventions.yml passent à agent.yml dans les dépôts de cours —
#   à garder en phase si ces workflows changent leur texte de tâche.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAIM_SCRIPT="${SCRIPT_DIR}/../claim-issue.sh"
COURSE_REPOS_FILE="${COURSE_REPOS_FILE:-config/course-repos.txt}"
STALE_HOURS="${STALE_HOURS:-3}"
DISPATCHED_LABEL="agent:dispatched"
FAILED_LABEL="agent:failed"

: "${GH_TOKEN:?GH_TOKEN requis (voir en-tête de ce script)}"
[ -f "$COURSE_REPOS_FILE" ] || { echo "::error::$COURSE_REPOS_FILE introuvable" >&2; exit 1; }

mapfile -t repos < <(grep -vE '^[[:space:]]*(#|$)' "$COURSE_REPOS_FILE")
if [ "${#repos[@]}" -eq 0 ]; then
  echo "Aucun dépôt listé dans $COURSE_REPOS_FILE — rien à faire." >&2
  jq -n '{eligible_count:0}'
  exit 0
fi
echo "Dépôts surveillés : ${repos[*]}" >&2

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
: > "$tmp/candidates.jsonl"

# -----------------------------------------------------------------------
# Ramasse-miettes — identique à l'ancien reap_stale_claims de queue-next.sh
# (voir son historique pour le contexte complet) : une réclamation
# (agent:dispatched) sans résolution depuis plus de STALE_HOURS est
# considérée abandonnée (run tué avant sa gestion d'échec, ou session locale
# interrompue sans aller jusqu'à `release`/`fail`).
# -----------------------------------------------------------------------
reap_stale_claims() {
  local repo="$1" now_epoch claim_epoch age_h num claim_at
  now_epoch="$(date -u +%s)"
  while read -r num; do
    [ -n "$num" ] || continue
    claim_at="$(gh issue view "$num" --repo "$repo" --json comments \
      --jq '[.comments[] | select(.body | startswith("🔒 Prise en charge"))] | last | .createdAt // empty' 2>/dev/null)"
    [ -n "$claim_at" ] || continue
    claim_epoch="$(date -u -d "$claim_at" +%s 2>/dev/null)" || continue
    age_h=$(( (now_epoch - claim_epoch) / 3600 ))
    if [ "$age_h" -ge "$STALE_HOURS" ]; then
      echo "::warning::$repo#$num réclamée depuis ${age_h}h (>= ${STALE_HOURS}h) sans résolution — marquée en échec." >&2
      bash "$CLAIM_SCRIPT" fail "$repo" "$num" \
        "réclamée depuis plus de ${STALE_HOURS}h sans résolution (run interrompu, ou session locale abandonnée) — vérification humaine nécessaire" || true
    fi
  done < <(gh issue list --repo "$repo" --label "$DISPATCHED_LABEL" --state open --json number --jq '.[].number' --limit 200 2>/dev/null)
}

for repo in "${repos[@]}"; do
  reap_stale_claims "$repo"

  gh issue list --repo "$repo" --label "template-migration" --state open \
    --json number,title,createdAt,labels --limit 200 2>/dev/null \
  | jq -c --arg repo "$repo" --arg kind "migration" \
      '.[] | . + {repo: $repo, kind: $kind}' >> "$tmp/candidates.jsonl" || true

  gh issue list --repo "$repo" --label "conventions-candidate" --state open \
    --json number,title,createdAt,labels --limit 200 2>/dev/null \
  | jq -c --arg repo "$repo" --arg kind "conventions" \
      '.[] | . + {repo: $repo, kind: $kind}' >> "$tmp/candidates.jsonl" || true

  gh issue list --repo "$repo" --label "conventions-style" --state open \
    --json number,title,createdAt,labels --limit 200 2>/dev/null \
  | jq -c --arg repo "$repo" --arg kind "fix" \
      '.[] | . + {repo: $repo, kind: $kind}' >> "$tmp/candidates.jsonl" || true
done

jq -s --arg d "$DISPATCHED_LABEL" --arg f "$FAILED_LABEL" '
  [ .[] | select(([.labels[].name] | index($d)) == null and ([.labels[].name] | index($f)) == null) ]
  | sort_by(.createdAt)
' "$tmp/candidates.jsonl" > "$tmp/eligible.json"

n="$(jq 'length' "$tmp/eligible.json")"
echo "Candidats éligibles : $n" >&2

if [ "$n" -eq 0 ]; then
  jq -n '{eligible_count:0}'
  exit 0
fi

pick="$(jq -c '.[0]' "$tmp/eligible.json")"
repo="$(printf '%s' "$pick" | jq -r '.repo')"
kind="$(printf '%s' "$pick" | jq -r '.kind')"
number="$(printf '%s' "$pick" | jq -r '.number')"
title="$(printf '%s' "$pick" | jq -r '.title')"
target="${title#\[*\] }"

case "$kind" in
  migration)
    workflow="agent-migrate-latex.yml"
    role="latex-template-migrator"
    task_title="Migration ${target}"
    task="Migre le document ${target} vers le template ocots en suivant le rôle latex-template-migrator. Si ce fichier porte \\documentclass, migre aussi tous les fichiers qu'il inclut via \\input / \\include, récursivement : ils partagent le préambule et doivent bouger ensemble pour que le document compile. Le fond (énoncés, formules, valeurs, ordre des questions) reste identique caractère pour caractère."
    ;;
  conventions)
    workflow="agent-review-conventions.yml"
    role="conventions-reviewer"
    task_title="Triage conventions ${target} (#${number})"
    task="Trie le candidat conventions ouvert dans l'issue #${number} (fichier ${target}) en suivant le rôle conventions-reviewer : relis le fichier autour de chaque ligne signalée, décide confirmée / faux positif / exception légitime, puis modifie CETTE issue (jamais une nouvelle) — ferme-la avec le motif de chaque rejet si rien n'est confirmé, ou réécris son corps et remplace le label conventions-candidate par conventions-style si au moins un point est confirmé. Ne modifie aucun fichier du dépôt."
    ;;
  fix)
    workflow="agent-fix-conventions.yml"
    role="conventions-fixer"
    task_title="Correction conventions ${target}"
    task="Corrige les points CONFIRMÉS de l'issue conventions-style #${number} (fichier ${target}) en suivant le rôle conventions-fixer : relis l'issue (verdicts déjà rendus par conventions-reviewer, pas la sortie brute du détecteur), applique le remède documenté par ocots-conventions pour chaque règle citée, uniquement sur les points confirmés — rien d'autre dans le fichier. Un remède qui demande un choix d'auteur (ex. C2 entre deux formes réellement équivalentes) : ne tranche pas, laisse la ligne en l'état et signale-le dans le bilan."
    ;;
  *)
    echo "::error::nature de tâche inconnue : $kind" >&2
    exit 1
    ;;
esac

jq -n \
  --argjson eligible_count "$n" \
  --arg repo "$repo" --arg kind "$kind" --argjson number "$number" \
  --arg title "$title" --arg target "$target" --arg role "$role" \
  --arg workflow "$workflow" --arg task_title "$task_title" --arg task "$task" \
  '{eligible_count:$eligible_count, repo:$repo, kind:$kind, number:$number,
    title:$title, target:$target, role:$role, workflow:$workflow,
    task_title:$task_title, task:$task}'
