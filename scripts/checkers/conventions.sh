#!/usr/bin/env bash
# Détecteur — ouvre une issue **candidate** par fichier en infraction brute.
# Déterministe, aucun appel modèle, mais volontairement PAS un verdict :
# l'outil rate des choses et signale du correct (README d'ocots-lint). Le tri
# revient à un agent (rôle conventions-reviewer, via
# agent-review-conventions.yml, orchestré par queue.yml).
#
# Tout passe par `ocots-lint synchroniser`, via le relais
# conventions/bin/ocots-lint (ocots-conventions >= v2.2.0) : une issue
# [conventions] par fichier (tri), une issue [nettoyer] pour la voie
# mécanique, empreintes et voies dans chaque issue, rejets non redemandés,
# rien de touché si l'analyse échoue. Titres, labels et comportement :
# README d'ocots-lint.
#
# Le chemin historique en bash (enveloppe de conventions/bin/verifier, pour
# les conventions antérieures à v2.2.0) est retiré depuis que tous les cours
# de config/course-repos.txt épinglent au moins v2.2.0 (2026-10-01). Un cours
# qui épinglerait encore une version plus ancienne fait échouer le job, avec
# la consigne de monter ses conventions.
#
# Entrées (variables d'environnement) :
#   REPO       owner/name du dépôt scanné (défaut: $GITHUB_REPOSITORY)
#   GH_TOKEN   jeton gh avec issues:write sur $REPO
#   CONVENTIONS_DIR  chemin du sous-module conventions (défaut: conventions)
#   IGNORE_FILE   fichier de préfixes à exclure, propre au dépôt de cours
#                 (défaut: .agents-ignore, à la racine — un préfixe de chemin
#                 par ligne, "#" pour commenter). Absent = aucune exclusion.
set -euo pipefail

REPO="${REPO:-${GITHUB_REPOSITORY:-}}"
CONVENTIONS_DIR="${CONVENTIONS_DIR:-conventions}"
IGNORE_FILE="${IGNORE_FILE:-.agents-ignore}"
RELAIS="${CONVENTIONS_DIR}/bin/ocots-lint"

: "${REPO:?REPO requis}"
: "${GH_TOKEN:?GH_TOKEN requis}"

if [ ! -d "$CONVENTIONS_DIR/bin" ]; then
  echo "::warning::pas de sous-module conventions ($CONVENTIONS_DIR/bin introuvable) — rien à vérifier."
  exit 0
fi

pin="$(git -C "$CONVENTIONS_DIR" describe --tags --always 2>/dev/null || echo '?')"

if [ ! -x "$RELAIS" ]; then
  echo "::error::conventions $pin : pas de relais $RELAIS (conventions antérieures à v2.2.0). Monter le sous-module conventions (git -C $CONVENTIONS_DIR checkout <dernière release>) — aucune issue modifiée."
  exit 1
fi

echo "Dépôt : $REPO — conventions : $pin — ocots-lint synchroniser"
exec "$RELAIS" synchroniser --depot "$REPO" --ignore "$IGNORE_FILE"
