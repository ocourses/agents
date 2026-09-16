# Protocole — traiter des tickets de la file en local (sans GitHub Actions)

Remplace, pour **un ticket à la fois**, le duo `queue.yml` (dispatch) +
`agent.yml` (scaffold → OpenCode/Albert → bilan) par une session Claude Code
qui fait le travail elle-même. Même sélection, même chantier (issue, branche,
PR Draft, fichier de suivi), même critère de succès, même protocole de
réclamation — seul le **moteur** change : toi, au lieu d'OpenCode/Albert.
Détail des pièces réutilisées : voir README.md, § « File d'attente » et
§ « Coordination avec un travail manuel ».

**Jamais les deux chemins sur le même ticket.** Ce protocole est une
alternative à `queue.yml`, pas un complément — une issue traitée ici ne doit
pas aussi être dispatchée par la file automatisée (le protocole de
réclamation, étape 2 ci-dessous, empêche justement cette collision).

## Invocation

> Suis `LOCAL-QUEUE.md`, fais 1 tick.

Le nombre de tickets est le seul paramètre ; **défaut : 1** si non précisé —
voir « Enchaîner plusieurs tickets » plus bas pour pourquoi.

## Prérequis

- Un clone à jour de `ocourses/agents` (ce dépôt), `gh` déjà authentifié avec
  un jeton portant, sur chaque dépôt de `config/course-repos.txt` **et** sur
  `ocourses/agents` lui-même : `Issues` (lire/écrire), `Contents`
  (lire/écrire), `Pull requests` (écrire), `Metadata` (lire) — mêmes portées
  que `AGENTS_DISPATCH_TOKEN` (README, § « Mise en place »), plus l'écriture
  de contenu qu'un run GitHub Actions obtient autrement via son propre
  checkout.
- Accès en clone/push aux dépôts de `config/course-repos.txt` (le tien, pas
  besoin d'un `AGENTS_READ_TOKEN` séparé : tu n'as pas de sous-module privé à
  checkouter à distance comme `agent.yml`, tu cloneras le dépôt cible toi-même
  s'il ne l'est pas déjà).

## Un tick

Toutes les commandes `scripts/*.sh` ci-dessous sont dans `ocourses/agents` ;
`<agents>` désigne le chemin de ce clone.

1. **Sélectionner** :
   ```bash
   result="$(bash <agents>/scripts/lib/next-task.sh)"
   ```
   Sortie JSON — `eligible_count`, et si `> 0` : `repo`, `kind`, `number`,
   `target`, `role`, `task_title`, `task`. **`eligible_count: 0` → arrête-toi
   ici, dis-le, n'invente pas de tâche.** C'est le même sélecteur que
   `queue-next.sh` (extrait dans `scripts/lib/next-task.sh` précisément pour
   qu'aucun des deux chemins ne choisisse une tâche différente).

2. **Réclamer**, avant tout travail :
   ```bash
   bash <agents>/scripts/claim-issue.sh claim <repo> <number> "Claude Code local (<ton nom>)"
   ```
   Échec (déjà réclamée) → arrête-toi, ne recommence pas automatiquement sur
   une autre tâche sans qu'on te le demande.

3. **Chantier**, dans un clone de `<repo>` (le cloner s'il ne l'est pas déjà) :
   ```bash
   cd <clone-de-repo>
   export GITHUB_OUTPUT="$(mktemp)"
   ROLE="<role>" \
   TASK="<task>" \
   TITLE="<task_title>" \
   LINK_ISSUE="<number>" \
   RUN_ID="local-$(date -u +%Y%m%dT%H%M%SZ)" \
   MODEL="claude-code-local" \
   REPO="<repo>" \
   bash <agents>/scripts/scaffold.sh
   grep -E '^(issue|pr|branch|tracking|base_branch)=' "$GITHUB_OUTPUT"
   ```
   Identique à ce que fait `agent.yml` avant de lancer OpenCode : ouvre (ou
   réutilise, via `LINK_ISSUE`) l'issue, crée la branche `agent/<slug>-<RUN_ID>`,
   le fichier de suivi `.agents/runs/<slug>-<RUN_ID>.md`, la PR Draft. Note
   `pr`, `branch`, `tracking` — nécessaires aux étapes suivantes. `MODEL`
   n'est pas un identifiant Albert : garde `claude-code-local` (ou équivalent)
   pour que le fichier de suivi distingue au premier coup d'œil un run local
   d'un run automatisé.

   Identité git : `scaffold.sh` committe sous `ocourses-agent`, comme un run
   automatisé — voulu (même décorum, même trace), la distinction se lit dans
   le commentaire de réclamation de l'étape 2 et le champ `MODEL` ci-dessus,
   pas dans l'auteur des commits.

4. **Réaliser le travail toi-même**, en suivant scrupuleusement
   `<agents>/roles/<role>.md` — c'est TOI le moteur, pas OpenCode/Albert.
   Comme le ferait OpenCode (cf. `run-opencode.sh`) : tiens le fichier de
   suivi (`tracking`) à jour au fil de l'eau — Plan, Journal, et surtout
   **Bilan** avant l'étape 6 (`finalize.sh` le poste tel quel en commentaire
   de PR) — et commite au fur et à mesure, jamais tout à la fin. Ne pousse
   **jamais** sur autre chose que `branch`.

5. **Vérifier le succès**, même critère que `queue-next.sh` (README, tableau
   § « File d'attente ») :
   | `kind` | Critère |
   |---|---|
   | `migration` | PR ouverte **et** `bash <agents>/scripts/lib/rescan-migration.sh <repo> <branch> <target>` renvoie `CLEAN` |
   | `fix` | PR ouverte (`gh pr view <pr> --repo <repo> --json state` → `OPEN`) |
   | `conventions` | l'issue `<number>` n'est plus `conventions-candidate` (fermée, ou promue `conventions-style` par ton propre travail à l'étape 4) |

   Pour `migration`, un statut autre que `CLEAN` (ou une revérification
   impossible) est un **échec**, même si une PR existe — ne conclus jamais au
   succès sur la seule existence d'une PR pour ce `kind` (c'est précisément ce
   que corrige `rescan-migration.sh`, ocourses/agents#15).

6. **Clôturer** :
   ```bash
   REPO="<repo>" PR="<pr>" BRANCH="<branch>" TRACKING="<tracking>" \
   OUTCOME="success" \
   bash <agents>/scripts/finalize.sh
   ```
   (`OUTCOME=failure` si l'étape 5 a échoué mais que tu laisses un état
   partiel poussé — voir « Comportement en échec » ci-dessous.)

7. **Libérer la réclamation** :
   - Succès (`migration`/`fix`) → commente + ferme l'issue toi-même comme le
     fait `queue-next.sh` (`gh issue comment`, `gh issue close --reason completed`),
     puis `bash <agents>/scripts/claim-issue.sh release <repo> <number>`.
   - Succès (`conventions`) → l'issue a déjà été traitée à l'étape 4 (fermée
     ou promue par toi-même, jamais par ce protocole) ; seulement
     `claim-issue.sh release <repo> <number>`.
   - Échec, quelle qu'en soit la nature → `bash <agents>/scripts/claim-issue.sh fail <repo> <number> "<raison précise>"`.
   - **Ne laisse jamais l'issue réclamée sans `release` ni `fail`** — même
     règle que le modèle déjà documenté dans le README (§ « Coordination avec
     un travail manuel »).

8. **Rapporte** un résumé court : `<repo>#<number>` · rôle · résultat · lien
   PR le cas échéant.

## Enchaîner plusieurs tickets

Le nombre de tickets est un paramètre de l'invocation, pas une valeur fixée
ici. **Sauf instruction explicite, traite un seul tick puis rends la main**
avec le résumé de l'étape 8. La file automatisée peut s'enchaîner sans
supervision (headless, verrou global, "vigie main" post-run dans `agent.yml`
qui détecte un push direct sur la branche par défaut) ; une session locale
interactive n'a pas ce filet, et une migration prend couramment ~40 min :
un point d'arrêt entre deux tickets permet de rediriger avant d'enchaîner.

Si on te demande explicitement N tickets : répète les étapes 1 à 8, N fois,
en t'arrêtant **immédiatement** si l'étape 1 renvoie `eligible_count: 0` —
jamais de tâche inventée pour atteindre N.

## Comportement en échec

Même règle que la file automatisée (README, § « Comportement en échec ») :
un échec n'est **pas retenté automatiquement**. `claim-issue.sh fail` pose le
label `agent:failed` et un commentaire — retirer le label remet le ticket en
jeu (pour toi ou pour `queue.yml`, indifféremment).

## Ce que ce protocole ne remplace pas

- Il ne dispatche jamais vers `agent-migrate-latex.yml` /
  `agent-review-conventions.yml` / `agent-fix-conventions.yml` : ces
  workflows restent le chemin automatisé (Albert). Ce protocole est une
  alternative pour le **même** travail sur un ticket **donné**, jamais les
  deux en parallèle dessus.
- Le verrou global GitHub Actions (`agent-albert-global`) ne protège pas ce
  chemin : seul `claim-issue.sh` coordonne les deux. Vérifier avant de
  réclamer (étape 2) n'est pas négociable.
