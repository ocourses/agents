#!/usr/bin/env bash
# Revérification post-run d'une migration — extrait de queue-next.sh
# (fonction rescan_migration) pour être appelé aussi par un tick local (voir
# LOCAL-QUEUE.md), avec le MÊME composant que le détecteur et que la file
# automatisée, pour que les trois verdicts ne divergent jamais.
#
# « Une PR existe » ne suffit pas comme critère de succès d'une migration :
# un diff vide fermerait l'issue de détection pour rien, que le checker
# hebdomadaire recréerait identique au passage suivant (dédup sur les issues
# ouvertes seulement) — ocourses/agents#15. On re-scanne donc la branche de
# la PR avec scripts/lib/template-scan.sh (le même composant que
# checkers/template-migration.sh) : succès seulement si plus aucun nom de
# ocots-compat.sty ne subsiste dans la chaîne \input du pilote cible.
#
# Usage : rescan-migration.sh <repo> <branche> <pilote>
#   stdout : la ligne TSV "STATUT<TAB>pilote<TAB>noms" de template-scan.sh
#   rc ≠ 0 : revérification IMPOSSIBLE (clone/API en échec) — à traiter comme
#            un échec de la tâche, jamais comme un succès non vérifié.
#
# Entrées :
#   GH_TOKEN      Contents (lire) sur <repo> et sur le dépôt source du
#                 sous-module template.
#   TEMPLATE_DIR  chemin du sous-module template dans le dépôt de cours
#                 (défaut: template — même convention que le checker).
#   SCAN          chemin de template-scan.sh (défaut: à côté de ce script).
set -euo pipefail

repo="${1:?usage: rescan-migration.sh <repo> <branche> <pilote>}"
branch="${2:?branche requise}"
target="${3:?pilote requis}"
: "${GH_TOKEN:?GH_TOKEN requis}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="${TEMPLATE_DIR:-template}"
SCAN="${SCAN:-${SCRIPT_DIR}/template-scan.sh}"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
dir="$tmp/rescan"; mkdir -p "$dir"

# PAT en en-tête (comme actions/checkout), pas dans l'URL : éviter toute
# fuite du jeton dans un message d'erreur de git.
git -c "http.https://github.com/.extraheader=AUTHORIZATION: basic $(printf 'x-access-token:%s' "$GH_TOKEN" | base64 | tr -d '\n')" \
  clone --quiet --depth 1 --branch "$branch" "https://github.com/$repo" "$dir/repo" || exit 1

if [ -f "$dir/repo/${TEMPLATE_DIR}/tex/ocots-compat.sty" ]; then
  # Template vendored (fichiers en dur, pas un sous-module) : compat lu
  # directement dans le clone.
  cp "$dir/repo/${TEMPLATE_DIR}/tex/ocots-compat.sty" "$dir/ocots-compat.sty"
else
  # Gitlink du sous-module template sur CETTE branche → SHA épinglé + dépôt
  # source. Le sous-module n'est pas matérialisé par le clone shallow.
  sub_json="$(gh api "repos/$repo/contents/${TEMPLATE_DIR}?ref=$branch")" || exit 1
  sub_sha="$(printf '%s' "$sub_json" | jq -r '.sha // empty')"
  tpl_repo="$(printf '%s' "$sub_json" | jq -r '.submodule_git_url // empty' \
    | sed -E 's#^(git@github\.com:|https://github\.com/)##; s#\.git$##')"
  if [ -z "$sub_sha" ] || [ -z "$tpl_repo" ]; then
    echo "gitlink ${TEMPLATE_DIR} illisible sur ${repo}@${branch}" >&2
    exit 1
  fi
  gh api "repos/$tpl_repo/contents/tex/ocots-compat.sty?ref=$sub_sha" \
    -H "Accept: application/vnd.github.raw" > "$dir/ocots-compat.sty" || exit 1
fi

(cd "$dir/repo" && bash "$SCAN" "$dir/ocots-compat.sty" "$target")
