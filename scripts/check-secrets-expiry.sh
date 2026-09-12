#!/usr/bin/env bash
# Surveillance des échéances de secrets — avertit AVANT la panne.
#
# Les PAT et les clés Albert de ce montage expirent à des dates échelonnées
# (quatre dates différentes rien que pour les PAT). Le jour où l'une tombe, le
# symptôme est muet et trompeur : échec de checkout du dépôt privé `agents`,
# ou 401 d'Albert au milieu d'un run d'agent — rien qui dise « jeton expiré ».
# Ce script lit config/secrets-expiry.txt et ouvre une issue à l'approche de
# chaque échéance, pour que la rotation soit faite avant, pas après.
#
# Il ne teste PAS la validité des secrets : il ne les lit pas et n'en a pas
# besoin. C'est délibéré — il tourne dans ocourses/agents avec le simple
# `github.token` (issues:write sur lui-même), donc il ne peut pas tomber en
# panne pour la raison même qu'il surveille. Un test de vivacité, lui, devrait
# s'exécuter dans chaque dépôt détenteur du secret ; c'est un autre chantier.
#
# Entrées (variables d'environnement) :
#   GH_TOKEN     jeton gh avec issues:write sur $REPO (github.token suffit)
#   REPO         owner/name où ouvrir l'issue (défaut: $GITHUB_REPOSITORY)
#   EXPIRY_FILE  défaut: config/secrets-expiry.txt
#   WARN_DAYS    seuil d'alerte en jours (défaut: 30)
#
# Sortie : 0 si tout va bien ou si l'alerte est seulement anticipée ;
#          1 si un secret est DÉJÀ expiré (le run échoue, c'est voulu).
set -euo pipefail

REPO="${REPO:-${GITHUB_REPOSITORY:-ocourses/agents}}"
EXPIRY_FILE="${EXPIRY_FILE:-config/secrets-expiry.txt}"
WARN_DAYS="${WARN_DAYS:-30}"
LABEL="secrets-expiry"
TITLE="⏳ Secrets — échéances à traiter"

: "${GH_TOKEN:?GH_TOKEN requis (issues:write sur $REPO)}"
[ -f "$EXPIRY_FILE" ] || { echo "::error::$EXPIRY_FILE introuvable"; exit 1; }

today="$(date -u +%Y-%m-%d)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
: > "$tmp/expired"; : > "$tmp/soon"; : > "$tmp/unknown"; : > "$tmp/ok"

days_until() { # <date ISO> -> nombre de jours (négatif si passée)
  python3 -c 'import sys,datetime
d=datetime.date.fromisoformat(sys.argv[1]); t=datetime.date.fromisoformat(sys.argv[2])
print((d-t).days)' "$1" "$today"
}

while read -r when repo secret label; do
  [ -n "${when:-}" ] || continue
  case "$when" in \#*) continue ;; esac

  if [ "$when" = "?" ]; then
    printf -- '- `%s` dans `%s` (%s) — **échéance non renseignée**\n' \
      "$secret" "$repo" "$label" >> "$tmp/unknown"
    echo "INCONNU  $repo  $secret  ($label)"
    continue
  fi

  if ! d="$(days_until "$when" 2>/dev/null)"; then
    echo "::error::date illisible dans $EXPIRY_FILE : « $when » (ligne $repo/$secret)"
    exit 1
  fi

  if [ "$d" -lt 0 ]; then
    printf -- '- `%s` dans `%s` (%s) — **EXPIRÉ depuis %s jours** (le %s)\n' \
      "$secret" "$repo" "$label" "$(( -d ))" "$when" >> "$tmp/expired"
    echo "EXPIRÉ   $repo  $secret  ($label)  le $when"
  elif [ "$d" -le "$WARN_DAYS" ]; then
    printf -- '- `%s` dans `%s` (%s) — expire dans **%s jours** (le %s)\n' \
      "$secret" "$repo" "$label" "$d" "$when" >> "$tmp/soon"
    echo "BIENTÔT  $repo  $secret  ($label)  dans $d j (le $when)"
  else
    echo "OK       $repo  $secret  ($label)  dans $d j (le $when)"
    echo x >> "$tmp/ok"
  fi
done < <(grep -vE '^[[:space:]]*(#|$)' "$EXPIRY_FILE")

n_exp=$(wc -l < "$tmp/expired" | tr -d ' ')
n_soon=$(wc -l < "$tmp/soon" | tr -d ' ')
n_unk=$(wc -l < "$tmp/unknown" | tr -d ' ')

gh label create "$LABEL" --repo "$REPO" --color d93f0b \
  --description "Échéance de secret à traiter" 2>/dev/null || true
existing="$(gh issue list --repo "$REPO" --label "$LABEL" --state open \
  --json number --jq '.[0].number // empty' 2>/dev/null || true)"

# Rien à signaler : refermer l'issue si elle traînait ouverte.
if [ "$n_exp" -eq 0 ] && [ "$n_soon" -eq 0 ] && [ "$n_unk" -eq 0 ]; then
  echo "Toutes les échéances sont au-delà de $WARN_DAYS jours et renseignées."
  if [ -n "$existing" ]; then
    gh issue comment "$existing" --repo "$REPO" \
      --body "Plus aucune échéance sous $WARN_DAYS jours au $today — refermée automatiquement." >/dev/null
    gh issue close "$existing" --repo "$REPO" --reason completed >/dev/null
    echo "Issue #$existing refermée."
  fi
  exit 0
fi

{
  echo "Relevé du $today (seuil d'alerte : $WARN_DAYS jours)."
  echo
  [ "$n_exp"  -gt 0 ] && { echo "## Expiré — à renouveler immédiatement"; cat "$tmp/expired"; echo; }
  [ "$n_soon" -gt 0 ] && { echo "## Échéance proche"; cat "$tmp/soon"; echo; }
  [ "$n_unk"  -gt 0 ] && { echo "## Échéance non renseignée"; cat "$tmp/unknown"; echo; }
  echo "---"
  echo "Après chaque rotation, **mettre à jour \`$EXPIRY_FILE\`** : ce fichier est"
  echo "saisi à la main (GitHub n'expose pas l'échéance d'un PAT par l'API), il ment"
  echo "dès qu'on l'oublie. Chaque cours a ses propres clés : pas de rotation groupée."
  echo
  echo "_Issue tenue à jour automatiquement par \`scripts/check-secrets-expiry.sh\`._"
} > "$tmp/body.md"

if [ -n "$existing" ]; then
  gh issue edit "$existing" --repo "$REPO" --body-file "$tmp/body.md" >/dev/null
  echo "Issue #$existing mise à jour."
else
  url="$(gh issue create --repo "$REPO" --title "$TITLE" --label "$LABEL" \
    --assignee ocots --body-file "$tmp/body.md")"
  echo "Issue ouverte : $url"
fi

if [ "$n_exp" -gt 0 ]; then
  echo "::error::$n_exp secret(s) déjà expiré(s) — voir l'issue."
  exit 1
fi
exit 0
