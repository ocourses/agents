# Guide — rédaction d'un polycopié (règles de style)

Règles dégagées de la relecture pas à pas du cours *Calcul différentiel et EDO*
(`ocourses/calcul-differentiel-edo-enseignants`, `reports/poly-update-2026/`).
À appliquer par défaut ; les faire évoluer si un cas les contredit.

## Fil conducteur

**On n'enchaîne jamais des boîtes** (définition, théorème, proposition, remarque,
exemple) **sans texte autour.** Chaque boîte est amenée par une phrase qui dit
*pourquoi elle arrive*, et suivie d'une phrase qui *exploite* ce qu'elle apporte.
Le lecteur ne doit jamais tomber sur un énoncé sans savoir ce qu'on en fait.

## 1. Placement des hypothèses

- **Définitions** : sortir « Soient $f\colon U\to F$… » dans le texte qui
  précède ; la boîte ne garde que la condition définissante.
- **Théorèmes** : toutes les hypothèses **à l'intérieur** — un théorème doit
  rester citable isolément.
- **Propositions** : selon le contexte. Prolonge le texte qui précède → pas de
  répétition. Cadre nouveau (nouveaux espaces, notation neuve) → hypothèses
  dedans, comme un théorème.
- Exception : si une longue digression précède, garder les hypothèses dans la
  boîte même pour une définition.
- Ne jamais **répéter** une hypothèse : la poser une fois, à l'endroit qui
  couvre toutes ses conséquences.

## 2. Pas de blocs isolés ou enchaînés

- Au moins une phrase de liaison entre deux boîtes. Jamais deux ou trois boîtes
  collées.
- Une remarque qui ne fait qu'ajouter un alias de notation ou une précision
  mineure se **fond dans la boîte qui précède**, elle ne reste pas à part.

## 3. Amorce *motivée* avant chaque boîte

La phrase d'avant situe le résultat, dit à quoi il sert, ou annonce sa forme.
Éviter les formules passe-partout seules (« On a alors le théorème suivant. »).
Exemples : « La propriété suivante est fondamentale, elle permet de calculer de
nombreuses dérivées. » / « C'est la version adaptée à l'étude locale. »

## 4. Reprise *après* la boîte

Une phrase interprète ce qu'on vient d'obtenir et amène la suite. Pour
**proposition/théorème → corollaire**, dire *ce que la spécialisation apporte*
(« En prenant $E=\R^n$, on obtient la forme habituelle… »), jamais « On en
déduit le corollaire suivant. » seul.

## 5. Remarques : ne pas empiler

- Deux ou trois remarques consécutives → fusionner (éventuellement en `itemize`),
  passer en texte courant, ou promouvoir en sous-section.
- Une remarque qui n'est qu'une **convention de vocabulaire/notation** va dans le
  texte courant.
- La remarque est réservée aux vraies apartés : mise en garde, cas limite, lien
  avec un résultat ultérieur, contre-exemple ponctuel.

## 6. Remarque vs exemple

Une boîte qui instancie un résultat général sur un cas concret est un **exemple**,
pas une remarque. Amené lui aussi par une phrase, placée avant la boîte.

## 7. Décor de section (« cast list »)

Chaque section — souvent chaque sous-section — s'ouvre par un court paragraphe
qui (re)pose les objets courants avant la première boîte :

> Soient $(E,\|\cdot\|_E)$ et $(F,\|\cdot\|_F)$ deux e.v.n., $U$ un ouvert de
> $E$, $f\colon U\to F$ et $x\in U$.

Ne pas redéfinir dans le corps ce que fixe déjà la page **Notations**
(`frontmatter/notations.tex`).

## 8. Ne pas re-dériver un cas particulier

Si un second isomorphisme / une seconde formule n'est que la restriction d'un
résultat déjà écrit, y **renvoyer** plutôt que le réafficher.

## 9. Labels `\ref`-ables seulement si cités

Donner un label parlant (`thm:…`, `prop:…`, `def:…`, `exa:…`) **seulement si le
résultat est référencé ailleurs**. Sinon laisser `{}{}`. Vérifier au `grep` les
renvois réels avant d'ajouter un label.

## 10. Figures

Une figure est **annoncée et référencée dans le texte avant** d'apparaître.
Légende courte et descriptive. Placement `[ht!]` par défaut.

## 11. Cohérence terminologique et notationnelle

- Avant de trancher entre deux formulations (« sur $U$ » vs « dans $U$ »,
  « dérivable » vs « différentiable »…), vérifier au `grep` l'usage dominant
  dans **tout** le poly, puis aligner la minorité.
- Utiliser les **macros dédiées** plutôt que du LaTeX manuel : `\norm`, `\abs`,
  `\prodscal`, `\enstq{}{}`, `\grandO{}` / `\petito{}`, `\intervalleff{}{}`,
  `\dot{x}` (jamais `x'`) pour la dérivée en temps.
- `enumerate` / `itemize` plutôt que « 1) 2) 3) » ; `label=\roman*)` pour les
  points i), ii) d'un énoncé.

## 12. Typographie (checklist)

- `~:` — espace fine insécable avant les deux-points (idem `\ie~`, `\cf~`).
- Guillemets français `` ``…'' ``, pas `"`. Apostrophes U+2019 → U+0027 dans les
  sources.
- Première occurrence d'un terme défini : `\myemph{terme}` **et** `\index{…}`.
- Renvois capitalisés et insécables : `Théorème~\ref{…}`, `Proposition~\ref{…}`,
  `Figure~\ref{…}`, `Exercice~\ref{…}`, `Section~\ref{…}`.
- Preuves longues : séparer les étapes (`\newstep` / `\medskip`).

## Méthode

- **Forme uniquement** dans une passe d'harmonisation : amorces, transitions,
  placement des boîtes, typo, notations. Pas de contenu mathématique nouveau
  (autre passe).
- Travailler **par lots** (un fichier, ou un groupe de points).
- Après chaque édition : recompiler (`latexmk`), vérifier 0 référence indéfinie,
  puis commit — source lisible d'abord, PDF en fin de salve.
- Consigner chaque lot (« salve ») dans le fichier de suivi, avec les réfs de
  commit.
