# Rôle — migration vers le template LaTeX `ocots`

## Mission

Faire passer **le fichier `.tex` indiqué dans la tâche** (et lui seul) au
template `ocots`, **sans rien changer au fond** : énoncés, formules, valeurs
numériques, ordre des questions restent identiques caractère pour caractère. Tu
changes la **forme** — classe, préambule, noms d'environnements, macros.

## Périmètre

- Un seul fichier `.tex`, plus si besoin son `.latexmkrc` (à créer s'il n'existe
  pas, sur le modèle de `td/td1/.latexmkrc`, pour que la CI puisse compiler).
- **Interdit** : toucher au texte, aux maths, à un autre fichier du cours, au
  sous-module `template/` (lecture seule), aux corrigés (`sol_*.tex`) sauf si la
  tâche les désigne.
- Ne modifie pas non plus la mise en forme du texte (`{\bf ...}`, ponctuation…)
  sauf incompatibilité réelle avec le template.

## Cible

| Support | Classe + paquet |
|---|---|
| TD | `\documentclass[11pt]{ocots-td}` + `\usepackage[lang=fr, theme=ocots, solutions=none, math={analysis,control}, institution={n7}]{ocots}` |
| Poly | `\documentclass[11pt,twoside]{ocots-book}` + `\usepackage[lang=fr, theme=ocots, solutions=end, math={analysis,control}]{ocots}` |
| Examen | `\documentclass[11pt]{ocots-exam}` + idem TD |

- Retire les `\usepackage` que le template fournit déjà (babel, inputenc,
  amsmath, amssymb, mathrsfs, hyperref, graphicx, tikz, enumitem, xspace,
  fancyhdr/fancyheadings…) et les réglages maison devenus inutiles
  (`\theoremstyle`, `\renewcommand{\tilde}`…).
- Métadonnées `\title \shorttitle \numero \date \discipline \promotion` :
  inchangées. `\maketitle` conservé. Une page de titre « manuelle »
  (`\title{{\bf ...}\\ ...}` avec logo) se convertit en ces métadonnées.

## Renommage des environnements

`exer`→`exercise` · `quest`→`question` · sous-questions
(`enumerate[label=\alph*)]` + `\item`)→`subquestion` · `rmq`/`rmq*`→`remark`/`remark*`
· `thm`→`theorem{}{}` · `prop`→`proposition{}{}` · `cor`→`corollary{}{}` ·
`lem`→`lemma` · `defi`→`definition{}{}` · `exem`→`example` · `demon`→`proof`.

- Boîtes à titre : deux arguments obligatoires, éventuellement vides —
  `\begin{theorem}{}{}`. Ne pose un label (`\begin{theorem}{}{thm:xxx}`) que si
  le résultat est cité ailleurs (vérifie au `grep`).
- `\begin{exercise}` n'accepte **pas** de titre libre, seulement des clés
  (`label`, `points`, `nosolution`). Une citation de source
  (`\begin{exer}[Sontag 1.4]`) se remet en **texte d'intro** de l'exercice, on
  ne la perd pas.
- Corrigé au fil du texte : `\solution` (commande) dans l'`exercise`, ou
  `\begin{correction}` hors boîte.

## Macros maison

- `\iere`, `\ieme` : fournis par babel-french (chargé par le template). Garde
  l'usage tel quel.
- `\veps` : fourni par `math=base`. Vérifie avant de supposer.
- `\IR \IN \IZ \IQ \IC` (de `tpN7`) → `\R \N \Z \Q \C` (du template) si présents,
  sinon garde une def locale.
- `\fonction`, `\diag`, `\trace`, `\rang`… : si absents du template
  (`grep` dans `template/tex/math/`), garde une **définition locale minimale
  commentée** dans le préambule et **liste-la dans le bilan**. N'invente jamais
  une macro du template.

## Méthode

1. Plan dans le fichier de suivi (préambule proposé, table de renommage,
   macros sans équivalent).
2. Lis `template/examples/td/main.tex` (ou `poly/`) en entier ; consulte
   `template/doc/commandes.md` par `grep`/`sed` ciblés, pas en entier.
3. Commits par lot : préambule ; en-tête ; puis chaque exercice / chapitre.
   Pour un poly multi-fichier, un commit par fichier `\input`é.
4. Vérifie à chaque lot que `git diff` ne montre que forme + renommage.

## Diff idéal

Préambule remplacé, environnements renommés, `.latexmkrc` ajouté si besoin — et
**tout le reste identique caractère pour caractère**.
