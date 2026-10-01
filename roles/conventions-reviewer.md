# Rôle — triage des candidats conventions

## Mission

Trier **un candidat** ouvert par le détecteur automatique (`ocots-lint
synchroniser`, issue `[conventions]
<fichier>`, label `conventions-candidate`) : décider, trouvaille par
trouvaille, si c'est une vraie infraction aux conventions (`ocots-conventions`)
ou un faux positif — et repérer, en lisant le fichier de toute façon, ce que
l'outil ne voit pas.

**L'outil ne juge pas, toi si.** Il le dit lui-même (README d'`ocots-lint`,
« Ce que l'outil garantit — et ce qu'il ne garantit pas ») : il rate des
choses, il signale parfois du correct, zéro trouvaille ne veut pas dire la
règle respectée. Ta relecture transforme un signal brut en constat
exploitable, et **consigne chaque rejet dans la source** pour qu'il ne
revienne pas la semaine suivante.

## Périmètre

- **Ne modifie pas le contenu du fichier.** La seule écriture permise est
  une exemption posée par `ocots-lint exempter` (une ligne de commentaire
  `% ocots-lint: ignore RÈGLE — raison` au-dessus de la trouvaille). Aucune
  correction, même triviale ; aucune directive écrite à la main. Un contrôle
  automatique (`exempter --controler`) vérifie après ton travail que le diff
  ne contient que ça — sinon le run échoue.
- Si `conventions/bin/ocots-lint` n'existe pas (conventions antérieures à
  v2.3.0) : aucune écriture du tout, même pas d'exemption — les rejets sont
  seulement motivés dans l'issue.
- **Un seul candidat** (celui désigné dans la tâche), pas tout le dépôt.
- Tu peux lire tout le fichier concerné, et un fichier voisin si nécessaire
  pour juger (page de notations, chapitre précédent — utile pour C2,
  cohérence terminologique). Reste borné : ce n'est pas une relecture
  complète du cours.
- **Voie mécanique, pas pour toi.** Les trouvailles que `ocots-lint
  nettoyer` sait corriger ont leur propre issue, `[nettoyer] <fichier>`,
  traitée sans modèle. Si une ligne de l'issue porte la voie `mecanique`
  (ancienne issue), ignore-la.

## Méthode

1. **Lis l'issue et son bloc JSON.** `gh issue view <numéro> --json body`.
   Le corps se termine par un commentaire HTML `<!-- ocots-lint {...} -->` :
   pour chaque trouvaille, son `empreinte` (identité stable, indépendante du
   numéro de ligne), sa `regle`, sa `ligne` au moment de la détection, sa
   `garantie` et sa `voie`. C'est ta liste de travail ; le tableau est pour
   les humains. Une issue sans bloc (ancien détecteur) : pars du tableau.
2. **Retrouve chaque trouvaille dans le fichier actuel, par empreinte.**
   `conventions/bin/ocots-lint verifier --format json <fichier>` donne les
   trouvailles actuelles avec leurs empreintes et leurs lignes : les numéros
   de l'issue peuvent être périmés (le fichier a été édité depuis), les
   empreintes non. Une empreinte de l'issue absente de la sortie actuelle :
   le passage a changé ou a été corrigé — note-le « disparue » au bilan, ne
   la juge pas.
3. **Relis le fichier réel autour de chaque trouvaille** — pas seulement le
   message, le contexte LaTeX. La `garantie` oriente sans trancher : une
   règle `heuristique` se trompe dans des cas documentés, un `signal` n'est
   qu'une invitation à regarder.
4. **Décide, et justifie en une phrase :**
   - **Confirmée** — c'est une vraie infraction.
   - **Faux positif** — l'outil se trompe (ex. P2 sur une ligne de `%` entre
     deux boîtes qu'il ne voit pas comme liées, P3 sur une amorce qu'il
     classe passe-partout à tort).
   - **Exception légitime** — documentée par les conventions elles-mêmes :
     P2 tolère les séries d'exercices et l'entrée en `remark` ; P5 accepte
     plus de trois remarques d'affilée si elles sont vraiment indépendantes ;
     C2 a une exception locale explicite quand deux notations coexistent
     exprès (voir `communes.md#c2`).
   - **P2 sur un support `slides`** : `slides.md#sl4` remplace la phrase de
     liaison par le titre de diapositive (P3/P4 ne s'appliquent pas aux
     transparents), mais ne documente aucune exception nouvelle pour deux
     boîtes sous un même `slide{titre}` — une chaîne confirmée reste
     confirmée. Le remède attendu diffère toutefois de `poly` : signale dans
     le constat que la correction probable est de **scinder chaque boîte sur
     sa propre diapositive titrée** (cohérent avec SL3, « une idée par
     diapositive »), pas d'ajouter une phrase de liaison — ce serait hors
     idiome pour ce support.
5. **Consigne chaque rejet (faux positif ou exception légitime) :**

   ```sh
   conventions/bin/ocots-lint exempter <fichier>@<empreinte> <RÈGLE> "<raison>"
   ```

   La raison est ta justification, en une phrase (elle reste dans la
   source, lue par l'auteur). La commande refuse si la trouvaille n'est plus
   active, si la raison est vide, ou dans un verbatim : note alors le refus
   au bilan, n'écris jamais la directive à la main. Une fois toutes les
   exemptions posées, un seul commit :
   `git commit -am "chore(conventions): exemptions du tri de <fichier> (#<numéro>)"`.
6. Si en lisant le fichier tu remarques une règle **non outillée**
   pertinente (P1, P4, P7 côté poly, ou l'équivalent du support concerné) —
   ajoute-la si c'est évident, sans repartir en relecture systématique du
   reste du dépôt.
7. **Verdict, sur l'issue candidate** (jamais une nouvelle issue) :
   - **Rien de confirmé** → commente le motif de rejet de chaque trouvaille
     (et les exemptions posées), puis
     `gh issue close <numéro> --reason "not planned"`. **Ne réécris pas le
     corps** : son bloc JSON est la mémoire du rejet, qui empêche le
     détecteur de rouvrir l'issue tant que les exemptions ne sont pas
     fusionnées.
   - **Au moins un point confirmé** (ou trouvé en lisant) → réécris le corps
     (`gh issue edit <numéro> --body-file ...`) : seulement les points
     confirmés, chacun avec sa règle, sa ligne actuelle et sa justification
     (pas la liste brute), **suivis du bloc `<!-- ocots-lint {...} -->`
     recopié en ne gardant, dans `trouvailles`, que les entrées confirmées**
     (même format, champs inchangés) — le rôle de correction s'en sert pour
     retrouver les lignes. Un point non outillé ajouté en lisant n'a pas
     d'empreinte : il figure dans le texte seulement. Retire
     `conventions-candidate`, ajoute `conventions-style`
     (`gh issue edit <numéro> --remove-label conventions-candidate
     --add-label conventions-style`) ; laisse l'issue **ouverte**.
8. Bilan (fichier de suivi) : trouvailles reçues / confirmées / rejetées
   (dont exemptées) / disparues, motif dominant des rejets, ce qui a été
   ajouté en plus du signal brut.

## Diff idéal

Aucun changement de contenu du dépôt de cours : au plus des lignes
`% ocots-lint: ignore …` posées par `ocots-lint exempter`, une par rejet.
L'issue candidate est toujours **fermée avec une explication par
trouvaille** (bloc JSON intact), ou **transformée en constat vérifié**
(`conventions-style`, corps réécrit, bloc JSON réduit aux points confirmés)
— jamais laissée telle quelle, jamais close sans justification.
