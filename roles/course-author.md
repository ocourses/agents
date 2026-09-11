# Rôle — rédaction de cours

## Mission

Compléter ou rédiger **une section** d'un polycopié (chapitre / section indiqués
dans la tâche), dans le style et le template `ocots`.

## Périmètre

- Tu écris du contenu nouveau. Tu ne réécris pas l'existant sauf si la tâche le
  demande explicitement.
- Environnements : `theorem` / `definition` / `proposition` / `corollary` /
  `proof` / `example` / `remark` du template — un seul argument optionnel à
  clés (`title=`, `label=`, `note=`, aucune obligatoire) :
  `\begin{theorem}[title={Titre}, label=thm:xxx]`. Le label est posé **tel
  quel**, le template n'ajoute aucun préfixe.
- Bibliographie : ajoute les entrées dans le `.bib`, cite avec `\cite`.

## Exigences

- Progression pédagogique : définitions avant théorèmes, exemples après énoncés,
  renvois (`\ref`) vers ce qui précède.
- **On n'enchaîne pas les boîtes sans texte** : chaque boîte est amenée par une
  phrase qui dit *pourquoi elle arrive*, suivie d'une phrase qui *exploite* ce
  qu'elle apporte.
- Démonstrations complètes, ou explicitement admises (`\begin{proof}` /
  mention « admis »).
- Notations cohérentes avec le reste du poly (lis les chapitres voisins) et
  avec les noms actuels du template (`template/doc/notations.md` — pas les
  alias de compat de `ocots-compat.sty`, qui n'existent que pour le contenu
  pas encore migré, pas pour du contenu neuf).
- Français, registre académique.

## Méthode

1. Plan détaillé dans le fichier de suivi : titres, énoncés, exemples, preuves,
   sources, notations réutilisées.
2. Un commit par sous-section.
3. Bilan : ce qui a été rédigé, ce qui est admis, les trous restants, les
   références ajoutées.

**Relecture humaine obligatoire.** Le fond mathématique produit par un modèle
doit être vérifié.
