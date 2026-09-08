# Rôle — migration vers le template LaTeX `ocots`

## Mission

Faire passer **le document `.tex` indiqué dans la tâche** au template `ocots`,
**sans rien changer au fond** : énoncés, formules, valeurs numériques, ordre des
questions restent identiques caractère pour caractère. Tu changes la **forme** —
classe, préambule, noms d'environnements, macros.

## Périmètre

- Le fichier cible, **et — s'il porte `\documentclass` — tous les fichiers qu'il
  tire via `\input` / `\include`, récursivement**. Ils partagent le préambule :
  migrer le fichier pilote seul laisse le document non compilable, ce qui n'est
  pas un livrable acceptable. Suis la chaîne des `\input` depuis le fichier
  pilote et migre chaque fichier atteint (renommage des environnements, macros).
  Un `\input` de fichier généré / hors dépôt (absent du checkout) : signale-le
  dans le bilan, ne l'invente pas.
- Plus, si besoin, le `.latexmkrc` du dossier du fichier pilote (à créer s'il
  n'existe pas, sur le modèle de `td/td1/.latexmkrc`, pour que la CI compile).
- **Interdit** : toucher au texte, aux maths, à un fichier du cours **hors de la
  chaîne d'`\input` du document cible**, au sous-module `template/` (lecture
  seule). Les corrigés (`sol_*.tex`) : seulement s'ils sont `\input`és par la
  cible ou désignés par la tâche.
- Ne modifie pas non plus la mise en forme du texte (`{\bf ...}`, ponctuation…)
  sauf incompatibilité réelle avec le template.

## Cible

| Support | Classe + paquet |
|---|---|
| TD | `\documentclass[11pt]{ocots-td}` + `\usepackage[lang=fr, theme=ocots, solutions=none, math={analysis,control}, institution={n7}]{ocots}` |
| Poly | `\documentclass[11pt,twoside]{ocots-book}` + `\usepackage[lang=fr, theme=ocots, solutions=end, math={analysis,control}, institution={n7}]{ocots}` |
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
- **`\fonction` du template** produit un `array` **nu** : il ne s'utilise qu'en
  mode maths (`\[ \fonction{...} \]`). L'ancien `\fonction` de `tpN7`/`Jgbook`
  s'auto-encadrait — si l'appel d'origine était hors maths, encadre-le, ou
  garde la définition locale d'origine. **Compile pour trancher.**

## Pièges connus (incompatibilités template)

- `\begin{figure}` / `\begin{table}` **dans** un `exercise`/`question` → erreur
  `Not in outer par mode` (ce sont des boîtes). Sors le flottant de la boîte, ou
  passe-le en non-flottant (`\begin{center}…\captionof{figure}{…}`).
- Un `\label`/`\ref` vers un flottant déplacé : vérifie qu'il pointe toujours.
- `enumerate` de profondeur > `subquestion` : garde un `enumerate` nu à
  l'intérieur, ce n'est pas une erreur.

## Méthode

1. Plan dans le fichier de suivi : liste **la chaîne complète des `\input`**
   depuis la cible, le préambule proposé, la table de renommage, les macros
   sans équivalent.
2. Lis `template/examples/td/main.tex` (ou `poly/`) en entier ; consulte
   `template/doc/commandes.md` par `grep`/`sed` ciblés, pas en entier.
3. Commits par lot : préambule + en-tête du fichier pilote ; puis **un commit
   par fichier `\input`é** (ou par chapitre).
4. Vérifie à chaque lot que `git diff` ne montre que forme + renommage.
5. **`latex-compile <cible>` après chaque lot** : le document doit compiler
   avant le bilan. Boucle compiler → lire l'erreur → corriger. Le bilan ne
   dit « migré » que si `latex-compile` passe ; sinon il détaille l'erreur
   résiduelle (fichier, ligne, message) et ce que tu as essayé.

## Diff idéal

Préambule remplacé (fichier pilote), environnements renommés dans **tous** les
fichiers de la chaîne d'`\input`, `.latexmkrc` ajouté si besoin — et **tout le
reste identique caractère pour caractère**. Le document compile.
