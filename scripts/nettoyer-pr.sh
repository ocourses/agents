#!/usr/bin/env bash
# Voie mécanique (ocots-lint) — corrige UN fichier par `ocots-lint nettoyer`,
# SANS modèle, et ouvre (ou met à jour) une PR Draft.
#
# Appelé par .github/workflows/nettoyer.yml, depuis la racine du dépôt de
# cours (sous-module conventions >= v2.2.0 initialisé). Issue d'origine :
# `[nettoyer] <fichier>`, label `conventions-mecanique`, ouverte par
# `ocots-lint synchroniser`.
#
# Idempotent : la branche est déterministe, `ocots-lint/nettoyer/<fichier>`
# (même calcul que `branche_nettoyer` dans ocots-lint/synchroniser.py —
# contrat entre les deux). Relancer la reconstruit depuis la base et la
# repousse : la même PR est mise à jour, jamais dupliquée ; et tant qu'elle
# est ouverte, `synchroniser` ne recrée pas l'issue.
#
# `nettoyer` n'applique que des corrections dont l'équivalence est vérifiée,
# et ne touche pas une ligne exemptée. Garde-fou : si un autre fichier que
# la cible a bougé, on s'arrête sans rien pousser.
#
# Rien à corriger (déjà corrigé, ou exempté) : l'issue est commentée et
# fermée, sans PR.
#
# Entrées : REPO, TARGET, ISSUE, GH_TOKEN (contents + pull-requests + issues
# en écriture). CONVENTIONS_DIR (défaut : conventions).
set -euo pipefail

: "${REPO:?REPO requis}"
: "${TARGET:?TARGET requis (fichier .tex du cours)}"
: "${ISSUE:?ISSUE requis (numéro de l’issue [nettoyer])}"
: "${GH_TOKEN:?GH_TOKEN requis}"
CONVENTIONS_DIR="${CONVENTIONS_DIR:-conventions}"
RELAIS="${CONVENTIONS_DIR}/bin/ocots-lint"

[ -x "$RELAIS" ] || { echo "::error::$RELAIS introuvable — ocots-conventions >= v2.2.0 requises."; exit 1; }
[ -f "$TARGET" ] || { echo "::error::cible introuvable : $TARGET"; exit 1; }

branche="ocots-lint/nettoyer/$(printf '%s' "$TARGET" | sed 's#[^A-Za-z0-9._/-]#-#g')"
base="$(git rev-parse --abbrev-ref HEAD)"
echo "Cible : $TARGET — branche : $branche — base : $base"

git switch -q -C "$branche"
"$RELAIS" nettoyer C4 "$TARGET" --appliquer | tee /tmp/nettoyer.out

modifies="$(git diff --name-only)"
if [ -z "$modifies" ]; then
  gh issue comment "$ISSUE" --repo "$REPO" --body \
    "Rien à corriger mécaniquement dans \`$TARGET\` (déjà corrigé, ou exempté). Fermeture automatique." >/dev/null
  gh issue close "$ISSUE" --repo "$REPO" --reason completed >/dev/null
  echo "Rien à corriger : issue #$ISSUE fermée."
  exit 0
fi
if [ "$modifies" != "$TARGET" ]; then
  echo "::error::nettoyer a modifié d'autres fichiers que la cible :"
  printf '%s\n' "$modifies"
  exit 1
fi

git add -- "$TARGET"
git commit -q -m "style: corrections mécaniques de $TARGET (ocots-lint nettoyer)" \
  -m "Issue #$ISSUE. Sans modèle : corrections à équivalence vérifiée."
git push -q --force origin "$branche"

corps="$(mktemp)"
{
  echo "Corrections mécaniques de \`$TARGET\` par \`ocots-lint nettoyer\`, **sans modèle** : seules des corrections dont l'équivalence a été vérifiée (\`~:\` retirés, guillemets en \`\\enquote\` si \`csquotes\` est chargé), jamais sur une ligne exemptée."
  echo
  echo "Issue : #$ISSUE (fermée par la file quand cette PR est ouverte ; recréée par \`synchroniser\` seulement si la PR est fermée sans fusion)."
  echo
  echo "**À relire avant fusion.** La CI LaTeX du cours recompile le document."
  echo
  echo '```text'
  sed -n '1,40p' /tmp/nettoyer.out
  echo '```'
} > "$corps"

existante="$(gh pr list --repo "$REPO" --head "$branche" --state open --json number --jq '.[0].number // empty')"
if [ -n "$existante" ]; then
  gh pr edit "$existante" --repo "$REPO" --body-file "$corps" >/dev/null
  echo "PR #$existante mise à jour."
else
  gh pr create --repo "$REPO" --draft --base "$base" --head "$branche" \
    --title "[nettoyer] $TARGET" --body-file "$corps" >/dev/null
  echo "PR créée."
fi
