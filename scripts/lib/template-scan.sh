#!/usr/bin/env bash
# Couche « scan » partagée — verdict de conformité template pour UN ou
# PLUSIEURS pilotes .tex, sans aucune gestion d'issues. Extrait de
# checkers/template-migration.sh (extraction des noms legacy, chaîne
# \input/\include, classification) pour être réutilisée par
# scripts/queue-next.sh : après un run de migration, la file revérifie que
# la branche de la PR ne contient plus aucun nom de ocots-compat.sty dans
# la chaîne du pilote cible — critère de succès fort, là où « une PR au bon
# titre existe » laissait passer les diffs vides (ocourses/agents#15).
#
# Usage : template-scan.sh <ocots-compat.sty> <pilote> [pilote…]
#   cwd  = racine du dépôt de cours scanné (les pilotes sont des chemins
#          relatifs à cette racine).
#   Sortie : une ligne TSV par pilote — "STATUT<TAB>pilote<TAB>noms"
#     STATUT ∈ CLEAN | MISSING | LEGACY
#     noms   = noms legacy restants, séparés par des espaces (vide pour
#              CLEAN/MISSING). Ordre alphabétique, dédupliqués.
#   Exit : 0 même si des pilotes sont non conformes — les verdicts sont de
#          la donnée, pas des erreurs. ≠0 uniquement sur erreur d'usage
#          (compat absent, aucun pilote).
#
# La liste des noms « legacy » est extraite de ocots-compat.sty à CHAQUE
# appel — jamais codée en dur : le fichier maigrit au fil des migrations
# (cf. son en-tête), le détecteur se resserre tout seul. Même contrat que
# le checker ; toute divergence créerait des verdicts différents entre la
# détection (hebdo) et la revérification (post-run) — c'est précisément le
# défaut que cette factorisation élimine.
set -euo pipefail

COMPAT="${1:?usage: template-scan.sh <ocots-compat.sty> <pilote> [pilote…]}"
shift
[ "$#" -gt 0 ] || { echo "usage: template-scan.sh <ocots-compat.sty> <pilote> [pilote…]" >&2; exit 2; }
[ -f "$COMPAT" ] || { echo "::error::compat introuvable : $COMPAT" >&2; exit 2; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# ---------------------------------------------------------------------------
# 1. Extraire les noms « legacy » depuis ocots-compat.sty
#    (motifs identiques à la version pré-factorisation de
#    checkers/template-migration.sh — y compris les `|| true` : `grep` sort 1
#    dès qu'un motif ne trouve rien, ce qui arrive légitimement quand le
#    dépôt de cours épingle un sous-module template plus ancien, où telle
#    forme d'alias n'existe pas encore ; sous `set -e -o pipefail`, laisser
#    passer ce 1 tuerait tout le script)
# ---------------------------------------------------------------------------

# Environnements : \NewDocumentEnvironment{nom} et \ocotsaliasenv{nom}{...}
# (on exclut les noms avec '@' : macros internes du fichier de compat,
# jamais tapées par un auteur de document)
{
  grep -oE '\\NewDocumentEnvironment\{[A-Za-z@*]+\}' "$COMPAT" | sed -E 's/.*\{(.*)\}/\1/' || true
  grep -oE '\\ocotsaliasenv\{[A-Za-z@*]+\}' "$COMPAT" | sed -E 's/.*\{(.*)\}/\1/' || true
} | { grep -v '@' || true; } | sort -u > "$tmp/envs.txt"

# Commandes : \newcommand{\nom}, \let\nom... et \DeclareRobustCommand{\nom}
# (ce dernier motif porte à lui seul ~80 alias de macros mathématiques
# renommées par le chantier 2 du template — sans lui le détecteur les rate
# toutes silencieusement)
{
  grep -oE '\\newcommand\{\\[A-Za-z@]+\}' "$COMPAT" | sed -E 's/.*\{\\(.*)\}/\1/' || true
  grep -oE '^\\let\\[A-Za-z@]+' "$COMPAT" | sed -E 's/^\\let\\//' || true
  grep -oE '\\DeclareRobustCommand\{\\[A-Za-z@]+\}' "$COMPAT" | sed -E 's/.*\{\\(.*)\}/\1/' || true
} | { grep -v '@' || true; } | sort -u > "$tmp/cmds.txt"

n_envs=$(wc -l < "$tmp/envs.txt"); n_cmds=$(wc -l < "$tmp/cmds.txt")
echo "Noms legacy extraits : $n_envs environnement(s), $n_cmds commande(s)" >&2
[ "$n_envs" -gt 0 ] || [ "$n_cmds" -gt 0 ] || { echo "::warning::aucun nom legacy extrait, ocots-compat.sty a-t-il changé de format ?" >&2; }

envs_re="$(paste -sd'|' "$tmp/envs.txt")"
cmds_re="$(paste -sd'|' "$tmp/cmds.txt")"

# ---------------------------------------------------------------------------
# 2. Chaîne \input / \include, récursive (avec garde anti-cycle)
# ---------------------------------------------------------------------------
collect_chain() {
  local file="$1" seen_var="$2"
  [ -f "$file" ] || return 0
  case " $(eval echo \$"$seen_var") " in *" $file "*) return 0 ;; esac
  eval "$seen_var=\"\$$seen_var $file\""
  echo "$file"
  local dir; dir="$(dirname "$file")"
  { grep -oE '\\(input|include)\{[^}]+\}' "$file" 2>/dev/null || true; } \
    | sed -E 's/.*\{(.*)\}/\1/' \
    | while IFS= read -r inc; do
        local incfile="$inc"
        [[ "$incfile" == *.tex ]] || incfile="${incfile}.tex"
        local candidate="$dir/$incfile"
        candidate="${candidate#./}"
        collect_chain "$candidate" "$seen_var"
      done
}

# ---------------------------------------------------------------------------
# 3. Classification — une ligne TSV par pilote : STATUT<TAB>pilote<TAB>noms
# ---------------------------------------------------------------------------
for pilot in "$@"; do
  seen=""
  # while-read plutôt que mapfile : ce composant reste ainsi exécutable sous
  # le bash 3.2 de macOS — testable en local, hors CI ubuntu.
  chain=()
  while IFS= read -r chain_file; do chain+=("$chain_file"); done \
    < <(collect_chain "$pilot" seen)

  # Signal de migration : \usepackage[...]{ocots}, seul signal fiable pour
  # tous les supports (ocots-td/book/exam pour TD/poly/examen, mais les
  # diapositives restent sur \documentclass{beamer} + \usepackage{ocots} —
  # pas de classe ocots-* dédiée). Les options peuvent tenir sur plusieurs
  # lignes, d'où le deuxième motif (la ligne qui referme le crochet).
  has_pkg=0
  grep -qE '\\usepackage(\[[^]]*\])?\{ocots\}|\]\{ocots\}' "$pilot" 2>/dev/null && has_pkg=1

  status="CLEAN"
  found_names=""

  if [ "$has_pkg" -eq 0 ]; then
    status="MISSING"
  else
    for f in "${chain[@]}"; do
      if [ -n "$envs_re" ]; then
        m=$(grep -oE "\\\\begin\{(${envs_re})\}" "$f" 2>/dev/null | sed -E 's/\\begin\{(.*)\}/\1/' || true)
        [ -n "$m" ] && found_names="$found_names"$'\n'"$m"
      fi
      if [ -n "$cmds_re" ]; then
        m=$(grep -oE "\\\\(${cmds_re})\\b" "$f" 2>/dev/null | sed -E 's/^\\//' || true)
        [ -n "$m" ] && found_names="$found_names"$'\n'"$m"
      fi
    done
    found_names="$(printf '%s\n' "$found_names" | sed '/^$/d' | sort -u)"

    # Une macro peut être *redéfinie localement* dans le dépôt de cours
    # (\newcommand/\renewcommand/\DeclareRobustCommand/\let), délibérément,
    # pour un usage qui ne colle pas à la version du template — cas réel et
    # documenté (poly/automatique.tex redéfinit \fonction en 4 args car le
    # \functiondef du template est une array 5 args nue). Ce n'est alors pas
    # un alias de compat en jeu : exclure ces noms-là des trouvailles évite
    # un faux positif qui gâcherait un run de migration pour rien.
    if [ -n "$found_names" ]; then
      kept=""
      while IFS= read -r name; do
        [ -n "$name" ] || continue
        overridden=0
        for f in "${chain[@]}"; do
          grep -qE "\\\\(re)?newcommand\{\\\\${name}\}|\\\\DeclareRobustCommand\{\\\\${name}\}|\\\\let\\\\${name}\\\\" "$f" 2>/dev/null \
            && { overridden=1; break; }
        done
        [ "$overridden" -eq 0 ] && kept="$kept"$'\n'"$name"
      done <<< "$found_names"
      found_names="$(printf '%s\n' "$kept" | sed '/^$/d' | sort -u)"
    fi

    [ -n "$found_names" ] && status="LEGACY"
  fi

  names_field=""
  [ -n "$found_names" ] && names_field="$(printf '%s\n' "$found_names" | paste -sd' ' -)"
  printf '%s\t%s\t%s\n' "$status" "$pilot" "$names_field"
done
