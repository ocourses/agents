#!/usr/bin/env bash
# Détecteur — enveloppe `conventions/bin/verifier` (ocots-conventions) et
# ouvre une issue **candidate** par fichier en infraction brute. Déterministe,
# aucun appel modèle, mais volontairement PAS un verdict : `verifier` lui-même
# le dit (ocots-conventions/README.md, § « Ce que l'outil ne fait pas ») — il
# rate des choses, il signale du correct, zéro trouvaille ne veut pas dire
# règle respectée. Une trouvaille encore moins.
#
# Ce script ne fait donc QUE lister des candidats (label
# conventions-candidate) — il n'affirme rien et ne les qualifie pas de vraie
# infraction. Le tri revient à un agent (rôle conventions-reviewer, via
# agent-review-conventions.yml, orchestré par la file d'attente globale
# queue.yml) : il relit le fichier, exerce le jugement que le script n'a pas,
# et promeut ou ferme chaque candidat. Ce script ne modifie donc jamais une
# issue déjà promue par l'agent (label conventions-style) : voir plus bas.
#
# Idempotent : une issue candidate existante pour un fichier est mise à jour
# (pas dupliquée) ; un fichier qui n'a plus d'infraction brute voit sa
# candidate fermée automatiquement (mais pas une issue déjà promue : elle
# reste au jugement de l'agent / d'un humain).
#
# Entrées (variables d'environnement) :
#   REPO       owner/name du dépôt scanné (défaut: $GITHUB_REPOSITORY)
#   GH_TOKEN   jeton gh avec issues:write sur $REPO
#   CONVENTIONS_DIR  chemin du sous-module conventions (défaut: conventions)
#   IGNORE_FILE   fichier de préfixes à exclure, propre au dépôt de cours
#                 (défaut: .agents-ignore, à la racine — un préfixe de chemin
#                 par ligne, ex. "slides/", "#" pour commenter). Absent =
#                 aucune exclusion. `verifier` lui-même a son propre SKIP
#                 (template/build/conventions/.git, en dur, pour TOUS ses
#                 usages) : ceci filtre en plus, après coup, pour UN dépôt —
#                 pas touché à `verifier`, qui reste générique.
#                 Bonus : un fichier déjà exclu ici dont l'issue candidate
#                 était ouverte se refermera tout seul (même mécanique que
#                 "plus aucune trouvaille", plus bas).
set -euo pipefail

REPO="${REPO:-${GITHUB_REPOSITORY:-}}"
CONVENTIONS_DIR="${CONVENTIONS_DIR:-conventions}"
IGNORE_FILE="${IGNORE_FILE:-.agents-ignore}"
LABEL="conventions-candidate"
REVIEWED_LABEL="conventions-style"
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

# --- exclusions propres à ce dépôt (IGNORE_FILE) ---------------------------
# Même piège évité qu'en template-migration.sh : ne pas compter sur le
# comportement de `grep -vf` avec un fichier de motifs vide (élimine tout au
# lieu de rien sur certains grep) — ici testé au cas par cas via une
# fonction, donc pas concerné, mais la construction reste identique.
: > "$tmp/ignore-patterns.txt"
if [ -f "$IGNORE_FILE" ]; then
  grep -vE '^[[:space:]]*(#|$)' "$IGNORE_FILE" \
    | sed -E 's/[.[\*^$()+?{|]/\\&/g; s/^/^/' \
    > "$tmp/ignore-patterns.txt"
fi
n_ignore=$(wc -l < "$tmp/ignore-patterns.txt")
[ "$n_ignore" -gt 0 ] && echo "Exclusions ($IGNORE_FILE) : $n_ignore motif(s)"

is_ignored() { # $1 = chemin
  [ "$n_ignore" -gt 0 ] || return 1
  grep -qEf "$tmp/ignore-patterns.txt" <<< "$1"
}

# ---------------------------------------------------------------------------
# Regroupement par fichier : chemin -> lignes "| ligne | RÈGLE | message |"
# Un chemin exclu par IGNORE_FILE n'entre jamais dans files.txt : il est donc
# traité comme "plus aucune trouvaille" par la boucle de fermeture plus bas,
# qui referme automatiquement une candidate déjà ouverte pour ce fichier.
# ---------------------------------------------------------------------------
: > "$tmp/files.txt"
while IFS= read -r line; do
  [ -n "$line" ] || continue
  if [[ "$line" =~ ^([^:]+):([0-9]+):\ \[([A-Za-z0-9]+)\]\ (.*)$ ]]; then
    path="${BASH_REMATCH[1]}"; ln="${BASH_REMATCH[2]}"; rule="${BASH_REMATCH[3]}"; msg="${BASH_REMATCH[4]}"
    is_ignored "$path" && continue
    echo "$path" >> "$tmp/files.txt"
    row_file="$tmp/rows-$(printf '%s' "$path" | md5sum | cut -d' ' -f1).txt"
    printf '| %s | %s | %s |\n' "$ln" "$rule" "${msg//|/\\|}" >> "$row_file"
  fi
done < "$tmp/out.txt"
sort -u -o "$tmp/files.txt" "$tmp/files.txt"

gh label create "$LABEL" --repo "$REPO" --color fbca04 \
  --description "Candidat brut (script) à trier par l'agent conventions-reviewer — pas encore un verdict" 2>/dev/null || true
gh label create "$REVIEWED_LABEL" --repo "$REPO" --color d93f0b \
  --description "Infraction confirmée par un agent après relecture" 2>/dev/null || true

existing_json="$(gh issue list --repo "$REPO" --label "$LABEL" --state open \
  --json number,title,body --limit 200 2>/dev/null || echo '[]')"

# Fichiers déjà triés et promus `conventions-style` par conventions-reviewer :
# la promotion réutilise le même numéro d'issue, juste avec le label et le
# corps changés (roles/conventions-reviewer.md, étape 5) — donc un tel fichier
# n'apparaît plus dans existing_json ($LABEL) et serait sinon recréé en
# doublon brut à chaque re-scan, alors qu'il a déjà un verdict humain/agent en
# cours (bug constaté en pratique : #46 à #53 dupliquant #24..#36). On ne
# touche jamais un fichier déjà promu : ni création, ni mise à jour, ni
# fermeture — il appartient désormais à conventions-fixer / à une relecture
# humaine, pas à ce détecteur mécanique.
existing_style_titles="$(gh issue list --repo "$REPO" --label "$REVIEWED_LABEL" --state open \
  --json title --jq '.[].title' --limit 200 2>/dev/null || true)"

n_open=0; n_updated=0; n_created=0; n_closed=0; n_promoted=0

# --- fichiers en infraction : créer ou mettre à jour -----------------------
while IFS= read -r path; do
  [ -n "$path" ] || continue
  title="[conventions] $path"
  if printf '%s\n' "$existing_style_titles" | grep -qxF "$title"; then
    echo "  = déjà promu conventions-style, ignoré : $path"
    n_promoted=$((n_promoted+1))
    continue
  fi
  row_file="$tmp/rows-$(printf '%s' "$path" | md5sum | cut -d' ' -f1).txt"
  body_file="$tmp/body.md"
  {
    echo "**⚠️ Candidat brut, pas relu.** Sortie mécanique de \`conventions/bin/verifier\`"
    echo "(\`ocots-conventions\` $pin) — *un signal, pas un verdict*. L'outil rate des"
    echo "choses, signale parfois du correct, et zéro trouvaille ne veut pas dire la"
    echo "règle respectée (voir"
    echo "[\`ocots-conventions\` § Ce que l'outil ne fait pas](https://github.com/ocourses/ocots-conventions#ce-que-loutil-ne-fait-pas))."
    echo "**Ne pas agir sur ce qui suit sans relecture.** Un agent (\`conventions-reviewer\`)"
    echo "passera trier ces lignes : confirmées → label \`conventions-style\`, rejetées →"
    echo "fermeture expliquée."
    echo
    echo "| Ligne | Règle | Message brut |"
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
      --body "Plus aucune trouvaille brute de \`verifier\` sur ce fichier. Fermeture automatique de ce candidat — rappel : zéro trouvaille ne certifie pas la conformité (règles non outillées, voir \`ocots-conventions/README.md\`)." >/dev/null
    gh issue close "$num" --repo "$REPO" --reason completed >/dev/null
    echo "  x candidat fermé (#$num) : $path"
    n_closed=$((n_closed+1))
  fi
done < <(printf '%s' "$existing_json" | jq -r '.[] | "\(.number)\t\(.title)"')

echo
echo "Résumé : $n_open fichier(s) en infraction ($n_created créée(s), $n_updated mise(s) à jour), $n_closed fermée(s), $n_promoted déjà promue(s) conventions-style (ignorée(s))."
