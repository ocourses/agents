#!/usr/bin/env bash
# Détecteur — enveloppe `conventions/bin/verifier` (ocots-conventions) et ouvre
# une issue par fichier en infraction. Déterministe, aucun appel modèle.
#
# `verifier` ne couvre que les règles *mécaniques* (P2, P3, P5, C4 au
# 2026-09-11) — un signal, pas un verdict (voir ocots-conventions/README.md,
# section « Ce que l'outil ne fait pas »). L'issue le rappelle : zéro
# trouvaille ne veut pas dire règle respectée, une trouvaille n'est pas
# automatiquement une faute.
#
# Idempotent : une issue existante pour un fichier est mise à jour (pas
# dupliquée) ; un fichier qui n'a plus d'infraction voit son issue fermée
# automatiquement, avec un commentaire.
#
# Entrées (variables d'environnement) :
#   REPO       owner/name du dépôt scanné (défaut: $GITHUB_REPOSITORY)
#   GH_TOKEN   jeton gh avec issues:write sur $REPO
#   CONVENTIONS_DIR  chemin du sous-module conventions (défaut: conventions)
set -euo pipefail

REPO="${REPO:-${GITHUB_REPOSITORY:-}}"
CONVENTIONS_DIR="${CONVENTIONS_DIR:-conventions}"
LABEL="conventions-style"
VERIFIER="${CONVENTIONS_DIR}/bin/verifier"

: "${REPO:?REPO requis}"
: "${GH_TOKEN:?GH_TOKEN requis}"

if [ ! -x "$VERIFIER" ]; then
  echo "::warning::pas de sous-module conventions ($VERIFIER introuvable) — rien à vérifier."
  exit 0
fi

pin="$(git -C "$CONVENTIONS_DIR" describe --tags --always 2>/dev/null || echo '?')"
echo "Dépôt : $REPO — conventions : $pin"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# `verifier` sort 1 dès qu'il y a une infraction : ce n'est pas une erreur ici.
set +e
"$VERIFIER" > "$tmp/out.txt" 2> "$tmp/err.txt"
set -e
echo "::group::sortie de verifier"; cat "$tmp/out.txt"; echo "---"; cat "$tmp/err.txt"; echo "::endgroup::"

# ---------------------------------------------------------------------------
# Regroupement par fichier : chemin -> lignes "| ligne | RÈGLE | message |"
# ---------------------------------------------------------------------------
: > "$tmp/files.txt"
while IFS= read -r line; do
  [ -n "$line" ] || continue
  if [[ "$line" =~ ^([^:]+):([0-9]+):\ \[([A-Za-z0-9]+)\]\ (.*)$ ]]; then
    path="${BASH_REMATCH[1]}"; ln="${BASH_REMATCH[2]}"; rule="${BASH_REMATCH[3]}"; msg="${BASH_REMATCH[4]}"
    echo "$path" >> "$tmp/files.txt"
    row_file="$tmp/rows-$(printf '%s' "$path" | md5sum | cut -d' ' -f1).txt"
    printf '| %s | %s | %s |\n' "$ln" "$rule" "${msg//|/\\|}" >> "$row_file"
  fi
done < "$tmp/out.txt"
sort -u -o "$tmp/files.txt" "$tmp/files.txt"

gh label create "$LABEL" --repo "$REPO" --color fbca04 \
  --description "Infraction mécanique aux conventions ocots-conventions" 2>/dev/null || true

existing_json="$(gh issue list --repo "$REPO" --label "$LABEL" --state open \
  --json number,title,body --limit 200 2>/dev/null || echo '[]')"

n_open=0; n_updated=0; n_created=0; n_closed=0

# --- fichiers en infraction : créer ou mettre à jour -----------------------
while IFS= read -r path; do
  [ -n "$path" ] || continue
  row_file="$tmp/rows-$(printf '%s' "$path" | md5sum | cut -d' ' -f1).txt"
  title="[conventions] $path"
  body_file="$tmp/body.md"
  {
    echo "**Conventions : \`ocots-conventions\` $pin**"
    echo
    echo "Règles **mécaniques** uniquement — *signal, pas verdict* : l'outil mesure"
    echo "une ampleur, il ne certifie rien. Zéro trouvaille ne veut pas dire la règle"
    echo "respectée ; une trouvaille n'est pas automatiquement une faute. Voir"
    echo "[\`ocots-conventions\` § Ce que l'outil ne fait pas](https://github.com/ocourses/ocots-conventions#ce-que-loutil-ne-fait-pas)."
    echo
    echo "| Ligne | Règle | Message |"
    echo "|---|---|---|"
    sort -n "$row_file"
    echo
    echo "Détail des règles : [\`ocots-conventions\`](https://github.com/ocourses/ocots-conventions#à-lire-dans-cet-ordre) (\`communes.md\` + le fichier du support)."
    echo
    echo "---"
    echo "_Détecté automatiquement par \`checkers/conventions.sh\` (\`ocourses/agents\`)._"
  } > "$body_file"

  match="$(printf '%s' "$existing_json" | jq -r --arg t "$title" '.[] | select(.title == $t)')"
  if [ -z "$match" ]; then
    gh issue create --repo "$REPO" --title "$title" --label "$LABEL" --body-file "$body_file" >/dev/null
    echo "  + issue créée : $path"
    n_created=$((n_created+1))
  else
    num="$(printf '%s' "$match" | jq -r '.number')"
    old_body="$(printf '%s' "$match" | jq -r '.body')"
    new_body="$(cat "$body_file")"
    if [ "$old_body" != "$new_body" ]; then
      gh issue edit "$num" --repo "$REPO" --body-file "$body_file" >/dev/null
      echo "  ~ issue mise à jour (#$num) : $path"
      n_updated=$((n_updated+1))
    else
      echo "  = inchangé (#$num) : $path"
    fi
  fi
  n_open=$((n_open+1))
done < "$tmp/files.txt"

# --- issues existantes dont le fichier n'a plus d'infraction : fermer ------
# (process substitution, pas un pipe : la boucle reste dans le shell courant,
# sinon les compteurs incrémentés dedans seraient perdus à la sortie)
while IFS=$'\t' read -r num title; do
  path="${title#\[conventions\] }"
  if ! grep -qxF "$path" "$tmp/files.txt"; then
    gh issue comment "$num" --repo "$REPO" \
      --body "Plus aucune infraction mécanique détectée sur ce fichier (\`checkers/conventions.sh\`). Fermeture automatique — une relecture humaine reste utile pour ce que l'outil ne voit pas." >/dev/null
    gh issue close "$num" --repo "$REPO" --reason completed >/dev/null
    echo "  x issue fermée (#$num) : $path"
    n_closed=$((n_closed+1))
  fi
done < <(printf '%s' "$existing_json" | jq -r '.[] | "\(.number)\t\(.title)"')

echo
echo "Résumé : $n_open fichier(s) en infraction ($n_created créée(s), $n_updated mise(s) à jour), $n_closed fermée(s)."
