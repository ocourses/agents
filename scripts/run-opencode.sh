#!/usr/bin/env bash
# Couche B — fait travailler l'agent avec OpenCode (headless, provider Albert).
#
# Assemble AGENTS.md (socle + rôle + contexte), pose opencode.json, lance
# `opencode run`. OpenCode explore, écrit son plan/journal/bilan dans le fichier
# de suivi, édite et commite lui-même. Le push est fait par le workflow après.
#
# Entrées (variables d'environnement) :
#   AGENTS_DIR   racine du checkout de ocourses/agents (défaut: _agents)
#   ROLE         nom du rôle (fichier roles/<ROLE>.md, override .agents/roles/ prioritaire)
#   TASK, MODEL, REPO, BRANCH, ISSUE, PR, TRACKING, RUN_URL
#   ALBERT_API_KEY
set -euo pipefail

OPENCODE_VERSION="1.18.29"   # épinglé — bumper après test sur le probe

AGENTS_DIR="${AGENTS_DIR:-_agents}"
: "${ROLE:?}" "${TASK:?}" "${MODEL:?}" "${TRACKING:?}" "${ALBERT_API_KEY:?}"

# --- rôle (override local prioritaire) ---
if [ -f ".agents/roles/${ROLE}.md" ]; then
  ROLE_FILE=".agents/roles/${ROLE}.md"
elif [ -f "${AGENTS_DIR}/roles/${ROLE}.md" ]; then
  ROLE_FILE="${AGENTS_DIR}/roles/${ROLE}.md"
else
  echo "::error::rôle introuvable : ${ROLE}" >&2; exit 1
fi
echo "Rôle : $ROLE_FILE"

# --- fichiers de run non suivis (au cas où le .gitignore du dépôt ne les couvre pas) ---
mkdir -p _agent_logs
printf '%s\n' opencode.json .opencode/ _agent_logs/ _agents/ \
  '**/build/' '*.synctex.gz' \
  >> .git/info/exclude

# AGENTS.md est un cas à part : dans les dépôts de cours, c'est un fichier
# RÉEL déjà suivi (contenu antérieur à cette base d'agents). .gitignore et
# .git/info/exclude ne s'appliquent qu'aux fichiers non suivis — ils ne
# cachent jamais une modification d'un fichier déjà commité. On écrase son
# contenu ci-dessous pour que l'agent le lise comme instructions de run,
# mais --skip-worktree fait ignorer cette modification locale par git status
# / diff / add -A / commit -a, quel que soit le commit que fait l'agent.
git update-index --skip-worktree AGENTS.md 2>/dev/null || true

# --- install OpenCode (épinglé) ---
npm install -g "opencode-ai@${OPENCODE_VERSION}"
opencode --version

# --- AGENTS.md = socle + rôle + contexte ---
{
  cat "${AGENTS_DIR}/config/AGENTS.base.md"
  echo; echo "---"; echo
  cat "$ROLE_FILE"
  echo; echo "---"; echo
  echo "## Contexte d'exécution"
  echo
  echo "- Dépôt : \`${REPO:-?}\`  ·  branche : \`${BRANCH:-?}\`"
  echo "- Issue : #${ISSUE:-?}  ·  PR : #${PR:-?}  ·  run : ${RUN_URL:-?}"
  echo "- Fichier de suivi (plan / journal / bilan) : \`${TRACKING}\`"
  echo "- Modèle : \`${MODEL}\`"
  echo
  echo "### Tâche"
  echo
  echo "${TASK}"
} > AGENTS.md
echo "::group::AGENTS.md"; cat AGENTS.md; echo "::endgroup::"

# --- opencode.json ---
export OPENCODE_CONFIG="${PWD}/opencode.json"
sed "s#albert/deepseek-v4-flash#albert/${MODEL}#g" \
  "${AGENTS_DIR}/config/opencode.json" > "$OPENCODE_CONFIG"

# --- run ---
set +e
opencode run --auto --model "albert/${MODEL}" \
  "Réalise la tâche décrite dans AGENTS.md. Tiens le fichier de suivi ${TRACKING} à jour (plan, journal, bilan) et commite ton travail au fur et à mesure." \
  2>&1 | tee _agent_logs/opencode.out
rc=$?
set -e
echo "opencode run rc=$rc (indicatif — le succès se juge aux commits et au bilan)"

# --- logs OpenCode -> artefact ---
mkdir -p _agent_logs
cp -r "$HOME/.local/share/opencode/log" _agent_logs/opencode-log 2>/dev/null || true
