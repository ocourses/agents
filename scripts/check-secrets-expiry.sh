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
#   ALBERT_API_KEY  facultatif — si fourni, les dates des clés Albert saisies
#                dans le fichier sont RECOUPÉES avec l'API Albert
#                (GET /v1/keys/{id}), qui fait foi. Absent : on s'en passe,
#                le script fonctionne à l'identique sur les dates saisies.
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

ALBERT_BASE="${ALBERT_BASE:-https://albert.api.etalab.gouv.fr}"
: > "$tmp/drift"

# Date d'expiration réelle d'une clé Albert, via son id. N'ÉCRIT JAMAIS le
# corps de la réponse : GET /v1/keys/{id} renvoie un champ `value` qui est la
# clé en clair. On n'en extrait que `expires` (timestamp Unix, ou null).
albert_expiry() { # <id> -> AAAA-MM-JJ | "jamais" | "" (échec)
  local id="$1" body code
  body="$(curl -sS --max-time 20 -w '\n%{http_code}' \
    -H "Authorization: Bearer ${ALBERT_API_KEY}" \
    "$ALBERT_BASE/v1/keys/$id" 2>/dev/null)" || return 1
  code="$(printf '%s' "$body" | tail -n1)"
  case "$code" in
    200) : ;;
    401) echo "::warning::Albert 401 pour la clé $id — ALBERT_API_KEY invalide ou expirée" >&2; return 1 ;;
    403) echo "::warning::Albert 403 pour la clé $id — le COMPTE Albert a expiré (au-delà des clés)" >&2; return 1 ;;
    404) echo "::warning::Albert 404 — clé $id introuvable (révoquée, ou id erroné dans le fichier)" >&2; return 1 ;;
    *)   echo "::warning::Albert a répondu $code pour la clé $id" >&2; return 1 ;;
  esac
  printf '%s' "$body" | sed '$d' | python3 -c 'import sys,json,datetime
try: d=json.load(sys.stdin)
except Exception: sys.exit(1)
e=d.get("expires")
if e is None: print("jamais")
else: print(datetime.datetime.fromtimestamp(int(e),datetime.timezone.utc).date().isoformat())' 2>/dev/null || return 1
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

  if [ "$secret" = "ALBERT_API_KEY" ] && [ -n "${ALBERT_API_KEY:-}" ]; then
    id="$(printf '%s' "$label" | sed -n 's/.*#\([0-9][0-9]*\).*/\1/p')"
    if [ -n "$id" ] && real="$(albert_expiry "$id")" && [ -n "$real" ]; then
      if [ "$real" = "jamais" ]; then
        echo "         └─ Albert : cette clé n'expire pas"
        echo "OK       $repo  $secret  ($label)  n'expire pas (Albert)"
        continue
      fi
      if [ "$real" != "$when" ]; then
        printf -- '- `%s` dans `%s` (%s) — le fichier dit **%s**, Albert dit **%s** (c'"'"'est Albert qui fait foi)\n' \
          "$secret" "$repo" "$label" "$when" "$real" >> "$tmp/drift"
        echo "DÉRIVE   $repo  $secret  ($label)  fichier=$when  Albert=$real"
        # Albert fait foi : le seuil d'alerte se calcule sur la date réelle,
        # sinon une date saisie trop optimiste masquerait une vraie échéance.
        when="$real"; d="$(days_until "$real")"
      else
        echo "         └─ recoupé avec Albert : $real"
      fi
    fi
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
n_drift=$(wc -l < "$tmp/drift" | tr -d ' ')

gh label create "$LABEL" --repo "$REPO" --color d93f0b \
  --description "Échéance de secret à traiter" 2>/dev/null || true
existing="$(gh issue list --repo "$REPO" --label "$LABEL" --state open \
  --json number --jq '.[0].number // empty' 2>/dev/null || true)"

# Rien à signaler : refermer l'issue si elle traînait ouverte.
if [ "$n_exp" -eq 0 ] && [ "$n_soon" -eq 0 ] && [ "$n_unk" -eq 0 ] && [ "$n_drift" -eq 0 ]; then
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
  [ "$n_drift" -gt 0 ] && { echo "## Date saisie ≠ date réelle (Albert fait foi)"; cat "$tmp/drift"; echo; }
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
