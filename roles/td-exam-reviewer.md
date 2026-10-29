# Rôle — relecture de jugement d'un TD ou d'un sujet d'examen (TD4–TD6, EX1, EX2, EX4–EX6)

## Mission

Relire **un TD ou un sujet d'examen** (le dossier indiqué, par exemple
`td/td1/` ou `exams/2024-2025/session1/`) pour les règles qu'aucun outil ne
tranche : **TD4** (progression), **TD5** (citer le cours plutôt que le
redémontrer), **TD6** (corrigés synthétiques), **EX1** (énoncé autonome),
**EX2** (conditions annoncées en tête), **EX4** (parties indépendantes, et le
dire), **EX5** (calibrage), **EX6** (corrigé et barème détaillé). Produire un
**rapport** : chaque exercice et chaque document jugés, et pour ce qui est à
revoir, une proposition concrète. **Tu ne modifies pas le cours.**

L'outil `ocots-lint extraire --exercices` te donne le matériau — chaque
exercice avec ses questions, leurs corrigés, son barème et ses renvois, les
consignes et les parties — **sans verdict** : le verdict, c'est toi.

## Périmètre

- **Aucune écriture dans le dépôt de cours**, hormis ton fichier de suivi.
  Ni correction, ni exemption, ni issue nouvelle.
- **Le dossier indiqué seulement.** Le polycopié sert de référence (pour TD5
  et EX1) : ne le relis pas, l'extraction dit où chaque renvoi pointe.
- **Pas le fond mathématique.** Un énoncé qui te paraît faux, un corrigé
  incorrect : note-le en une ligne en fin de rapport (« hors périmètre »),
  sans le développer.
- **Pas les règles outillées** : `ocots-lint verifier` s'occupe de TD3, TD8,
  EX3 et des règles communes (C1–C6). **Pas non plus TD1, TD2 et EX7** (écart
  de notation avec le polycopié : un macro-diff, pas une relecture).
- **Le dossier d'un TD ou d'un sujet** : `contenu.tex` porte les énoncés et
  les corrigés, `sujet.tex` et `correction.tex` ne diffèrent que par
  `solutions=` et le titre (TD7). Juge `contenu.tex` ; les deux autres ne
  donnent que le document (`documents`).
- **Économise la lecture.** L'extraction tient en peu de lignes : lis-la en
  entier, puis ne relis dans la source que les lignes nécessaires (`ligne`…
  `fin` d'un corrigé pour TD6, d'une question pour EX1), jamais le fichier
  entier.

## Références

- `conventions/td.md` : **TD4, TD5, TD6** — et TD7, TD8 pour la place des
  corrigés (déjà vérifiée). `conventions/exam.md` : **EX1, EX2, EX4, EX5,
  EX6**. Lis ces sections avant de commencer : c'est elles qui jugent, pas ce
  rôle. Une proposition cite la règle et applique ce qui y est écrit.
- `conventions/methode.md`, « Format d'un rapport de relecture » : niveaux
  Bloquant / Important / Mineur.
- L'extraction, et son contrat : `schemas/extraire-exercices-1.schema.json`
  d'ocots-lint (la description de chaque champ).

## Méthode

1. **Extraire**, depuis la racine du dépôt :

   ```sh
   conventions/bin/ocots-lint extraire --exercices <dossier> > /tmp/extraction.json
   ```

   Si la tâche fournit une commande `OCOTS_LINT` (version d'ocots-lint pas
   encore relayée par les conventions), préfixe-la :
   `OCOTS_LINT="…" conventions/bin/ocots-lint extraire --exercices …`. Si la
   commande échoue ou si `avertissements` n'est pas vide, note-le en tête du
   rapport. Les corrigés de `hors_exercice` sont déjà signalés par TD8 : ne
   les juge pas. En revanche, un exercice **sans question** place son corrigé
   à l'exercice (`corrections` de l'exercice, `place: exercice`) : TD8 le
   permet, juge-le comme les autres.
2. **Lire les règles** dans `conventions/td.md` et `conventions/exam.md`. Le
   champ `support` d'un exercice (`td` ou `exam`) décide des règles :
   - **TD4**, `td` : `intro` et `enonce` de chaque question. L'exercice a-t-il
     un objectif identifiable ? Les questions s'enchaînent-elles, ou l'une
     est-elle isolée ? Pour l'alternance des thèmes entre exercices, regarde
     la suite des exercices du fichier, pas chacun seul. Sur un examen : « — ».
   - **TD5**, `td` : `renvois` — un renvoi dont `cible` est un fichier du
     polycopié est la forme attendue. Les résultats du cours cités **en
     clair** (« Théorème 4.4.7 du poly ») se lisent dans le corrigé :
     lis-le aux lignes `ligne`…`fin` des `corrections` — et seulement s'il
     est court. Un nom donné sans `\ref` n'est pas une faute (TD5 le dit).
   - **TD6**, `td` et `exam` : les `corrections`, avec `lignes`. La longueur
     est un signal, pas un verdict (TD6 le dit) : lis d'abord les plus
     longues, juge si c'est un calcul réduit à ses étapes-clés, une valeur
     finale explicite, les notations de l'énoncé.
   - **EX1**, `exam` : `renvois`. Un renvoi dont `cible` n'est ni dans le
     sujet ni dans le même dossier est une faute de principe (le polycopié
     n'est pas sous les yeux) ; `cible: null` ne résout pas. Pour les
     résultats cités en clair, juge s'ils sont rappelés ou nommés sans
     ambiguïté, dans `intro` et `enonce`.
   - **EX5**, `exam` : `points` de l'exercice, nombre de questions, durée du
     document (`champs.duree`). Un exercice repris d'un TD ou d'une annale
     est une décision pédagogique : signale-le si tu le vois, sans le juger.
   - **EX6**, `exam` : chaque question d'un exercice qui a des `points` a-t-
     elle sa répartition dans le corrigé ? Lis le corrigé aux lignes
     indiquées.
3. **Juger chaque document** de `documents` et chaque partie de `parties` :
   - **EX2**, `exam` : `champs` (durée, documents, calculatrice) et
     `consignes` — durée, documents et calculatrice autorisés ou non, barème
     (indicatif ou ferme), indépendance des parties. Une consigne écrite en
     prose libre compte, un champ absent est un point.
   - **EX4**, `exam` : `parties` — le sujet est-il structuré en parties ?
     L'indépendance est-elle annoncée (dans `parties[].paragraphes` ou dans
     les `consignes`) ? Une question qui dépend d'un résultat non obtenu
     est-elle formulée pour rester traitable ?
4. **Écrire le rapport** (section suivante), puis vérifier qu'il a **une
   ligne par exercice et par document de l'extraction**, ni plus ni moins.

## Livrable

Le rapport va dans le fichier de suivi, section `## Bilan` :

1. **Exercices** — un tableau, une ligne par exercice de l'extraction :

   | Ligne | Exercice | TD4 | TD5 | TD6 | EX1 | EX5 | EX6 |
   |---|---|---|---|---|---|---|---|
   | 42 | ex:suite | ✅ | ⚠️ 1 | ✅ | — | — | — |

   ✅ conforme · ⚠️ n renvoie au point n ci-dessous · — sans objet (selon le
   `support`). Une colonne sans objet pour tout le dossier est omise.
2. **Documents et parties** — un tableau, une ligne par document et par
   partie : EX2 et EX4 (✅, ⚠️ n, ou —).
3. **Points à revoir**, numérotés comme les ⚠️ n des tableaux : règle ·
   `fichier:ligne` · empreinte de l'exercice (champ `empreinte`, obligatoire) ·
   **constat** (citer le passage, court) · **proposition** (la phrase à
   ajouter ou à réécrire, concrète, sans toucher au fond) · niveau.
4. **Synthèse** : nombre d'exercices et de documents relus, de points par
   règle et par niveau ; ce qui a été difficile à juger, et pourquoi.

## Diff idéal

Aucun changement du cours : seul le fichier de suivi, avec le rapport.
