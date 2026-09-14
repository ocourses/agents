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
| Diapositives | `\documentclass[9pt,t]{beamer}` + `\usepackage[lang=fr, theme=ocots, solutions=none, math={analysis,control}, institution={n7}]{ocots}` |

- **Diapositives : pas de classe `ocots-*` dédiée** — seul `\documentclass{beamer}` +
  `\usepackage[...]{ocots}` signale la migration (c'est aussi le seul signal
  que `checkers/template-migration.sh` sait reconnaître pour ce support).
  N'invente pas de classe `ocots-beamer`/`ocots-slides` : elle n'existe pas.

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

### Alias d'environnements hérités (`my*`), tous supports

Un pilote **déjà migré** (classe/paquet corrects) peut encore utiliser les
alias transitoires de `ocots-compat.sty` — même logique que les macros
mathématiques ci-dessous, mais pour les environnements, **et sur tous les
supports, diapositives comprises**. Deux mécanismes différents y cohabitent,
d'où deux façons de migrer. Liste extraite du fichier à la date d'écriture de
ce rôle (`ocots-compat.sty` évolue : si un doute, revérifie avec
`grep -oE '\\(NewDocumentEnvironment|ocotsaliasenv)\{[A-Za-z@*]+\}' template/tex/ocots-compat.sty`
— c'est exactement ce que fait `checkers/template-migration.sh`, pas de liste figée à maintenir en double) :

- **Alias directs** (`\ocotsaliasenv`, simple renommage, même signature) :
  `myassumption`/`myassumption*`→`assumption`/`assumption*` ·
  `myquestionnement`→`openquestion` · `mydifficulty`→`difficulty` ·
  `myweb`→`web` · `proofdeb`/`proofmil`/`prooffin`→`proofbegin`/
  `proofmiddle`/`proofend` · `myquestion`→`question` ·
  `mysubquestion`→`subquestion` · `myexercise`→`exercise` ·
  `mycorr`/`mycorrection`→`correction` ·
  `myinstructions`/`myinstructions*`→`instructions` ·
  **`myframe`→`slide`** (diapositives — le seul de cette famille qui ne
  s'applique qu'à un seul support).
- **Alias à ancienne syntaxe** (`\NewDocumentEnvironment`, la v0 antérieure au
  template prenait des arguments positionnels) — renommer **et** convertir
  vers la syntaxe à clés actuelle (même règle que « Boîtes à titre »
  ci-dessus) :
  - `mytheorem{Titre}{cle}`→`theorem[title={Titre}, label=cle]`,
    `mydefinition`→`definition`, `myproposition`→`proposition`,
    `mycorollary`→`corollary`, `myconjecture`→`conjecture` — même schéma
    `{Titre}{cle}` à deux arguments positionnels pour les cinq. **Piège sur
    le label** : la v0 préfixait automatiquement `cle` (`thm:`, `def:`,
    `prop:`, `cor:`, `conj:` respectivement, sauf si `cle` portait déjà ce
    préfixe) avant de l'utiliser comme `label=`, alors que la syntaxe
    actuelle **ne préfixe rien**. Si `cle` est référencé ailleurs
    (`\ref{...}` — vérifie au `grep`), pose `label=` avec le préfixe
    correspondant explicitement pour ne pas casser la référence ; si `cle`
    n'est jamais référencé, pas besoin de label du tout (même règle que
    « Boîtes à titre »).
  - `mylemma`/`mylemma*`→`lemma`/`lemma*`, `myexample`/`myexample*`→
    `example`/`example*`, `myremark`/`myremark*`→`remark`/`remark*` — titre
    optionnel simple (`monenv[Titre]`→`monenv[title={Titre}]`), pas de
    second argument, pas de piège de label.
  - `myexercisecb` (ancienne syntaxe d'étiquette `\begin{myexercisecb}<etiquette>`)
    →`exercise[label=ex:etiquette]` (même convention de préfixe `ex:` que le
    reste des exercices).

Ces alias compilent (`ocots-compat.sty` les garde), **mais utilise
systématiquement les noms et la syntaxe actuels** — ce sont des passerelles
de transition pour du contenu pas encore migré, pas une API à perpétuer
(même principe que pour les macros mathématiques, cf. plus bas).
**Contrairement aux macros mathématiques, leur usage résiduel ne déclenche
(à la date d'écriture de ce rôle) aucun avertissement à la compilation** —
vérifie si ça a changé (`ocourses/ocots-latex-template#33`) avant de t'y
fier : tant que ce n'est pas le cas, ne conclus **jamais** « migré » sur la
seule absence d'erreur/avertissement de `latex-compile` pour ce qui est des
environnements — `grep` explicitement les noms `my*` restants dans toute la
chaîne `\input`, y compris pour un pilote beamer.

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

0. **`latex-compile <pilote>` en l'état, avant tout changement.** Sert de
   référence pour l'étape 5 : si le pilote ne compile déjà pas, pour une
   raison **étrangère à la migration** (bug préexistant, sans rapport avec le
   template ou le renommage), note l'erreur (fichier, ligne, message) et **ne
   tente pas de le corriger toi-même** sauf si la tâche le demande
   explicitement — un pilote cassé pour une raison hors migration reste hors
   périmètre, même si le corriger permettrait d'obtenir un document qui
   compile.
1. Plan dans le fichier de suivi : liste **la chaîne complète des `\input`**
   depuis la cible, le préambule proposé, la table de renommage, les macros
   sans équivalent.
2. Lis en entier l'exemple du support visé (structure des exemples revue
   régulièrement — si les chemins ci-dessous ne correspondent plus, cherche
   `find template/examples -iname '*.tex'` avant de conclure à un support
   sans exemple) : `template/examples/themes/ocots/td.tex`,
   `poly.tex`, `exam.tex` ou `slides.tex` selon le support, chacun
   `\input`ant le corps correspondant sous `template/examples/content/`
   (`td-body.tex`, `exam-body.tex`, `slides-body.tex`, ou plusieurs fichiers
   pour `poly.tex`). Consulte `template/doc/commandes.md` et
   `template/doc/notations.md` (référence des macros mathématiques) par
   `grep`/`sed` ciblés, pas en entier.
3. **Un fichier à la fois, commité avant de passer au suivant.** Ordre :
   préambule + en-tête du pilote → `git add <pilote>` + commit ; puis chaque
   fichier `\input`é → `git add <ce fichier>` + commit. **Ne garde jamais
   plusieurs fichiers non commités en parallèle** : sur un poly de plusieurs
   centaines de lignes, c'est la seule façon de ne pas perdre le travail si le
   run est coupé (rate-limit, timeout).
4. Vérifie à chaque commit que `git diff --staged` ne montre que forme +
   renommage.
5. **`latex-compile <pilote>` à la fin** (et quand utile en cours de route) :
   - Si l'étape 0 compilait déjà, ou si l'échec initial était **lié à la
     migration** (ancien préambule, macros non renommées) : le document doit
     compiler avant le bilan. Boucle compiler → lire l'erreur → corriger. Le
     bilan ne dit « migré » que si `latex-compile` passe ; sinon il détaille
     l'erreur résiduelle (fichier, ligne, message) et ce que tu as essayé.
   - Si l'étape 0 échouait déjà pour une raison **étrangère à la migration** :
     ne bloque pas le bilan sur ce point précis — confirme seulement que ton
     diff ne l'aggrave pas et ne le masque pas (comparaison des deux messages
     d'erreur), et signale-le explicitement dans le bilan plutôt que de
     conclure à un échec de la tâche.
   - **Vérifie `git status` juste après compilation.** `latexmk` peut modifier
     un fichier suivi par git en dehors des fichiers migrés — typiquement un
     PDF rendu committé (dossier qui ne l'ignore pas via `.gitignore`).
     Restaure tout fichier de ce type (`git checkout -- <fichier>`) avant de
     committer : un rendu recompilé (métadonnées, horodatage) n'est pas un
     livrable de migration, même visuellement identique, et ne doit pas
     polluer le diff.

## Diff idéal

Préambule remplacé (fichier pilote), environnements renommés dans **tous** les
fichiers de la chaîne d'`\input`, `.latexmkrc` ajouté si besoin — et **tout le
reste identique caractère pour caractère**. Le document compile, ou compilait
déjà mal avant la migration pour une raison qui lui est étrangère (bilan
explicite dans ce cas, sans tentative de correction hors périmètre). Aucun
fichier suivi par git modifié en dehors de la chaîne migrée (PDF rendu
restauré si la compilation l'a touché).
