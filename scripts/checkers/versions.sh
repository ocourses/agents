#!/usr/bin/env bash
# Couche « détecteur » — signale un sous-module épinglé en retard sur la
# dernière release de son dépôt (template, conventions…), pour ne pas oublier
# une montée de version. Déterministe, aucun modèle.
#
# Pour chaque sous-module de .gitmodules hébergé sur GitHub dont le dépôt a
# des tags `vX.Y.Z` :
#   - version épinglée = tag du commit épinglé ; à défaut, le plus haut tag
#     dont le commit épinglé descend (API compare) — « vX + commits » ;
#   - en retard sur le plus haut tag → une issue `[versions] <chemin>`
#     (label `versions`), créée ou mise à jour : versions à franchir, majeures
#     signalées, section du CHANGELOG de chacune (c'est elle qui dit ce que
#     le cours doit changer), commandes de montée ;
#   - à jour → l'issue ouverte, s'il y en a une, est fermée.
#
# Le label `versions` n'est pas lu par la file d'attente : ces issues sont
# pour l'auteur, aucun agent ne les prend.
#
# Entrées (variables d'environnement) :
#   REPO       owner/name du dépôt de cours (défaut : $GITHUB_REPOSITORY)
#   GH_TOKEN   jeton gh : issues:write sur $REPO, lecture des dépôts des
#              sous-modules (github.token suffit pour des dépôts publics)
#   DRY_RUN    1 = affiche le plan et les corps d'issue, ne touche à rien
set -euo pipefail

REPO="${REPO:-${GITHUB_REPOSITORY:-}}"
DRY_RUN="${DRY_RUN:-0}"
LABEL="versions"
: "${REPO:?REPO requis}"
: "${GH_TOKEN:?GH_TOKEN requis}"
[ -f .gitmodules ] || { echo "Pas de sous-module : rien à vérifier."; exit 0; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# Section « ## vX.Y.Z … » d'un CHANGELOG, jusqu'au titre ou au `---` suivant.
section() { # $1 = fichier, $2 = version
  awk -v v="$2" '
    $0 ~ "^## " v "([^0-9.]|$)" { f=1; next }
    f && (/^## / || /^---[[:space:]]*$/) { exit }
    f { print }
  ' "$1" | awk 'NF {p=1} p'
}

# Issue ouverte « [versions] <chemin> » : numéro, ou vide.
issue_ouverte() { # $1 = titre
  gh issue list --repo "$REPO" --label "$LABEL" --state open --limit 100 \
    --json number,title --jq ".[] | select(.title == \"$1\") | .number" | head -1
}

en_retard=0
while read -r cle chemin <&3; do
  nom="${cle#submodule.}"; nom="${nom%.path}"
  url="$(git config -f .gitmodules --get "submodule.${nom}.url")"
  depot="$(printf '%s\n' "$url" | sed -nE 's#^(git@github\.com:|https://github\.com/)([^/]+/[^/.]+)(\.git)?/?$#\2#p')"
  titre="[versions] $chemin"
  [ -n "$depot" ] || { echo "$chemin : pas un dépôt GitHub ($url), ignoré."; continue; }
  epingle="$(git ls-tree HEAD "$chemin" | awk '$2 == "commit" {print $3}')"
  [ -n "$epingle" ] || { echo "::warning::$chemin : aucun commit épinglé dans HEAD."; continue; }

  if ! gh api "repos/$depot/tags" --paginate --jq '.[] | [.name, .commit.sha] | @tsv' \
      > "$tmp/tags.tsv" 2>"$tmp/err"; then
    echo "::warning::$chemin : tags de $depot illisibles ($(head -1 "$tmp/err")), ignoré."
    continue
  fi
  grep -E '^v[0-9]+\.[0-9]+\.[0-9]+[[:space:]]' "$tmp/tags.tsv" | sort -V -k1,1 > "$tmp/semver.tsv" || true
  [ -s "$tmp/semver.tsv" ] || { echo "$chemin : $depot n'a pas de release vX.Y.Z, ignoré."; continue; }
  derniere="$(tail -1 "$tmp/semver.tsv" | cut -f1)"

  actuelle="$(awk -F'\t' -v s="$epingle" '$2 == s {t=$1} END {print t}' "$tmp/semver.tsv")"
  if [ "$actuelle" = "$derniere" ]; then
    echo "$chemin : à jour ($derniere)."
    n="$(issue_ouverte "$titre")"
    if [ -n "$n" ]; then
      echo "  → fermer #$n"
      [ "$DRY_RUN" = 1 ] || {
        gh issue comment "$n" --repo "$REPO" --body "\`$chemin\` épingle désormais \`$derniere\`, la dernière release. Fermeture automatique." >/dev/null
        gh issue close "$n" --repo "$REPO" --reason completed >/dev/null
      }
    fi
    continue
  fi

  # Base : le tag épinglé, ou le plus haut tag dont le commit épinglé descend.
  base="$actuelle"; epingle_lisible="\`$actuelle\`"
  if [ -z "$base" ]; then
    while IFS=$'\t' read -r tag sha <&4; do
      statut="$(gh api "repos/$depot/compare/$sha...$epingle" --jq .status 2>/dev/null || true)"
      [ "$statut" = "ahead" ] && base="$tag"
    done 4< "$tmp/semver.tsv"
    if [ -n "$base" ]; then
      epingle_lisible="\`${epingle:0:7}\` (\`$base\` + des commits, pas une release)"
    else
      epingle_lisible="\`${epingle:0:7}\` (antérieur à toute release)"
    fi
  fi
  if [ -n "$base" ]; then
    awk -F'\t' -v b="$base" 'f {print $1} $1 == b {f=1}' "$tmp/semver.tsv" > "$tmp/a-franchir"
  else
    cut -f1 "$tmp/semver.tsv" > "$tmp/a-franchir"
  fi
  majeur_base="$(printf '%s' "${base#v}" | cut -d. -f1)"
  en_retard=$((en_retard + 1))
  echo "$chemin : $epingle_lisible → $derniere ($(tr '\n' ' ' < "$tmp/a-franchir"))"

  gh api "repos/$depot/contents/CHANGELOG.md?ref=$derniere" \
    -H "Accept: application/vnd.github.raw" > "$tmp/CHANGELOG.md" 2>/dev/null || : > "$tmp/CHANGELOG.md"

  {
    echo "\`$chemin\` ([\`$depot\`](https://github.com/$depot)) épingle $epingle_lisible ; la dernière release est [\`$derniere\`](https://github.com/$depot/releases/tag/$derniere)."
    echo
    echo "## Versions à franchir"
    echo
    while read -r v; do
      majeur="$(printf '%s' "${v#v}" | cut -d. -f1)"
      if [ -z "$majeur_base" ] || [ "$majeur" != "$majeur_base" ]; then
        echo "- [\`$v\`](https://github.com/$depot/releases/tag/$v) — ⚠️ **majeure** : elle peut demander de modifier les sources du cours"
        majeur_base="$majeur"
      else
        echo "- [\`$v\`](https://github.com/$depot/releases/tag/$v)"
      fi
    done < "$tmp/a-franchir"
    echo
    echo "## Monter"
    echo
    echo '```bash'
    echo "git -C $chemin fetch --tags && git -C $chemin checkout $derniere"
    echo "git add $chemin && git commit -m \"build($chemin): passe $chemin en $derniere\""
    echo '```'
    echo
    echo "Dans une PR, en appliquant ce que dit chaque section ci-dessous."
    case "$depot" in
      */ocots-conventions)
        echo "Avant de fusionner : \`./conventions/bin/ocots-lint synchroniser --dry-run\` montre les issues que le prochain lundi ouvrira ou fermera (\`uv\` requis)." ;;
      */ocots-latex-template)
        echo "Recompiler les documents dont le PDF est suivi par git, si la version change leur rendu." ;;
    esac
    echo
    echo "## Ce que dit le CHANGELOG"
    while read -r v; do
      echo
      echo "<details><summary><code>$v</code></summary>"
      echo
      if [ -s "$tmp/CHANGELOG.md" ] && s="$(section "$tmp/CHANGELOG.md" "$v")" && [ -n "$s" ]; then
        printf '%s\n' "$s"
      else
        echo "_Pas de section \`$v\` dans le CHANGELOG : voir la [release](https://github.com/$depot/releases/tag/$v)._"
      fi
      echo
      echo "</details>"
    done < "$tmp/a-franchir"
    echo
    echo "---"
    echo "_Détecté par \`ocourses/agents\`, checker \`versions\`. Fermée automatiquement quand \`$chemin\` épingle \`$derniere\` ou plus._"
  } > "$tmp/corps.md"
  # Limite GitHub : 65 536 caractères par corps d'issue.
  if [ "$(wc -c < "$tmp/corps.md")" -gt 60000 ]; then
    head -c 60000 "$tmp/corps.md" > "$tmp/c" && printf '\n\n_… tronqué : lire le CHANGELOG complet._\n' >> "$tmp/c"
    mv "$tmp/c" "$tmp/corps.md"
  fi

  n="$(issue_ouverte "$titre")"
  if [ "$DRY_RUN" = 1 ]; then
    echo "  → ${n:+mettre à jour #$n}${n:-créer « $titre »}"
    sed 's/^/    | /' "$tmp/corps.md"
    continue
  fi
  gh label create "$LABEL" --repo "$REPO" --color c5def5 \
    --description "Sous-module en retard sur sa dernière release" 2>/dev/null || true
  if [ -z "$n" ]; then
    gh issue create --repo "$REPO" --title "$titre" --label "$LABEL" --body-file "$tmp/corps.md" >/dev/null
    echo "  → issue créée"
  elif [ "$(gh issue view "$n" --repo "$REPO" --json body --jq .body)" != "$(cat "$tmp/corps.md")" ]; then
    gh issue edit "$n" --repo "$REPO" --body-file "$tmp/corps.md" >/dev/null
    echo "  → #$n mise à jour"
  else
    echo "  → #$n inchangée"
  fi
done 3< <(git config -f .gitmodules --get-regexp '^submodule\..*\.path$')

echo "Sous-modules en retard : $en_retard"
