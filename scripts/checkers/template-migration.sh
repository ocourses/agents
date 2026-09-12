#!/usr/bin/env bash
# Couche « détecteur » — scanne un dépôt de cours pour repérer les documents
# .tex qui ne sont pas (ou pas complètement) migrés vers le template `ocots`,
# et ouvre une issue par document non conforme. Déterministe, aucun appel
# modèle : c'est un grep, pas un agent.
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
# La liste des noms « legacy » est extraite de ocots-compat.sty à chaque run,
# pas codée en dur : le fichier maigrit au fil des migrations (cf. son
# en-tête), le détecteur se resserre tout seul.
#
# Entrées (variables d'environnement) :
#   REPO       owner/name du dépôt scanné (défaut: $GITHUB_REPOSITORY)
#   GH_TOKEN   jeton gh avec issues:write sur $REPO
#   TEMPLATE_DIR  chemin du sous-module template (défaut: template)
#   DISPATCH_WORKFLOW  nom du workflow de migration à suggérer dans l'issue
#                       (défaut: agent-migrate-latex.yml)
set -euo pipefail

REPO="${REPO:-${GITHUB_REPOSITORY:-}}"
TEMPLATE_DIR="${TEMPLATE_DIR:-template}"
DISPATCH_WORKFLOW="${DISPATCH_WORKFLOW:-agent-migrate-latex.yml}"
LABEL="template-migration"
COMPAT="${TEMPLATE_DIR}/tex/ocots-compat.sty"

: "${REPO:?REPO requis}"
: "${GH_TOKEN:?GH_TOKEN requis}"
[ -f "$COMPAT" ] || { echo "::error::compat introuvable : $COMPAT (sous-module template initialisé ?)"; exit 1; }

echo "Dépôt : $REPO"
echo "Compat : $COMPAT"

# ---------------------------------------------------------------------------
# 1. Extraire les noms « legacy » depuis ocots-compat.sty
# ---------------------------------------------------------------------------
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# Environnements : \NewDocumentEnvironment{nom} et \ocotsaliasenv{nom}{...}
# (on exclut les noms avec '@' : macros internes du fichier de compat,
# jamais tapées par un auteur de document)
# `grep` sort 1 (pas une erreur) dès qu'un motif ne trouve rien — ça arrive
# légitimement : un dépôt de cours peut pointer un sous-module template plus
# ancien, où telle forme d'alias n'existe pas encore (vu en réel : un sous-
# module figé avant l'introduction de \NewDocumentEnvironment, quand
# `mytheorem` n'était qu'un \ocotsaliasenv simple). Sous `set -e -o
# pipefail`, laisser passer ce 1 tuerait tout le script — chaque motif est
# donc gardé par `|| true`.
{
  grep -oE '\\NewDocumentEnvironment\{[A-Za-z@*]+\}' "$COMPAT" | sed -E 's/.*\{(.*)\}/\1/' || true
  grep -oE '\\ocotsaliasenv\{[A-Za-z@*]+\}' "$COMPAT" | sed -E 's/.*\{(.*)\}/\1/' || true
} | { grep -v '@' || true; } | sort -u > "$tmp/envs.txt"

# Commandes : \newcommand{\nom}, \let\nom... et \DeclareRobustCommand{\nom}
# (ce dernier motif porte à lui seul ~80 alias de macros mathématiques
# renommées par le chantier 2 du template — sans lui le détecteur les rate
# toutes silencieusement, cf. .agents ou le suivi de la PR qui a ajouté cette
# ligne)
{
  grep -oE '\\newcommand\{\\[A-Za-z@]+\}' "$COMPAT" | sed -E 's/.*\{\\(.*)\}/\1/' || true
  grep -oE '^\\let\\[A-Za-z@]+' "$COMPAT" | sed -E 's/^\\let\\//' || true
  grep -oE '\\DeclareRobustCommand\{\\[A-Za-z@]+\}' "$COMPAT" | sed -E 's/.*\{\\(.*)\}/\1/' || true
} | { grep -v '@' || true; } | sort -u > "$tmp/cmds.txt"

n_envs=$(wc -l < "$tmp/envs.txt"); n_cmds=$(wc -l < "$tmp/cmds.txt")
echo "Noms legacy extraits : $n_envs environnement(s), $n_cmds commande(s)"
[ "$n_envs" -gt 0 ] || [ "$n_cmds" -gt 0 ] || { echo "::warning::aucun nom legacy extrait, ocots-compat.sty a-t-il changé de format ?"; }

envs_re="$(paste -sd'|' "$tmp/envs.txt")"
cmds_re="$(paste -sd'|' "$tmp/cmds.txt")"

# ---------------------------------------------------------------------------
# 2. Repérer les fichiers pilotes (\documentclass), hors template/ et conventions/
# ---------------------------------------------------------------------------
mapfile -t pilots < <(
  grep -rlZ --include='*.tex' '\\documentclass' . 2>/dev/null \
  | tr '\0' '\n' | sed 's#^\./##' \
  | grep -v "^${TEMPLATE_DIR}/" | grep -v '^conventions/' | sort -u
)
echo "Pilotes trouvés : ${#pilots[@]}"

# ---------------------------------------------------------------------------
# 3. Chaîne \input / \include, récursive (avec garde anti-cycle)
# ---------------------------------------------------------------------------
collect_chain() {
  local file="$1" seen_var="$2"
  [ -f "$file" ] || return 0
  case " $(eval echo \$"$seen_var") " in *" $file "*) return 0 ;; esac
  eval "$seen_var=\"\$$seen_var $file\""
  echo "$file"
  local dir; dir="$(dirname "$file")"
  { grep -oE '\\(input|include)\{[^}]+\}' "$file" 2>/dev/null || true; } \
    | sed -E 's/.*\{(.*)\}/\1/' \
    | while IFS= read -r inc; do
        local incfile="$inc"
        [[ "$incfile" == *.tex ]] || incfile="${incfile}.tex"
        local candidate="$dir/$incfile"
        candidate="${candidate#./}"
        collect_chain "$candidate" "$seen_var"
      done
}

# ---------------------------------------------------------------------------
# 4. Classification + ouverture d'issue
# ---------------------------------------------------------------------------
gh label create "$LABEL" --repo "$REPO" --color 0e8a16 \
  --description "Document détecté non conforme au template ocots" 2>/dev/null || true

existing_titles="$(gh issue list --repo "$REPO" --label "$LABEL" --state open \
  --json title --jq '.[].title' 2>/dev/null || true)"

n_missing=0; n_legacy=0; n_skipped=0

for pilot in "${pilots[@]}"; do
  seen=""
  mapfile -t chain < <(collect_chain "$pilot" seen)

  # Signal de migration : \usepackage[...]{ocots}, seul signal fiable pour
  # tous les supports (ocots-td/book/exam pour TD/poly/examen, mais les
  # diapositives restent sur \documentclass{beamer} + \usepackage{ocots} —
  # pas de classe ocots-* dédiée). Les options peuvent tenir sur plusieurs
  # lignes, d'où le deuxième motif (la ligne qui referme le crochet).
  has_pkg=0
  grep -qE '\\usepackage(\[[^]]*\])?\{ocots\}|\]\{ocots\}' "$pilot" && has_pkg=1

  status=""
  found_names=""

  if [ "$has_pkg" -eq 0 ]; then
    status="MISSING"
  else
    for f in "${chain[@]}"; do
      if [ -n "$envs_re" ]; then
        m=$(grep -oE "\\\\begin\{(${envs_re})\}" "$f" 2>/dev/null | sed -E 's/\\begin\{(.*)\}/\1/' || true)
        [ -n "$m" ] && found_names="$found_names"$'\n'"$m"
      fi
      if [ -n "$cmds_re" ]; then
        m=$(grep -oE "\\\\(${cmds_re})\\b" "$f" 2>/dev/null | sed -E 's/^\\//' || true)
        [ -n "$m" ] && found_names="$found_names"$'\n'"$m"
      fi
    done
    found_names="$(printf '%s\n' "$found_names" | sed '/^$/d' | sort -u)"

    # Une macro peut être *redéfinie localement* dans le dépôt de cours
    # (\newcommand/\renewcommand/\DeclareRobustCommand/\let), délibérément,
    # pour un usage qui ne colle pas à la version du template — cas réel et
    # documenté (poly/automatique.tex redéfinit \fonction en 4 args car le
    # \functiondef du template est une array 5 args nue). Ce n'est alors pas
    # un alias de compat en jeu : exclure ces noms-là des trouvailles évite
    # un faux positif qui gâcherait un run de migration pour rien.
    if [ -n "$found_names" ]; then
      kept=""
      while IFS= read -r name; do
        [ -n "$name" ] || continue
        overridden=0
        for f in "${chain[@]}"; do
          grep -qE "\\\\(re)?newcommand\{\\\\${name}\}|\\\\DeclareRobustCommand\{\\\\${name}\}|\\\\let\\\\${name}\\\\" "$f" 2>/dev/null \
            && { overridden=1; break; }
        done
        [ "$overridden" -eq 0 ] && kept="$kept"$'\n'"$name"
      done <<< "$found_names"
      found_names="$(printf '%s\n' "$kept" | sed '/^$/d' | sort -u)"
    fi

    [ -n "$found_names" ] && status="LEGACY"
  fi

  [ -z "$status" ] && { n_skipped=$((n_skipped+1)); continue; }

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
      printf '%s\n' "$found_names" | sed 's/^/- `/; s/$/`/'
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
done

echo
echo "Résumé : $n_missing MISSING, $n_legacy LEGACY, $n_skipped déjà conforme(s)/ignoré(s)."
