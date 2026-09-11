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
- **Examen (`ocots-exam`) — champs de consignes dédiés** : `\duree{}`,
  `\documents{}`, `\calculatrice{}`, `\examnote{}` (dans cet ordre de
  composition), appelés automatiquement par `\maketitle`
  (`template/doc/commandes.md`, § « TD et examens »). Un bloc manuel
  `\begin{instructions}…\end{instructions}` qui ne contient *que* durée /
  documents autorisés / calculatrice se convertit en ces champs — mapping
  formel, pas un changement de fond. S'il contient autre chose (consignes
  propres au sujet), garde `instructions` (toujours valide, migration
  progressive prévue par le template) ou mets le surplus dans `\examnote`.
  **N'ajoute pas** les clés `points=` sur les `exercise` ni le barème
  calculé automatiquement de ta propre initiative — ça change ce qui est
  affiché (barème calculé vs. énoncé tel quel par l'auteur), ce n'est pas
  une migration de forme. Signale la possibilité dans le bilan, fais-le
  seulement si la tâche le demande explicitement.

## Renommage des environnements

`exer`→`exercise` · `quest`→`question` · sous-questions
(`enumerate[label=\alph*)]` + `\item`)→`subquestion` · `rmq`/`rmq*`→`remark`/`remark*`
· `thm`→`theorem` · `prop`→`proposition` · `cor`→`corollary` ·
`lem`→`lemma` · `defi`→`definition` · `exem`→`example` · `demon`→`proof`.

- **Boîtes à titre : un seul argument optionnel, à clés** — `title=`,
  `label=`, `note=` (aucune n'est obligatoire) :
  `\begin{theorem}[title={Titre}, label=thm:xxx]`. **Pas** de syntaxe à deux
  arguments positionnels (`\begin{theorem}{}{}`) — c'est l'ancienne forme, à
  ne pas reproduire même « vide ». Le label est posé **tel quel**, le
  template n'ajoute aucun préfixe (vérifie sur `template/examples/content/boxes.tex`
  si un doute : chaque appel y est visible). Ne pose un label que si le
  résultat est cité ailleurs (vérifie au `grep`).
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
- Macro absente du template (`grep` dans `template/tex/math/` et
  `template/doc/notations.md` pour vérifier) : garde une **définition locale
  minimale commentée** dans le préambule et **liste-la dans le bilan**.
  N'invente jamais une macro du template.

### Notations mathématiques : noms actuels, pas les alias de compat

Le module maths a été renommé en bloc (`\fonction`→`\functiondef`,
`\rang`→`\rank` (désormais localisé fr/en tout seul, plus de doublon),
`\dd`/`\xdif`/`\diff`→`\dif`, `\petito`→`\smallo`, `\grandO`→`\bigO`,
`\enstq`→`\setst`, `\intervalleff`/`\intervalleoo`/…→`\intervalcc`/
`\intervaloo`/…, `\Ical`→`\TimeInterval`, `\Vcal`→`\Neighborhoods`,
`\Lcal`/`\xCn`→`\ContinuousLinear`/`\Cclass`, `\Sn`/`\Nb`/`\Rn`/`\Rp`/…→
`\Sphere`/`\Nbar`/`\Rnonpos`/`\Rnonneg`/…, et une quinzaine d'autres — **la
référence est `template/doc/notations.md`, pas cette liste** (elle peut
elle-même dater). `\M` (matrice, gras) a disparu **sans alias** : utilise
`\calset{M}` (générique) ou une définition locale si le rendu gras est
voulu.

- Les anciens noms compilent encore (`ocots-compat.sty` les garde en alias),
  **mais utilise systématiquement les noms actuels** dans ce que tu écris —
  ce sont des alias de transition pour du contenu pas encore migré, pas une
  API à perpétuer. Une macro maison locale qui fait doublon avec un nom
  *actuel* du template (pas un alias) : adopte celui du template.
- **`\functiondef` (ex-`\fonction`) produit un `array` nu** : ne s'utilise
  qu'en mode maths (`\[ \functiondef{...} \]`). L'ancien `\fonction` de
  `tpN7`/`Jgbook` s'auto-encadrait — si l'appel d'origine était hors maths,
  encadre-le, ou garde la définition locale d'origine. **Compile pour
  trancher.**
- L'usage d'un ancien nom déclenche un avertissement de compilation
  (`Deprecated mathematical macro used`), **une seule fois par run** même
  s'il y en a plusieurs — ce n'est pas un compteur. Le voir dans
  `latex-compile` = il reste au moins un ancien nom quelque part dans le
  document migré ; localise-le au `grep` (pas à l'œil), ne conclus pas
  « migré » sur la seule absence d'erreur de compilation.

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
   `template/doc/commandes.md` et `template/doc/notations.md` (référence des
   macros mathématiques) par `grep`/`sed` ciblés, pas en entier.
3. **Un fichier à la fois, commité avant de passer au suivant.** Ordre :
   préambule + en-tête du pilote → `git add <pilote>` + commit ; puis chaque
   fichier `\input`é → `git add <ce fichier>` + commit. **Ne garde jamais
   plusieurs fichiers non commités en parallèle** : sur un poly de plusieurs
   centaines de lignes, c'est la seule façon de ne pas perdre le travail si le
   run est coupé (rate-limit, timeout).
4. Vérifie à chaque commit que `git diff --staged` ne montre que forme +
   renommage.
5. **`latex-compile <pilote>` à la fin** (et quand utile en cours de route) :
   le document doit compiler avant le bilan. Boucle compiler → lire l'erreur →
   corriger. Le bilan ne dit « migré » que si `latex-compile` passe ; sinon il
   détaille l'erreur résiduelle (fichier, ligne, message) et ce que tu as
   essayé.

## Diff idéal

Préambule remplacé (fichier pilote), environnements renommés dans **tous** les
fichiers de la chaîne d'`\input`, `.latexmkrc` ajouté si besoin — et **tout le
reste identique caractère pour caractère**. Le document compile.
