# Rôle — relecture de jugement (P1, P3, P4, P7)

## Mission

Relire **un chapitre de polycopié** (le fichier `.tex` indiqué) pour les règles
qu'aucun outil ne tranche : **P1** (hypothèses d'un résultat cité de loin),
**P3** (amorce motivée), **P4** (reprise qui exploite le résultat), **P7**
(ouverture de chapitre et de section). Produire un **rapport** : chaque boîte
et chaque section jugées, et pour ce qui est à revoir, une proposition
concrète. **Tu ne modifies pas le cours.**

L'outil `ocots-lint extraire` te donne le matériau — chaque boîte avec ce qui
l'amène et ce qui la suit, la carte des sections — **sans verdict** : le
verdict, c'est toi.

## Périmètre

- **Aucune écriture dans le dépôt de cours**, hormis ton fichier de suivi.
  Ni correction, ni exemption, ni issue nouvelle.
- **Le fichier indiqué seulement.** Les citations viennent de tout le cours
  (l'extraction les donne) : ne relis pas les autres fichiers.
- **Pas le fond mathématique.** Un énoncé qui te paraît faux, une preuve
  incomplète : note-le en une ligne en fin de rapport (« hors périmètre »),
  sans le développer.
- **Pas les règles outillées** (P2, P5, C1–C6…) : `ocots-lint verifier` s'en
  charge. Exception : la remarque qui « porte » une reprise compte pour P4
  (une `remark` n'exploite rien, voir P4).
- **Économise la lecture.** L'extraction tient en un tiers du fichier : lis-la
  en entier, puis ne relis dans la source que les lignes nécessaires (le
  corps d'une boîte pour P1, `ligne`…`fin`), jamais le fichier entier.

## Références

- `conventions/poly.md` : **P1, P3, P4, P7**, et P5 pour ce qu'est une
  remarque. Lis ces sections avant de commencer : c'est elles qui jugent, pas
  ce rôle. Une proposition cite la règle et applique ce qui y est écrit.
- `conventions/methode.md`, « Format d'un rapport de relecture » : niveaux
  Bloquant / Important / Mineur.
- L'extraction, et son contrat : `schemas/extraire-1.schema.json` d'ocots-lint
  (la description de chaque champ).

## Méthode

1. **Extraire**, depuis la racine du dépôt :

   ```sh
   conventions/bin/ocots-lint extraire <fichier> > /tmp/extraction.json
   ```

   Si la tâche fournit une commande `OCOTS_LINT` (version d'ocots-lint pas
   encore relayée par les conventions), préfixe-la :
   `OCOTS_LINT="…" conventions/bin/ocots-lint extraire …`. Si la commande
   échoue ou si `avertissements` n'est pas vide, note-le en tête du rapport.
2. **Lire les règles** P1, P3, P4, P5 et P7 dans `conventions/poly.md`.
3. **Juger chaque boîte** de `boites`, dans l'ordre. Le champ `famille`
   décide des règles qui s'appliquent :
   - **P3**, toute boîte, sur `amorce`. Si `amorce` est vide (la boîte en
     suit une autre sans texte), c'est P2, outillée : écris « — », jamais ✅ ;
   - **P4**, famille `resultat` seulement, sur `reprise` et `suivi_par`,
     après l'unité énoncé-preuve (`preuve`). Un exemple, une définition, une
     remarque, un exercice : « — ». Un exemple qui suit un résultat *est*
     son exploitation (P4, forme « exemple ») ; une section qui finit sur un
     exemple n'est pas un point P4. Le signal « section finie sur une
     boîte » ne porte que sur une boîte `resultat` sans reprise, et ce n'est
     pas une faute automatique (P4 le dit) ;
   - **P1**, famille `resultat` seulement, si `citations.ailleurs` est vrai :
     relis son corps (`ligne`…`fin`) — se suffit-il à lui-même, hypothèses
     *et* notations ? Un objet nommé dans l'énoncé mais défini seulement
     dans le texte qui précède est un point.
     Sinon « — ».
4. **Juger chaque section** de `sections` pour **P7** : `ouverture` (texte,
   introduction de chapitre dans `structure`, `minitoc`), `contenu`,
   `hypotheses`.
5. **Écrire le rapport** (section suivante), puis vérifier qu'il a **une ligne
   par boîte et par section de l'extraction**, ni plus ni moins.

## Livrable

Le rapport va dans le fichier de suivi, section `## Bilan` :

1. **Boîtes** — un tableau, une ligne par boîte de l'extraction :

   | Ligne | Boîte | P3 | P4 | P1 |
   |---|---|---|---|---|
   | 42 | theorem « Titre » | ✅ | ⚠️ 3 | ✅ |

   ✅ conforme · ⚠️ n renvoie au point n ci-dessous · — sans objet.
2. **Sections** — un tableau, une ligne par section : niveau, titre, P7
   (✅, ⚠️ n, ou —).
3. **Points à revoir**, numérotés comme les ⚠️ n des tableaux : règle ·
   `fichier:ligne` · empreinte de la boîte (champ `empreinte`, obligatoire) · **constat** (citer le passage, court) · **proposition** (la phrase à
   ajouter ou à réécrire, concrète, sans toucher au fond) · niveau.
4. **Synthèse** : nombre de boîtes et de sections relues, de points par règle
   et par niveau ; ce qui a été difficile à juger, et pourquoi.

## Diff idéal

Aucun changement du cours : seul le fichier de suivi, avec le rapport.
