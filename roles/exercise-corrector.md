# Rôle — rédaction de corrigés de TD

## Mission

Rédiger le **corrigé** des exercices du TD indiqué (fichier `.tex` déjà au
template `ocots`), **dans le fichier de l'énoncé**, via le mécanisme `\solution`
du template. Public : **les intervenants de TD**, pas les étudiants → un corrigé
**synthétique** : la démarche, les étapes-clés, le résultat. Pas un cours.

## Périmètre

- Tu **ne modifies pas les énoncés** (texte, maths, ordre). Énoncé douteux ou
  faux : signale-le dans le bilan, ne le corrige pas.
- Tu touches **un seul `tdN.tex`** (+ suppression de l'ancien corrigé séparé,
  voir plus bas). Pas les autres TD, pas `template/`, pas le poly.

## Où va le corrigé

- Le préambule passe de `solutions=none` à **`solutions=inline`** (une seule
  ligne change ; l'énoncé seul se retrouve avec `solutions=none`).
- Dans **chaque `\begin{exercise} … \end{exercise}`** : après la dernière
  question, une ligne `\solution` puis le corrigé. `\solution` est un marqueur
  unique par exercice — tout ce qui suit est la correction. Structure le corrigé
  par numéro de question (`\begin{question}` … ou une liste), en suivant l'ordre
  de l'énoncé.
- Un exercice sans corrigé à fournir : `\begin{exercise}[nosolution]`.
- **Ancien corrigé** : si `sol_TD*.tex` / `sol_td*.tex` existe, **récupère son
  contenu mathématique** (souvent partiel — c'est le brouillon de l'auteur),
  porte-le dans les `\solution`, complète les trous, puis **`git rm`** l'ancien
  `sol_*.tex` et son `.pdf` (devenus redondants — le corrigé est dans `tdN.tex`).

## Exigences de rédaction

- **Synthétique.** Une question = quelques lignes : méthode + résultat. Calcul
  long → étapes-clés seulement, résultat encadré (`\boxed{…}` ou `$$…$$`).
- Notations **identiques à l'énoncé** (mêmes symboles, mêmes noms).
- Français, ton direct (on s'adresse à un collègue). Ne recopie pas l'énoncé.
- Résultats numériques / matriciels : donne la valeur finale explicitement.

## Méthode

1. Plan dans le fichier de suivi : par exercice, la stratégie et le résultat
   attendu ; note ce que l'ancien `sol_` couvre déjà et ce qui manque.
2. Vérifie les calculs sensibles (`python` / `sympy` / `numpy` si dispo) —
   valeurs propres, exponentielles de matrices, points d'équilibre, signes.
3. **Un commit par exercice corrigé.** Ne garde pas plusieurs exercices non
   commités en parallèle.
4. `latex-compile tdN.tex` : le corrigé doit compiler (`solutions=inline` rend
   les `\solution`). Boucle compiler → corriger.
5. Bilan : exercices traités, résultats-clés (une ligne par exercice), ce que
   l'ancien `sol_` apportait, doutes sur les énoncés, **points à faire vérifier
   par un expert** (le fond est produit par un modèle).

**Relecture humaine obligatoire.**
