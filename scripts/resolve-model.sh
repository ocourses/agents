#!/usr/bin/env bash
# Résout un alias de modèle vers l'identifiant canonique exposé par Albert.
# Usage : resolve-model.sh <alias-ou-id>  ->  écrit "model=<id>" (format GITHUB_OUTPUT).
#
# Catalogue Albert au 2026-09-08 (vérifier avec `GET /v1/models`, il évolue) :
#   deepseek-v4-flash ...................... coding agentique, tool calling, 131k ctx
#   qwen3-coder-30b-A3b-instruct ........... spécialisé code
#   openai/gpt-oss-120b ................... généraliste, tâches complexes
#   gemma-4-31b-it ....................... généraliste
#   mistral-small-3-2-24b-instruct-2506 .. tâches moyennes + image
#   ministral-3-8b-instruct-2512 ......... tâches simples
set -euo pipefail

alias_in="${1:?alias de modèle attendu}"

case "$alias_in" in
  deepseek|deepseek-flash) model="deepseek-v4-flash" ;;
  qwen-coder)              model="qwen3-coder-30b-A3b-instruct" ;;
  gpt-oss)                 model="openai/gpt-oss-120b" ;;
  gemma)                   model="gemma-4-31b-it" ;;
  mistral-small)           model="mistral-small-3-2-24b-instruct-2506" ;;
  ministral)               model="ministral-3-8b-instruct-2512" ;;
  *)                       model="$alias_in" ;;   # identifiant passé tel quel
esac

echo "model=$model"
