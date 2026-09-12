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
#   CHAIN               rang du tick dans la chaîne (défaut 0, cf. plus bas)
#   MAX_CHAIN           nombre maximum de ticks enchaînés (défaut 6)
#   GITHUB_REPOSITORY   dépôt hôte, pour se redéclencher soi-même
#   STALE_HOURS         au-delà, une réclamation sans résolution est
#                        considérée abandonnée (défaut 3, cf. reap_stale_claims)
#
# La réclamation d'une issue (label agent:dispatched, commentaire de prise en
# charge, libération, échec) passe par scripts/claim-issue.sh — SOURCE UNIQUE
# du protocole, partagée avec tout travail manuel (une session Claude Code
# locale, ou toi directement) qui prendrait une issue sans passer par cette
# file. Les deux acteurs DOIVENT utiliser le même protocole pour ne pas se
# marcher dessus : voir l'en-tête de claim-issue.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COURSE_REPOS_FILE="${COURSE_REPOS_FILE:-config/course-repos.txt}"
STALE_HOURS="${STALE_HOURS:-3}"
# Dupliqués depuis claim-issue.sh (doivent rester identiques) : nécessaires
# ici pour filtrer les candidats côté lecture (gh issue list --label, jq).
DISPATCHED_LABEL="agent:dispatched"
FAILED_LABEL="agent:failed"

: "${GH_TOKEN:?GH_TOKEN requis (PAT dédié, voir en-tête du script)}"
[ -f "$COURSE_REPOS_FILE" ] || { echo "::error::$COURSE_REPOS_FILE introuvable"; exit 1; }

mapfile -t repos < <(grep -vE '^[[:space:]]*(#|$)' "$COURSE_REPOS_FILE")
[ "${#repos[@]}" -gt 0 ] || { echo "Aucun dépôt listé dans $COURSE_REPOS_FILE — rien à faire."; exit 0; }
echo "Dépôts surveillés : ${repos[*]}"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
: > "$tmp/candidates.jsonl"

# -----------------------------------------------------------------------
# Ramasse-miettes — une réclamation (agent:dispatched) sans résolution
# depuis plus de STALE_HOURS est considérée abandonnée : run GitHub Actions
# annulé/tué avant sa propre gestion d'échec, ou session locale interrompue
# (Ctrl-C, machine éteinte) sans être allée jusqu'à `claim-issue.sh release`
# ou `fail`. Sans ce filet, une telle issue resterait réclamée pour de bon,
# invisible et jamais retraitée. On se base sur le commentaire de prise en
# charge posté par `claim claim` (source de vérité — l'ancienneté du label
# lui-même n'est pas exposée par l'API issues).
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
      echo "::warning::$repo#$num réclamée depuis ${age_h}h (>= ${STALE_HOURS}h) sans résolution — marquée en échec."
      bash "$SCRIPT_DIR/claim-issue.sh" fail "$repo" "$num" \
        "réclamée depuis plus de ${STALE_HOURS}h sans résolution (run interrompu, ou session locale abandonnée) — vérification humaine nécessaire" || true
    fi
  done < <(gh issue list --repo "$repo" --label "$DISPATCHED_LABEL" --state open --json number --jq '.[].number' 2>/dev/null)
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

# Réclamer avant de déclencher. Le verrou global GitHub Actions garantit
# qu'aucun AUTRE tick automatisé n'est actif en même temps — mais rien
# n'empêche un travail manuel (Claude Code local) d'avoir réclamé cette même
# issue entre la lecture de la liste et cet instant. Course rare (protocole
# partagé, un seul humain à la fois), mais gérée : si `claim` échoue, on
# s'arrête proprement plutôt que de dupliquer le travail.
if ! bash "$SCRIPT_DIR/claim-issue.sh" claim "$repo" "$number" "file d'attente automatique"; then
  echo "::warning::$repo#$number réclamée entre-temps par quelqu'un d'autre — on s'arrête ce tour-ci."
  exit 0
fi

# Les deux workflows cibles acceptent désormais issue= (numéro de la
# template-migration / conventions-candidate d'origine) : côté migration,
# ça permet à agent.yml de fermer nativement cette issue via link_issue
# (Closes #N dans la PR), plutôt que par le seul commentaire posé plus bas.
echo "Déclenchement : $dispatch_workflow -f target=$target -f issue=$number sur $repo"
gh workflow run "$dispatch_workflow" --repo "$repo" -f "target=$target" -f "issue=$number"

sleep 8
run_json="$(gh run list --repo "$repo" --workflow "$dispatch_workflow" --limit 1 \
  --json databaseId,url,status,createdAt)"
run_id="$(printf '%s' "$run_json" | jq -r '.[0].databaseId')"
run_url="$(printf '%s' "$run_json" | jq -r '.[0].url')"

if [ -z "$run_id" ] || [ "$run_id" = "null" ]; then
  bash "$SCRIPT_DIR/claim-issue.sh" fail "$repo" "$number" \
    "déclenchement envoyé mais aucun run retrouvé sur \`$dispatch_workflow\` (workflow absent sur ce dépôt ? PAT sans \`actions:write\` ?)"
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
    # Issue fermée : `agent:dispatched` n'a plus d'effet sur l'éligibilité,
    # mais on le retire quand même pour que `claim-issue.sh status` reste
    # exact si l'issue est rouverte un jour (revert de la PR, etc.).
    bash "$SCRIPT_DIR/claim-issue.sh" release "$repo" "$number" >/dev/null
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
    # L'issue reste OPEN si promue conventions-style (relecture humaine) :
    # sans ce release, `agent:dispatched` restait collé pour de bon — bug
    # constaté en pratique (issues #54, #55) avant ce correctif.
    bash "$SCRIPT_DIR/claim-issue.sh" release "$repo" "$number" >/dev/null
    echo "OK : candidat traité par l'agent (état: $state)"
  fi
fi

if [ "$success" -ne 1 ]; then
  bash "$SCRIPT_DIR/claim-issue.sh" fail "$repo" "$number" \
    "run terminé en échec, ou sans résultat exploitable : $run_url — vérifier les logs et le fichier de suivi \`.agents/runs/\`"
  echo "ÉCHEC (rc=$rc) — voir $run_url"
fi

# ---------------------------------------------------------------------------
# Auto-chaînage — c'est LUI qui vide la file, pas le cron.
#
# Un tick = une tâche. Avec ~190 tâches en attente, compter sur le cron pour
# les enchaîner supposerait qu'il parte à l'heure à chaque fois ; il ne part
# pas du tout ici (voir l'en-tête de queue.yml). On se redéclenche donc
# soi-même tant qu'il reste du travail, et le cron horaire ne sert plus qu'à
# rallumer une chaîne éteinte.
#
# Deux conditions d'arrêt, volontairement strictes :
#   - plus rien d'éligible (n <= 1 : la seule tâche du tour était la nôtre) ;
#   - plafond MAX_CHAIN atteint, pour qu'une file qui se remplit toute seule
#     (détecteurs hebdomadaires) ne puisse pas boucler indéfiniment.
#
# Le redéclenchement passe par le PAT, pas par github.token : un dispatch émis
# avec le jeton par défaut ne crée PAS de nouveau run (garde-fou anti-récursion
# de GitHub Actions). D'où la nécessité que AGENTS_DISPATCH_TOKEN porte aussi
# sur ocourses/agents lui-même, en Actions:write.
# ---------------------------------------------------------------------------
CHAIN="${CHAIN:-0}"
MAX_CHAIN="${MAX_CHAIN:-6}"
SELF_REPO="${GITHUB_REPOSITORY:-ocourses/agents}"

if [ "$n" -le 1 ]; then
  echo "File vidée (aucune autre tâche éligible ce tour-ci) — la chaîne s'arrête."
  exit 0
fi

next=$(( CHAIN + 1 ))
if [ "$next" -ge "$MAX_CHAIN" ]; then
  echo "Plafond de $MAX_CHAIN ticks enchaînés atteint — il reste environ $(( n - 1 )) tâche(s)."
  echo "Le prochain cron (horaire) rallumera la chaîne ; ou relancer à la main."
  exit 0
fi

echo "Tick $next/$MAX_CHAIN — environ $(( n - 1 )) tâche(s) restante(s), on enchaîne."
if gh workflow run queue.yml --repo "$SELF_REPO" \
     -f chain="$next" -f max_chain="$MAX_CHAIN"; then
  echo "Tick suivant déclenché sur $SELF_REPO."
else
  echo "::warning::redéclenchement impossible — AGENTS_DISPATCH_TOKEN porte-t-il"
  echo "::warning::sur $SELF_REPO avec Actions:write ? La chaîne s'arrête ici ;"
  echo "::warning::le cron horaire prendra le relais."
fi
