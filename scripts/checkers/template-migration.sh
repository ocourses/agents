#!/usr/bin/env bash
# Couche « détecteur » — scanne un dépôt de cours pour repérer les documents
# .tex qui ne sont pas (ou pas complètement) migrés vers le template `ocots`,
# et ouvre une issue par document non conforme. Déterministe, aucun appel
# modèle : c'est un grep, pas un agent.
#
# La détection elle-même (extraction des noms legacy, chaîne \input/\include
# récursive, classification MISSING/LEGACY/CLEAN) est déléguée à
# scripts/lib/template-scan.sh — composant PARTAGÉ avec la revérification
# post-run de scripts/queue-next.sh (ocourses/agents#15) : le détecteur
# hebdomadaire et le vérificateur de fin de run doivent rendre le même
# verdict sur le même arbre, sans jamais diverger — une copie divergée
# recréerait exactement la boucle « run vide → issue rouverte » que ce
# partage élimine.
#
# Deux statuts détectés :
#   MISSING — le pilote n'a pas \usepackage[...]{ocots} (jamais migré, ex.
#             encore sur tpN7.sty/Jgbook). Signal volontairement unique : les
#             classes cibles varient selon le support (ocots-td/book/exam pour
#             TD/poly/examen, mais \documentclass{beamer} + \usepackage{ocots}
#             pour les diapositives, pas de classe ocots-* dédiée) — seul
#             \usepackage{ocots} est constant partout.
#   LEGACY  — le pilote est migré, mais lui ou sa chaîne \input utilise
#             encore un nom de tex/ocots-compat.sty (migration partielle)
#
# La liste des noms « legacy » est extraite de ocots-compat.sty à chaque run
# (dans le script partagé), pas codée en dur : le fichier maigrit au fil des
# migrations (cf. son en-tête), le détecteur se resserre tout seul.
#
# Entrées (variables d'environnement) :
#   REPO       owner/name du dépôt scanné (défaut: $GITHUB_REPOSITORY)
#   GH_TOKEN   jeton gh avec issues:write sur $REPO
#   TEMPLATE_DIR  chemin du sous-module template (défaut: template)
#   DISPATCH_WORKFLOW  nom du workflow de migration à suggérer dans l'issue
#                       (défaut: agent-migrate-latex.yml)
#   IGNORE_FILE   fichier de préfixes à exclure, propre au dépôt de cours
#                 (défaut: .agents-ignore, à la racine — un préfixe de chemin
#                 par ligne, ex. "slides/", "#" pour commenter). Absent =
#                 aucune exclusion, comportement inchangé. Sert à un choix
#                 spécifique à UN cours (ex. slides pas encore prêtes pour ce
#                 traitement) — pas une règle du template, sinon elle serait
#                 dans ce script, pas dans un fichier par dépôt.
#   SCAN          chemin du script de détection partagé
#                 (défaut: ../lib/template-scan.sh, relatif à ce script)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${REPO:-${GITHUB_REPOSITORY:-}}"
TEMPLATE_DIR="${TEMPLATE_DIR:-template}"
IGNORE_FILE="${IGNORE_FILE:-.agents-ignore}"
DISPATCH_WORKFLOW="${DISPATCH_WORKFLOW:-agent-migrate-latex.yml}"
SCAN="${SCAN:-${SCRIPT_DIR}/../lib/template-scan.sh}"
LABEL="template-migration"
COMPAT="${TEMPLATE_DIR}/tex/ocots-compat.sty"

: "${REPO:?REPO requis}"
: "${GH_TOKEN:?GH_TOKEN requis}"
[ -f "$COMPAT" ] || { echo "::error::compat introuvable : $COMPAT (sous-module template initialisé ?)"; exit 1; }
[ -f "$SCAN" ] || { echo "::error::script de détection introuvable : $SCAN"; exit 1; }

echo "Dépôt : $REPO"
echo "Compat : $COMPAT"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# --- exclusions propres à ce dépôt (IGNORE_FILE), en plus des sous-modules --
# ATTENTION : `grep -vf` avec un fichier de motifs VIDE élimine tout au lieu
# de rien sur certains grep (confirmé en test) — d'où la branche explicite
# ci-dessous plutôt que de compter sur ce comportement, quel que soit le grep
# du runner.
: > "$tmp/ignore-patterns.txt"
if [ -f "$IGNORE_FILE" ]; then
  grep -vE '^[[:space:]]*(#|$)' "$IGNORE_FILE" \
    | sed -E 's/[.[\*^$()+?{|]/\\&/g; s/^/^/' \
    > "$tmp/ignore-patterns.txt"
fi
n_ignore=$(wc -l < "$tmp/ignore-patterns.txt")
[ "$n_ignore" -gt 0 ] && echo "Exclusions ($IGNORE_FILE) : $n_ignore motif(s)"

# ---------------------------------------------------------------------------
# Repérer les fichiers pilotes (\documentclass), hors template/, conventions/
# et les exclusions de IGNORE_FILE
# ---------------------------------------------------------------------------
# Fichier intermédiaire + `if` explicite plutôt qu'un `&&/||` en pipeline : ce
# dernier n'est PAS un if/then/else (un `grep -v` qui filtre tout sort en
# échec, ce qui déclencherait aussi la branche `||`) — piège classique, évité
# ici en le rendant sans ambiguïté.
grep -rlZ --include='*.tex' '\\documentclass' . 2>/dev/null \
  | tr '\0' '\n' | sed 's#^\./##' \
  | grep -v "^${TEMPLATE_DIR}/" | grep -v '^conventions/' \
  > "$tmp/candidates-raw.txt" || true

if [ "$n_ignore" -gt 0 ]; then
  mapfile -t pilots < <(grep -vEf "$tmp/ignore-patterns.txt" "$tmp/candidates-raw.txt" 2>/dev/null | sort -u)
else
  mapfile -t pilots < <(sort -u "$tmp/candidates-raw.txt")
fi
echo "Pilotes trouvés : ${#pilots[@]}"

# ---------------------------------------------------------------------------
# Classification — déléguée au script partagé (voir en-tête) : une ligne TSV
# "STATUT<TAB>pilote<TAB>noms" par pilote. La redirection (plutôt qu'une
# process substitution) propage un échec du scan sous `set -e`.
# ---------------------------------------------------------------------------
: > "$tmp/verdicts.tsv"
if [ "${#pilots[@]}" -gt 0 ]; then
  bash "$SCAN" "$COMPAT" "${pilots[@]}" > "$tmp/verdicts.tsv"
fi

# ---------------------------------------------------------------------------
# Ouverture d'issue par pilote non conforme
# ---------------------------------------------------------------------------
gh label create "$LABEL" --repo "$REPO" --color 0e8a16 \
  --description "Document détecté non conforme au template ocots" 2>/dev/null || true

# --limit 300 : sans limite explicite `gh issue list` tronque à 30 — les
# titres au-delà sortiraient de la dédup et un pilote déjà signalé serait
# re-signalé en doublon (ocourses/agents#14).
existing_titles="$(gh issue list --repo "$REPO" --label "$LABEL" --state open \
  --json title --jq '.[].title' --limit 300 2>/dev/null || true)"

n_missing=0; n_legacy=0; n_skipped=0

while IFS=$'\t' read -r status pilot found_names; do
  [ -n "$status" ] || continue
  [ "$status" = "CLEAN" ] && { n_skipped=$((n_skipped+1)); continue; }

  title="[migration] $pilot"
  if printf '%s\n' "$existing_titles" | grep -qxF "$title"; then
    echo "  = déjà signalé : $pilot"
    continue
  fi

  body_file="$tmp/issue-body.md"
  {
    echo "**Statut :** \`$status\`"
    echo
    if [ "$status" = "MISSING" ]; then
      echo "Ce pilote n'utilise aucune classe \`ocots-*\` / \`\\usepackage{ocots}\` : jamais migré."
    else
      echo "Pilote déjà sur le template \`ocots\`, mais noms hérités de \`ocots-compat.sty\` encore présents dans sa chaîne \`\\input\` :"
      echo
      printf '%s' "$found_names" | tr ' ' '\n' | sed 's/^/- `/; s/$/`/'
    fi
    echo
    echo "---"
    echo "Pour lancer la migration (revue humaine avant fusion, comme toujours) :"
    echo
    echo '```'
    echo "gh workflow run ${DISPATCH_WORKFLOW} -f target=${pilot}"
    echo '```'
    echo
    echo "_Détecté automatiquement par \`checkers/template-migration.sh\` (\`ocourses/agents\`)._"
  } > "$body_file"

  gh issue create --repo "$REPO" --title "$title" --label "$LABEL" --body-file "$body_file" >/dev/null
  echo "  + issue créée ($status) : $pilot"

  [ "$status" = "MISSING" ] && n_missing=$((n_missing+1)) || n_legacy=$((n_legacy+1))
done < "$tmp/verdicts.tsv"

echo
echo "Résumé : $n_missing MISSING, $n_legacy LEGACY, $n_skipped déjà conforme(s)/ignoré(s)."
