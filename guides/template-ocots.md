# Guide — utilisation du template `ocots`

Le template `ocots` (`ocourses/ocots-latex-template`, tiré en sous-module
`template/`) sert les quatre supports — poly, diapos, TD, examen — avec **une
seule API** : un énoncé se colle tel quel du TD au polycopié.

Toujours lire `template/README.md` et `template/doc/commandes.md` avant d'agir,
et l'exemple compilable du support visé (`template/examples/{poly,td,exam,slides}/main.tex`).

## Préambule

| Support | Classe | Package |
|---------|--------|---------|
| Poly | `\documentclass[11pt,twoside]{ocots-book}` | `\usepackage[lang=fr, theme=ocots, solutions=end, math=analysis]{ocots}` |
| TD | `\documentclass[11pt]{ocots-td}` | `\usepackage[lang=fr, theme=ocots, solutions=none, math=analysis, institution={n7}]{ocots}` |
| Examen | `\documentclass[11pt]{ocots-exam}` | idem TD |
| Diapos | `\documentclass[9pt,t]{beamer}` | `\usepackage[lang=fr, theme=legacy-dark]{ocots}` |

- `theme=` est facultatif (`ocots` sur papier, `legacy-dark` en diapos).
- `math` et `institution` acceptent plusieurs valeurs **entre accolades** :
  `institution={insa,n7}` — jamais `institution=insa,n7`.
- Ne **pas** recopier de `fancyhdr`, de réglage de marges ou de macros que le
  template fournit déjà.

## Environnements (définis une seule fois, mêmes noms partout)

- Boîtes à titre, compteur commun numéroté dans la section :
  `theorem`, `definition`, `proposition`, `corollary`, `conjecture` —
  **deux arguments obligatoires, éventuellement vides** :
  `\begin{theorem}{Titre}{étiquette} … \end{theorem}`, cité par `\ref{thm:étiquette}`.
- Au fil du texte : `lemma`, `example`, `remark` (+ variantes étoilées non
  numérotées). `example`/`example*` acceptent une note : `\begin{example*}[note]`.
- Blocs étiquetés : `assumption` (H1, H2…), `openquestion` (Q1…),
  `difficulty` (D1…) + variantes `*`.
- Preuves : `proof`.

## Exercices et corrigés

```latex
\ocotscollectsolutions            % début de partie (mode end)
\begin{exercise}[label=matrices, points=4]
    Énoncé.
    \begin{question} … \end{question}
    \begin{question}
        \begin{subquestion} … \end{subquestion}
    \end{question}
\solution                         % commande, PAS un environnement
    \begin{question} … \end{question}
\end{exercise}
\ocotsprintsolutions              % où les corrigés paraissent
```

- Clés de `\begin{exercise}[…]` : `label=<nom>` (pose `\label{ex:<nom>}`),
  `points=<n>`, `nosolution`.
- `\solution` est une **commande** (une `tcolorbox` se coupe au premier niveau).
- Option paquet `solutions=none|inline|end` : en `none`/`inline`,
  `\ocotscollectsolutions` / `\ocotsprintsolutions` sont neutres — le document
  ne change pas d'un mode à l'autre.
- Correction hors boîte (TD, examen) : `\begin{correction} … \end{correction}`
  (disparaît en `solutions=none`).
- `\newquestion` force la question suivante ; `\exercisenotext` avale la ligne
  vide quand l'énoncé n'a pas d'intro.

## TD et examens

Métadonnées portées par les en-têtes : `\title` / `\shorttitle`, `\numero`,
`\date`, `\discipline`, `\promotion`. `\maketitle` compose logos + titre.
Environnements propres : `instruction`, `instructions` (non numérotés),
`docpart` (Partie 1, 2…).

## Macros mathématiques

- `math=base` : `\norm`, `\abs`, `\prodscal`, `\enstq{}{}`…
- `math=analysis` : ajoute `\R`, `\M_n`, `\Ical`, `\xCn{0}`, `\grandO`,
  `\petito`, `\BallClosed`…
- `math=control` : macros d'automatique.
- **Vérifier dans `template/math/ocots-math-*.sty`** avant de supposer qu'une
  macro existe. Une macro maison sans équivalent se garde dans le préambule du
  document, commentée, et se signale.

## Migrer un document v0

Deux lignes de préambule suffisent :

```latex
% avant
\documentclass[11pt,onecolumn,twoside]{../template/book}
\usepackage[correction, relativePath=\relativePath]{\relativePath/book}
% après
\documentclass[11pt,twoside]{ocots-book}
\usepackage[lang=fr, solutions=end, math=analysis]{ocots}
```

Le **corps n'est pas retouché** : `ocots-compat.sty` garde les noms v0
(`mytheorem`, `mydefinition`, `myexercisecb`, `\solutioncb`, `\myemph`,
`no solution`…). Ces alias sont dépréciés : chaque ligne migrée vers les noms
`ocots` est une ligne de `ocots-compat.sty` en moins.

## Compilation

`TEXINPUTS` pointe sur le sous-module (voir `.latexmkrc` du dépôt). Vérifier
avec `latexmk` ; la CI du dépôt de cours gère la compilation lourde, pas le run
d'agent.
