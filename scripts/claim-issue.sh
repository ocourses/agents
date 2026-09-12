#!/usr/bin/env bash
# Protocole de réclamation d'une issue — SOURCE UNIQUE, utilisée par la file
# automatisée (queue-next.sh) ET par tout travail manuel (une session Claude
# Code locale, ou toi directement) qui prendrait une issue de
# template-migration / conventions-candidate sans passer par la file.
#
# GitHub n'offre pas de transaction sur les labels (pas de compare-and-swap) :
# ce n'est donc PAS un verrou parfait, seulement une convention — vérifier
# (status) avant, réclamer (claim) tout de suite après, ne jamais commencer
# le travail avant que claim ait réussi. Avec un seul bot (verrou global
# GitHub Actions : jamais deux ticks automatisés en même temps) + un seul
# humain à la fois, la fenêtre de course est nulle en pratique si ce
# protocole est suivi à la lettre des deux côtés.
#
# Usage :
#   claim-issue.sh status  <repo> <issue>
#   claim-issue.sh claim   <repo> <issue> <origine>
#   claim-issue.sh release <repo> <issue>
#   claim-issue.sh fail    <repo> <issue> <raison>
#
# <origine> et <raison> sont du texte libre, posté dans un commentaire —
# ex. "file d'attente automatique" ou "Claude Code local (Olivier)".
#
# Entrées : GH_TOKEN (issues:write sur le dépôt ciblé).
set -euo pipefail

DISPATCHED_LABEL="agent:dispatched"
FAILED_LABEL="agent:failed"

cmd="${1:?usage: claim-issue.sh <status|claim|release|fail> <repo> <issue> [...]}"
repo="${2:?repo requis (owner/name)}"
issue="${3:?numero de l issue requis}"
: "${GH_TOKEN:?GH_TOKEN requis (issues:write sur $repo)}"

labels_of() { gh issue view "$issue" --repo "$repo" --json labels --jq '[.labels[].name] | join(",")'; }

ensure_labels() {
  gh label create "$DISPATCHED_LABEL" --repo "$repo" --color 5319e7 \
    --description "Reclamee - un travail (bot ou humain) est en cours" 2>/dev/null || true
  gh label create "$FAILED_LABEL" --repo "$repo" --color b60205 \
    --description "Run en echec - verifier avant de remettre en file" 2>/dev/null || true
}

case "$cmd" in
  status)
    l=",$(labels_of),"
    case "$l" in
      *",$FAILED_LABEL,"*)     echo "echec - necessite intervention humaine" ;;
      *",$DISPATCHED_LABEL,"*) echo "reclamee" ;;
      *)                        echo "libre" ;;
    esac
    ;;

  claim)
    origine="${4:?origine requise (ex. \"Claude Code local (Olivier)\")}"
    ensure_labels
    l=",$(labels_of),"
    case "$l" in
      *",$DISPATCHED_LABEL,"*)
        echo "::error::#$issue deja reclamee sur $repo - ne pas commencer (voir les commentaires pour savoir par qui)."
        exit 1 ;;
      *",$FAILED_LABEL,"*)
        echo "::error::#$issue porte $FAILED_LABEL - un run precedent a echoue, verifier avant de reprendre."
        exit 1 ;;
    esac
    gh issue edit "$issue" --repo "$repo" --add-label "$DISPATCHED_LABEL" >/dev/null
    gh issue comment "$issue" --repo "$repo" \
      --body "🔒 Prise en charge par **$origine** — $(date -u +%FT%TZ)." >/dev/null
    echo "Reclamee."
    ;;

  release)
    gh issue edit "$issue" --repo "$repo" --remove-label "$DISPATCHED_LABEL" 2>/dev/null || true
    echo "Liberee."
    ;;

  fail)
    raison="${4:-non precisee}"
    ensure_labels
    gh issue edit "$issue" --repo "$repo" --remove-label "$DISPATCHED_LABEL" 2>/dev/null || true
    gh issue edit "$issue" --repo "$repo" --add-label "$FAILED_LABEL" >/dev/null
    gh issue comment "$issue" --repo "$repo" \
      --body "⚠️ Échec : $raison. **Pas de nouvelle tentative automatique** — retirer \`$FAILED_LABEL\` pour remettre en jeu." >/dev/null
    echo "Marquee en echec."
    ;;

  *) echo "::error::sous-commande inconnue : $cmd" >&2; exit 1 ;;
esac
