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
# Trois natures de tâches, trois workflows cibles :
#
#   label source              -> workflow                        -> rôle
#   template-migration        -> agent-migrate-latex.yml          -> latex-template-migrator
#   conventions-candidate     -> agent-review-conventions.yml     -> conventions-reviewer
#   conventions-style         -> agent-fix-conventions.yml        -> conventions-fixer
#
# `conventions-candidate` (sortie brute de checkers/conventions.sh) n'est
# JAMAIS traité comme un verdict : l'agent conventions-reviewer relit et
# décide (confirme -> conventions-style, ou rejette -> ferme). Comme il
# appelle Albert, il passe par cette même file — pas de traitement à part.
#
# `conventions-style` (verdict confirmé, écrit par conventions-reviewer) est
# ensuite repris par conventions-fixer, qui corrige le texte pour les points
# confirmés et ouvre une PR — succès = PR retrouvée sur la branche du run.
#
# `migration` ajoute une REVÉRIFICATION DE FOND à ce critère : « une PR
# existe » seul laisserait passer un diff vide — l'issue fermée completed
# serait recréée identique par le checker hebdomadaire, qui ne déduplique
# que sur les issues ouvertes (ocourses/agents#15). Après le run, la
# branche de la PR est re-scannée par scripts/lib/template-scan.sh — le
# MÊME composant que le détecteur checkers/template-migration.sh, pour que
# les deux verdicts ne divergent jamais. Succès = PR trouvée ET plus aucun
# nom de ocots-compat.sty dans la chaîne \input du pilote cible.
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
#
# La SÉLECTION de la prochaine tâche (parcours des dépôts, ramasse-miettes
# des réclamations abandonnées, mapping label -> rôle -> titre -> tâche) et
# la REVÉRIFICATION post-run d'une migration vivent dans scripts/lib/
# (next-task.sh, rescan-migration.sh) : un tick local (voir LOCAL-QUEUE.md)
# les appelle telles quelles, pour ne jamais diverger de ce script sur ce
# qui compte comme « prochaine tâche » ou « migration réussie ».
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

: "${GH_TOKEN:?GH_TOKEN requis (PAT dédié, voir en-tête du script)}"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

result="$(bash "$SCRIPT_DIR/lib/next-task.sh")"
n="$(printf '%s' "$result" | jq -r '.eligible_count')"
if [ "$n" -eq 0 ]; then
  echo "File vide : rien à traiter."
  exit 0
fi

repo="$(printf '%s' "$result" | jq -r '.repo')"
kind="$(printf '%s' "$result" | jq -r '.kind')"
number="$(printf '%s' "$result" | jq -r '.number')"
target="$(printf '%s' "$result" | jq -r '.target')"
dispatch_workflow="$(printf '%s' "$result" | jq -r '.workflow')"

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
# Revérification post-run d'une migration (ocourses/agents#15) — « une PR
# existe » ne suffit pas : un diff vide fermerait l'issue completed, que le
# checker hebdomadaire recréerait identique au passage suivant (dédup sur
# les issues ouvertes seulement) → boucle de runs vides. Extraite dans
# scripts/lib/rescan-migration.sh (voir son en-tête) pour être appelée aussi
# par un tick local — même composant, même verdict, dans les deux chemins.
# ---------------------------------------------------------------------------
rescan_migration() {
  bash "$SCRIPT_DIR/lib/rescan-migration.sh" "$1" "$2" "$3"
}

# ---------------------------------------------------------------------------
# Vérification du succès : le critère dépend de la nature de la tâche.
#
# migration et fix partagent la même mécanique — l'agent (latex-template-
# migrator / conventions-fixer) fait le travail directement et ouvre sa PR
# via scaffold.sh (titre "[agent] <Titre> <cible>", cf. agent-migrate-latex.yml
# / agent-fix-conventions.yml) : on la retrouve par branche, PR trouvée =
# succès, l'issue d'origine est fermée (le lien natif link_issue la referait
# de toute façon à la fusion, mais on ne l'attend pas — même convention que
# migration). migration AJOUTE la revérification ci-dessus à ce critère ;
# fix garde « PR trouvée » seul.
# conventions (triage) est différent : l'agent modifie l'issue lui-même,
# jamais une PR de contenu ; on vérifie son état après coup.
# ---------------------------------------------------------------------------
success=0
fail_reason=""
case "$kind" in
  migration|fix)
    # Recherche par NOM DE BRANCHE (`agent/<slug>-<run_id>`, cf. scaffold.sh),
    # pas par titre : `gh pr list --search` interroge l'index de recherche
    # GitHub, qui peut avoir un léger retard sur l'API liste juste après un
    # push — faux `agent:failed` observé sur ocourses/automatique-enseignants#139
    # (la requête rejouée plus tard trouvait la PR). `run_id` (capturé plus
    # haut) suffit à isoler LA branche de CE run précis, sans reconstruire le
    # slug exact — lui dépend de TITLE, calculé dans scaffold.sh, inconnu ici.
    if ! pr_json="$(gh pr list --repo "$repo" --state open \
        --json number,url,headRefName --limit 200 2>"$tmp/pr-list.err")"; then
      echo "::warning::$repo — gh pr list a échoué après le run ($run_url) : $(cat "$tmp/pr-list.err")"
      pr_json='[]'
    fi
    pr_entry="$(printf '%s' "$pr_json" | jq -c --arg suffix "-${run_id}" \
      '[.[] | select(.headRefName | startswith("agent/") and endswith($suffix))] | .[0] // empty')"
    pr_url="$(printf '%s' "$pr_entry" | jq -r '.url // empty')"
    pr_branch="$(printf '%s' "$pr_entry" | jq -r '.headRefName // empty')"
    if [ "$rc" -eq 0 ] && [ -n "$pr_url" ]; then
      if [ "$kind" = "migration" ]; then
        set +e
        verdict="$(rescan_migration "$repo" "$pr_branch" "$target" 2>"$tmp/rescan.err")"
        vrc=$?
        set -e
        if [ "$vrc" -ne 0 ] || [ -z "$verdict" ]; then
          fail_reason="PR ouverte ($pr_url) mais revérification impossible — $(tail -n 1 "$tmp/rescan.err" 2>/dev/null || echo 'voir les logs du tick')"
        else
          vstatus="$(cut -f1 <<<"$verdict")"
          vnames="$(cut -f3- <<<"$verdict")"
          echo "Revérification $target : $vstatus${vnames:+ ($vnames)}"
          if [ "$vstatus" != "CLEAN" ]; then
            fail_reason="PR ouverte ($pr_url) mais \`$target\` reste non conforme (statut $vstatus)${vnames:+ — noms de \`ocots-compat.sty\` encore présents : $vnames} — le diff n'élimine pas tous les anciens noms."
          fi
        fi
      fi
      if [ -z "$fail_reason" ]; then
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
    fi
    ;;
  conventions)
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
    ;;
esac

if [ "$success" -ne 1 ]; then
  bash "$SCRIPT_DIR/claim-issue.sh" fail "$repo" "$number" \
    "${fail_reason:-run terminé en échec, ou sans résultat exploitable : $run_url — vérifier les logs et le fichier de suivi \`.agents/runs/\`}"
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
