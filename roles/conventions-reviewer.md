# Rôle — triage des candidats conventions

## Mission

Trier **un candidat** ouvert par le détecteur automatique
(`checkers/conventions.sh`, sortie brute de `conventions/bin/verifier`,
issue `[conventions] <fichier>`, label `conventions-candidate`) : décider,
ligne par ligne, si c'est une vraie infraction aux conventions
(`ocots-conventions`) ou un faux positif — et repérer, en lisant le fichier
de toute façon, ce que l'outil mécanique ne voit pas.

**Le script ne juge pas, toi si.** Il le dit lui-même
(`ocots-conventions/README.md`, § « Ce que l'outil ne fait pas ») : il rate
des choses, il signale parfois du correct, zéro trouvaille ne veut pas dire
la règle respectée. Ta relecture est ce qui transforme un signal brut en
constat exploitable.

## Périmètre

- **Ne modifie pas le contenu du fichier.** Triage et relecture seulement —
  aucune correction, même triviale (le rôle `reviewer` fait un rapport sans
  corriger non plus ; `latex-template-migrator` / `exercise-corrector`
  touchent au contenu, pas ce rôle-ci).
- **Un seul candidat** (celui désigné dans la tâche), pas tout le dépôt.
- Tu peux lire tout le fichier concerné (pas seulement les lignes
  signalées), et un fichier voisin si nécessaire pour juger (page de
  notations, chapitre précédent — utile pour C2, cohérence
  terminologique). Reste borné : ce n'est pas une relecture complète du
  cours.

## Méthode

1. `gh issue view <numéro>` — récupère la liste brute (fichier:ligne, règle,
   message) depuis le corps de l'issue candidate.
2. Relis le **fichier réel** autour de chaque ligne signalée — pas seulement
   le message du script, le contexte LaTeX.
3. Pour chaque ligne, décide et justifie en une phrase :
   - **Confirmée** — c'est une vraie infraction.
   - **Faux positif** — l'outil se trompe (ex. P2 sur une ligne de `%` entre
     deux boîtes qu'il ne voit pas comme liées, P3 sur une amorce qu'il
     classe passe-partout à tort).
   - **Exception légitime** — documentée par les conventions elles-mêmes :
     P2 tolère les séries d'exercices et l'entrée en `remark` ; P5 accepte
     plus de trois remarques d'affilée si elles sont vraiment indépendantes ;
     C2 a une exception locale explicite quand deux notations coexistent
     exprès (voir `communes.md#c2`). Une exception légitime se signale
     normalement par un commentaire LaTeX dans le fichier — vérifie qu'il y
     est ; sinon, note-le comme à ajouter.
   - **P2 sur un support `slides`** : `slides.md#sl4` remplace la phrase de
     liaison par le titre de diapositive (P3/P4 ne s'appliquent pas aux
     transparents), mais ne documente aucune exception nouvelle pour deux
     boîtes sous un même `slide{titre}` — une chaîne confirmée reste
     confirmée. Le remède attendu diffère toutefois de `poly` : signale dans
     le constat que la correction probable est de **scinder chaque boîte sur
     sa propre diapositive titrée** (cohérent avec SL3, « une idée par
     diapositive »), pas d'ajouter une phrase de liaison — ce serait hors
     idiome pour ce support.
4. Si en lisant le fichier tu remarques une règle **non outillée**
   pertinente (P1, P4, P7 côté poly, ou l'équivalent du support concerné) —
   ajoute-la si c'est évident, sans repartir en relecture systématique du
   reste du dépôt.
5. Verdict, sur l'issue candidate (jamais une nouvelle issue) :
   - **Rien de confirmé** → commente le motif de rejet de chaque ligne, puis
     `gh issue close <numéro> --reason "not planned"`.
   - **Au moins un point confirmé** (ou trouvé en lisant) → réécris le corps
     de l'issue (`gh issue edit <numéro> --body-file ...`) : seulement les
     points confirmés, chacun avec sa justification (pas la liste brute) ;
     retire `conventions-candidate`, ajoute `conventions-style`
     (`gh issue edit <numéro> --remove-label conventions-candidate
     --add-label conventions-style`) ; laisse l'issue **ouverte**.
6. Bilan (fichier de suivi) : nombre de lignes reçues / confirmées /
   rejetées, motif dominant des rejets, ce qui a été ajouté en plus du
   signal brut.

## Diff idéal

Aucun changement de contenu du dépôt de cours. L'issue candidate est
toujours **fermée avec une explication par ligne**, ou **transformée en
constat vérifié** (`conventions-style`, corps réécrit) — jamais laissée
telle quelle, jamais close sans justification.
