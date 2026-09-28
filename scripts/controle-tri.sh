#!/usr/bin/env bash
# Garde-fou du rôle conventions-reviewer (tri), lancé par agent.yml après le
# travail de l'agent, avant le push : le tri ne touche au contenu du cours
# QUE pour poser des exemptions (`ocots-lint exempter`), une ligne de
# commentaire `% ocots-lint: ignore RÈGLE — raison` au-dessus d'un faux
# positif ou d'une exception légitime. C'est ce qui empêche un rejet de
# revenir chaque semaine.
#
# Contrôle le diff de la branche contre la base, fichier de suivi
# (.agents/runs/) exclu, commité ou non :
#   - relais `conventions/bin/ocots-lint` présent (conventions >= v2.3.0) :
#     `ocots-lint exempter --controler -` — seules des directives valides,
#     ajoutées seules sur leur ligne, dans des .tex ;
#   - sinon (anciennes conventions) : le diff doit être vide, comme avant.
#
# Entrées : BASE (branche de base, ex. main). CONVENTIONS_DIR (défaut :
# conventions). Lancé depuis la racine du clone du dépôt de cours.
# Sortie 0 si conforme, 1 sinon (le job échoue, la file marque l'issue
# agent:failed ; la PR Draft reste visible pour un humain).
set -euo pipefail

: "${BASE:?BASE requis (branche de base)}"
CONVENTIONS_DIR="${CONVENTIONS_DIR:-conventions}"
RELAIS="${CONVENTIONS_DIR}/bin/ocots-lint"

git fetch -q origin "$BASE" 2>/dev/null || true
base_ref="origin/$BASE"
git rev-parse -q --verify "$base_ref" >/dev/null || base_ref="$BASE"
depart="$(git merge-base "$base_ref" HEAD)"

diff="$(git diff "$depart" -- . ':(exclude).agents/runs')"
nouveaux="$(git ls-files --others --exclude-standard -- . ':(exclude).agents/runs')"

if [ -n "$nouveaux" ]; then
  echo "::error::le tri a créé des fichiers :"
  printf '%s\n' "$nouveaux"
  exit 1
fi
if [ -z "$diff" ]; then
  echo "Tri : aucun fichier du cours modifié."
  exit 0
fi
if [ ! -x "$RELAIS" ]; then
  echo "::error::le tri a modifié le cours, et $RELAIS est absent (conventions < v2.3.0) : aucune modification n'est permise."
  git diff --stat "$depart" -- . ':(exclude).agents/runs'
  exit 1
fi
if ! printf '%s\n' "$diff" | "$RELAIS" exempter --controler -; then
  echo "::error::le tri a modifié le cours autrement qu'en posant des exemptions (ocots-lint exempter)."
  exit 1
fi
echo "Tri : $(printf '%s\n' "$diff" | grep -c '^+[^+]') exemption(s) posée(s), diff conforme."
