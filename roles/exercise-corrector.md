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

## S'appuyer sur le cours (obligatoire)

Le corrigé doit être **cohérent avec le cours**, pas une solution parachutée.
Avant de rédiger :

- Lis les chapitres du poly concernés (`poly/introduction.tex`,
  `poly/stabilite.tex`, `poly/commande.tex`) et les transparents
  (`slides/slides_chapitre_*.tex`). Repère le **vocabulaire**, les **notations**
  (p. ex. matrice de contrôlabilité, exponentielle de matrice, point de
  fonctionnement), les **théorèmes** et **méthodes** tels qu'ils y sont posés.
- Le corrigé **réutilise ces notations et ces résultats** : cite le théorème du
  cours utilisé (« critère de Kalman », « stabilité par linéarisation »,
  « théorème de Cauchy-Lipschitz »…) plutôt que de tout redémontrer. Renvoie au
  besoin au chapitre (`\ref{chap:...}` s'il porte un label).
- Si l'exercice attend une méthode vue en cours (exponentielle de matrice vs
  diagonalisation, Routh vs valeurs propres…), suis **celle du cours**.
- Divergence énoncé / cours (notation, hypothèse) : signale-la dans le bilan.

## Où va le corrigé

- Le préambule passe de `solutions=none` à **`solutions=inline`** (une seule
  ligne change ; l'énoncé seul se retrouve avec `solutions=none`).
- Dans **chaque `\begin{exercise} … \end{exercise}`** : après la dernière
  question, une ligne `\solution` puis le corrigé. `\solution` est un marqueur
  unique par exercice — tout ce qui suit est la correction.
- **Ne rouvre pas `\begin{question}` dans le `\solution`** : le compteur
  `question` continue celui de l'énoncé (le corrigé de la Q1 s'afficherait
  « 4 »). Structure le corrigé avec une **liste manuelle** qui reprend les
  numéros de l'énoncé, p. ex.
  `\begin{description}\item[1.] … \item[2.] …\end{description}`
  (et `\item[a.]`, `\item[b.]` pour les sous-questions). Un renvoi ponctuel à
  une question de l'énoncé : `\ref{…}` si elle porte un label, sinon cite le
  numéro en clair.
- Un exercice sans corrigé à fournir : `\begin{exercise}[nosolution]`.
- **Ancien corrigé** : si `sol_TD*.tex` / `sol_td*.tex` existe, **récupère son
  contenu mathématique** (souvent partiel — c'est le brouillon de l'auteur),
  porte-le dans les `\solution`, complète les trous, puis **`git rm`** l'ancien
  `sol_*.tex` et son `.pdf` (devenus redondants — le corrigé est dans `tdN.tex`).
  **Exception** : si tu n'as pas pu récupérer le contenu de l'ancien corrigé
  (PDF image, pas de source, illisible…), **ne le supprime pas** — laisse-le
  comme référence pour la relecture, et dis-le dans le bilan.

## Exigences de rédaction

- **Synthétique.** Une question = quelques lignes : méthode + résultat. Calcul
  long → étapes-clés seulement, résultat encadré (`\boxed{…}` ou `$$…$$`).
- Notations **identiques à l'énoncé** (mêmes symboles, mêmes noms).
- Français, ton direct (on s'adresse à un collègue). Ne recopie pas l'énoncé.
- Résultats numériques / matriciels : donne la valeur finale explicitement.

## Méthode

1. Lis d'abord les chapitres du poly et les transparents concernés (section
   « S'appuyer sur le cours »). Plan dans le fichier de suivi : par exercice, la
   stratégie, le **résultat du cours mobilisé** et le résultat attendu ; note ce
   que l'ancien `sol_` couvre déjà et ce qui manque.
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
