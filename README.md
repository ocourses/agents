# `ocourses/agents` — base d'agents IA pour les cours

Workflow GitHub Actions réutilisable qui fait travailler un agent IA sur un
dépôt de cours, **sans jamais perdre son travail** : chaque run laisse une
trace complète (issue, branche, fichier de suivi, commits, PR Draft,
commentaire de bilan).

- **Mécanique figée** — l'orchestration (issue → branche → suivi → commit
  *dummy* → PR Draft → travail → bilan) est en **scripts** (`bash` + `gh`),
  déterministe.
- **Liberté** — le travail lui-même est fait par **[OpenCode](https://opencode.ai)**
  (le moteur), modèle **Albert** (`deepseek-v4-flash`), avec tous ses outils.
- **Générique** — un rôle = un fichier Markdown, réutilisable pour n'importe
  quelle tâche (migration LaTeX, corrigés, rédaction, relecture…).

Voir [`ARCHITECTURE.md`](ARCHITECTURE.md) pour le détail et l'historique des
décisions.

## Les deux parcours, de bout en bout

Vue d'ensemble avant le détail de chaque pièce (sections suivantes). Deux
pipelines partagent la même colonne vertébrale — détection gratuite → file
d'attente → agent Albert → verrou global — mais divergent sur ce que l'agent
fait vraiment.

### Migration

```
1. check.yml (cron ou manuel) → checkers/template-migration.sh — gratuit
   · classe chaque pilote .tex : MISSING / LEGACY / conforme
   → ouvre une issue "[migration] <fichier>", label template-migration

2. queue.yml (cron, verrou agent-albert-global) → queue-next.sh
   · prend la plus ancienne issue template-migration, tous dépôts confondus
   · gh workflow run agent-migrate-latex.yml -f target=<fichier> -f issue=<#1>
   · attend la fin (tient le verrou pendant tout le run)

3. agent-migrate-latex.yml → agent.yml (role: latex-template-migrator)
   · scaffold.sh : nouvelle issue "[agent] Migration <fichier>", branche,
     PR Draft "Closes #<cette issue>" ET "Closes #1" (link_issue = l'issue
     de détection d'origine, transmise depuis queue-next.sh — lien GitHub
     natif, visible dans le panneau Development de #1)
   · run-opencode.sh : OpenCode + Albert migre, compile, commite
   · finalize.sh : bilan en commentaire de PR, reste en Draft

4. queue-next.sh reprend la main
   · PR trouvée ET branche re-scannée propre → ferme l'issue de détection
     (#1), succès — indépendamment du lien natif ci-dessus, qui ne referme
     #1 qu'à la fusion (souvent bien après, une fois la Draft relue).
     Le re-scan = scripts/lib/template-scan.sh (le même composant que le
     détecteur) sur la branche de la PR : plus aucun nom de
     ocots-compat.sty dans la chaîne \input du pilote. Un diff vide ou
     incomplet n'est donc plus un succès (ocourses/agents#15).
   · sinon → label agent:failed sur l'issue de détection, pas de retentative

5. Relecture humaine de la PR Draft (latex-pr.yml compile dès "Ready for
   review"), merge quand ça va.
```

### Conventions

Même colonne vertébrale, mais **le script ne décide jamais** — il ouvre un
candidat, un agent tranche.

```
1. check.yml → checkers/conventions.sh — gratuit, enveloppe
   conventions/bin/verifier
   → ouvre/actualise un candidat "[conventions] <fichier>",
     label conventions-candidate, corps marqué "⚠️ candidat brut, pas relu"
   · plus aucune trouvaille brute au run suivant → ferme le candidat seul

2. queue.yml — MÊME file, MÊME verrou que la migration
   · fusionne migration + conventions, prend le plus ancien des deux
     toutes catégories confondues
   · gh workflow run agent-review-conventions.yml
       -f target=<fichier> -f issue=<numéro du candidat>

3. agent-review-conventions.yml → agent.yml (role: conventions-reviewer)
   · relit le FICHIER RÉEL autour de chaque ligne signalée par verifier
   · juge : confirmée / faux positif / exception légitime (P2 tolère les
     séries d'exercices, P5 accepte des remarques groupées légitimes…)
   · modifie l'issue candidate elle-même — jamais le contenu du cours :
     - rien de confirmé → ferme avec le motif de chaque rejet
     - au moins un point confirmé → réécrit le corps (juste les points
       retenus), swap le label conventions-candidate → conventions-style,
       laisse ouverte

4. queue-next.sh reprend la main
   · état de l'issue candidate changé (fermée ou promue) → succès
   · toujours conventions-candidate → agent:failed, pas de retentative

5. queue.yml reprend une issue conventions-style (verdict confirmé) — MÊME
   file, MÊME verrou, aucun cron séparé
   · gh workflow run agent-fix-conventions.yml
       -f target=<fichier> -f issue=<numéro de l'issue conventions-style>

6. agent-fix-conventions.yml → agent.yml (role: conventions-fixer)
   · relit l'issue conventions-style (verdicts déjà rendus, pas la sortie
     brute) et le remède documenté par ocots-conventions pour chaque règle
   · corrige UNIQUEMENT les points confirmés · un choix d'auteur non
     tranchable (ex. C2 entre deux formes réellement équivalentes) → laissé
     en l'état, signalé dans le bilan, pas décidé à sa place
   · PR Draft, liée nativement à l'issue conventions-style (link_issue)

7. queue-next.sh reprend la main — même mécanique que la migration : PR
   trouvée → ferme l'issue conventions-style, succès ; sinon → agent:failed.
   Relecture humaine de la PR avant fusion, comme toujours.
```

### Ce qui distingue vraiment les deux

| | Migration | Conventions |
|---|---|---|
| Le script seul peut-il conclure ? | Oui — macro `my*` présente ou non, fait binaire | Non, jamais — d'où le passage obligé par l'agent |
| L'agent modifie… | le contenu du cours | seulement l'issue (jamais le contenu) |
| Critère de succès de la file | une PR est ouverte **et** le re-scan de sa branche est propre | l'issue candidate a changé d'état |
| Résultat pour l'humain | une PR Draft à relire | une issue triée (fermée ou confirmée) à traiter |

## Séquence d'un run

1. `scaffold.sh` — issue (assignée `ocots`, label `agent`), branche
   `agent/<slug>-<run_id>`, fichier de suivi `.agents/runs/<slug>-<run_id>.md`
   (commit *dummy*), PR **Draft** (assignée `ocots`, « Closes #issue »).
2. `run-opencode.sh` — assemble `AGENTS.md` (socle + rôle + contexte) et
   `opencode.json`, lance `opencode run --auto`. OpenCode écrit son plan et son
   journal dans le fichier de suivi, édite, **commite lui-même** (Conventional
   Commits).
3. `finalize.sh` — met le suivi à jour, pousse, poste la section `## Bilan` du
   suivi en **commentaire de PR**. La PR **reste en Draft** (relecture humaine).

En cas d'échec : l'état partiel est poussé, un commentaire signale l'interruption.

## Appeler l'agent depuis un dépôt de cours

```yaml
name: Agent IA
on:
  workflow_dispatch:
    inputs:
      role: { required: true, type: string }
      task: { required: true, type: string }

permissions:
  contents: write
  issues: write
  pull-requests: write

jobs:
  run:
    uses: ocourses/agents/.github/workflows/agent.yml@main
    with:
      role: ${{ inputs.role }}
      task: ${{ inputs.task }}
    secrets:
      ALBERT_API_KEY: ${{ secrets.ALBERT_API_KEY }}
      AGENTS_READ_TOKEN: ${{ secrets.AGENTS_READ_TOKEN }}
```

### Entrées

| Entrée | Défaut | Rôle |
|---|---|---|
| `role` | — | fichier `roles/<role>.md` (override `.agents/roles/<role>.md` prioritaire) |
| `task` | — | la tâche |
| `title` | le rôle | titre court des issue / PR |
| `model` | `deepseek-v4-flash` | id de modèle Albert |
| `agents_ref` | `main` | ref de ce dépôt |
| `base_branch` | branche par défaut | base de la PR |
| `assignee` | `ocots` | login assigné aux issue / PR |
| `link_issue` | *(vide)* | numéro d'une **autre** issue du dépôt appelant à fermer nativement (`Closes #N` supplémentaire dans la PR), en plus de la propre issue de suivi créée par ce workflow — sert pour une issue métier qui existe déjà avant le run (voir plus bas) |

### Secrets (au niveau du **dépôt** appelant)

Sur plan GitHub Free, les secrets d'**organisation** n'atteignent pas les dépôts
privés. Chaque dépôt de cours pose donc ses propres secrets :

```bash
gh secret set ALBERT_API_KEY    -R ocourses/<cours>   # clé Albert
gh secret set AGENTS_READ_TOKEN -R ocourses/<cours>   # PAT fine-grained, Contents:Read
                                                      # sur `agents` + le sous-module template
```

Réglages org (une fois) : *Actions → « Allow GitHub Actions to create and
approve pull requests »* ; et sur ce dépôt, *Actions → Access →
« Accessible from repositories in the organization »*.

## Modèles Albert

`GET /v1/models` fait foi (le catalogue bouge). Au 2026-09-08 :
`deepseek-v4-flash` (défaut, coding agentique, 131k), `openai/gpt-oss-120b`
(généraliste), `qwen3-coder-30b-A3b-instruct`, `gemma-4-31b-it`,
`mistral-small-3-2-24b-instruct-2506`, `ministral-3-8b-instruct-2512`.
Passe l'id exact en input `model`.

## Arborescence

```
.github/workflows/agent.yml      workflow réutilisable (issue → PR → travail → bilan)
.github/workflows/check.yml     workflow réutilisable, générique (détecteurs, pas de modèle)
.github/workflows/latex-pr.yml  workflow réutilisable (compilation LaTeX sur PR non-Draft)
.github/workflows/queue.yml     tourne ICI (pas réutilisable) — verrou global, déclenche agent-migrate-latex.yml à distance
.github/workflows/secrets-expiry.yml  tourne ICI — relève les échéances de secrets, ouvre une issue
scripts/scaffold.sh           couche A — mise en place du chantier
scripts/run-opencode.sh       couche B — assemble AGENTS.md + lance OpenCode
scripts/finalize.sh           couche A — clôture (suivi + bilan)
scripts/checkers/             un détecteur par fichier (template-migration, conventions, …)
scripts/lib/template-scan.sh  détection template partagée : checker (batch, tous pilotes) + queue-next.sh (revérification post-run, un pilote)
scripts/queue-next.sh         dépile une issue de la file, déclenche, attend
scripts/check-secrets-expiry.sh  relit config/secrets-expiry.txt, alerte à J-30
config/opencode.json          provider Albert, permissions
config/AGENTS.base.md         socle commun injecté dans AGENTS.md
config/course-repos.txt       dépôts de cours surveillés par la file d'attente
config/secrets-expiry.txt     échéances des PAT et clés Albert (saisies à la main)
roles/                        un fichier par rôle
```

## Détecteurs — ce qui n'est pas (encore) conforme

`check.yml` (workflow réutilisable, générique) exécute **un** détecteur
`scripts/checkers/<checker>.sh` sur un dépôt de cours et ouvre une issue par
infraction trouvée. **Scripts déterministes, pas des agents** : `grep` /
Python, aucun appel modèle, aucun budget Albert consommé — tournent sur un
cron sans y penser. Un détecteur = un fichier, même principe que `roles/` pour
les agents : ajouter un détecteur, c'est écrire `scripts/checkers/<nom>.sh`,
rien d'autre à toucher dans `check.yml`.

| Checker | Détecte | Label | Source |
|---|---|---|---|
| `template-migration` | document `.tex` pas (ou pas complètement) migré vers le template `ocots` | `template-migration` | extrait `template/tex/ocots-compat.sty` à chaque run |
| `conventions` | **candidats bruts** (pas un verdict) aux règles mécaniques de `ocots-conventions` (P2, P3, P5, C4 au 2026-09-11) | `conventions-candidate` | enveloppe `conventions/bin/verifier` |

### `template-migration`

Deux statuts : `MISSING` (pilote sans `\usepackage[...]{ocots}` — jamais
migré) / `LEGACY` (pilote migré, mais lui ou sa chaîne `\input` utilise
encore un nom de `ocots-compat.sty`). La liste des noms « legacy » est
extraite du fichier à chaque run, pas codée en dur : il maigrit au fil des
migrations, le détecteur se resserre tout seul. Chaque issue contient le
statut, les macros en cause, et la commande prête à lancer
(`gh workflow run agent-migrate-latex.yml -f target=...`).

⚠️ Une ligne de `ocots-compat.sty` ne se supprime que quand **plus aucun
document, dans aucun dépôt de cours existant**, n'utilise ce nom — et un
cours pas encore créé ne peut de toute façon pas être scanné. Ce n'est donc
jamais *prouvable*, seulement *mesurable sur l'existant* : la suppression
reste une décision de dépréciation humaine, pas un geste automatique. Ce qui
est automatisable, en revanche, c'est d'empêcher la régression : qu'un
document **neuf** réintroduise un nom `my*` (à outiller en CI si besoin,
séparément de ce détecteur).

### `conventions`

Enveloppe `conventions/bin/verifier` : regroupe ses trouvailles par fichier,
une issue **candidate** par fichier (pas par ligne, label
`conventions-candidate`). **Idempotent** — un candidat existant est mis à
jour (pas dupliqué), et se ferme tout seul (avec un commentaire) si le
fichier n'a plus de trouvaille brute au run suivant.

**Ce script n'affirme jamais qu'il y a une vraie infraction.** `verifier`
le dit lui-même (`ocots-conventions/README.md`, § « Ce que l'outil ne fait
pas ») : il rate des choses, il signale parfois du correct, zéro trouvaille
ne certifie pas la conformité. Chaque candidat est donc explicitement
marqué comme non relu, et **le jugement est délégué à un agent**
(`conventions-reviewer`, voir « File d'attente » plus bas) — jamais
transformé en verdict par ce seul script. Nécessite le sous-module
`conventions/` ; s'il est absent, le checker sort proprement sans rien
faire (`::warning::`).

### Exclure des documents (`.agents-ignore`)

Les deux détecteurs excluent déjà `template/` et `conventions/` (sous-modules)
en dur. Pour exclure autre chose — propre à **un** cours, ex. des slides pas
encore prêtes pour ce traitement — un fichier `.agents-ignore` à la racine du
dépôt de cours, un préfixe de chemin par ligne (`#` pour commenter) :

```
# .agents-ignore
slides/
```

Absent = aucune exclusion, comportement inchangé. Ce n'est **pas** une règle
du template (sinon elle serait dans les détecteurs eux-mêmes, pas dans un
fichier par dépôt) : `automatique-enseignants`, par exemple, migre ses
slides normalement.

Effet différent selon le détecteur, à cause de leur mécanique respective :

- **`conventions`** : un fichier exclu n'entre jamais dans le regroupement,
  donc une candidate déjà ouverte pour lui se referme **automatiquement** au
  run suivant (même mécanique que « plus aucune trouvaille »).
- **`template-migration`** n'a pas de fermeture automatique (aucune n'a
  jamais existé, exclusion ou pas) : une issue déjà ouverte pour un document
  désormais exclu doit être fermée **à la main**.

### Appel depuis un dépôt de cours

Un seul cron, un job par détecteur activé (le job « générique » ci-dessous
sert de modèle pour en ajouter d'autres) :

```yaml
name: Check — conformité (template + conventions)
on:
  schedule: [{ cron: "0 6 * * 1" }]
  workflow_dispatch: {}
permissions: { contents: read, issues: write }
jobs:
  template-migration:
    uses: ocourses/agents/.github/workflows/check.yml@main
    with: { checker: template-migration }
    secrets:
      AGENTS_READ_TOKEN: ${{ secrets.AGENTS_READ_TOKEN }}
  conventions:
    uses: ocourses/agents/.github/workflows/check.yml@main
    with: { checker: conventions }
    secrets:
      AGENTS_READ_TOKEN: ${{ secrets.AGENTS_READ_TOKEN }}
```

## Compilation LaTeX sur PR (`latex-pr.yml`)

Workflow réutilisable : compile les documents `.tex` touchés par une PR (une
PR d'agent ou une PR humaine), poste le résultat en commentaire, joint les
PDF/logs en artefact. Ne tourne que sur PR **non-Draft** — centralisé ici
depuis (ocourses/agents#2) parce qu'il était dupliqué au caractère près dans
chaque dépôt de cours.

```yaml
name: Compilation LaTeX (PR)
on:
  pull_request:
    types: [synchronize, ready_for_review, reopened]
    paths: ["**/*.tex", "**/*.sty", "**/*.cls", "**/.latexmkrc", ".gitmodules"]
permissions: { contents: read, pull-requests: write }
jobs:
  compile:
    if: github.event.pull_request.draft == false
    uses: ocourses/agents/.github/workflows/latex-pr.yml@main
    secrets:
      AGENTS_READ_TOKEN: ${{ secrets.AGENTS_READ_TOKEN }}
```

Le déclencheur (`on: pull_request`) et la condition Draft restent dans le
dépôt appelant : un workflow `workflow_call` ne peut pas être déclenché
directement par un événement `pull_request`.

## File d'attente — déclenchement automatique

`queue.yml` + `scripts/queue-next.sh` : dépile la plus ancienne tâche
éligible, **tous dépôts de `config/course-repos.txt` confondus**, et
l'envoie au bon workflow — sans intervention humaine. Trois natures de
tâches, trois workflows cibles :

| Label source | Dispatché vers | Rôle | Ce que « succès » veut dire |
|---|---|---|---|
| `template-migration` | `agent-migrate-latex.yml` | `latex-template-migrator` | une PR `[agent] Migration <fichier>` est ouverte **et** la revérification (`scripts/lib/template-scan.sh` sur la branche de la PR) ne trouve plus aucun nom de `ocots-compat.sty` dans la chaîne `\input` du pilote |
| `conventions-candidate` | `agent-review-conventions.yml` | `conventions-reviewer` | l'issue candidate n'est plus `conventions-candidate` (fermée ou promue `conventions-style`) |
| `conventions-style` | `agent-fix-conventions.yml` | `conventions-fixer` | une PR `[agent] Correction conventions <fichier>` est ouverte |

**Le checker `conventions` ne juge jamais** — il l'a dit lui-même
(`ocots-conventions/README.md`, § « Ce que l'outil ne fait pas ») : c'est un
signal mécanique, pas un verdict, il rate des choses et en signale à tort.
Chaque candidat passe donc par un **agent** (`conventions-reviewer`) qui
relit le fichier et décide — confirme (`conventions-style`, reste ouverte
pour action humaine) ou rejette (ferme, avec le motif par ligne). Cet agent
ne modifie jamais le contenu du cours, seulement l'issue.

Parce que `conventions-reviewer` appelle Albert comme n'importe quel autre
agent, il passe par **la même file, le même verrou** que les migrations —
pas de cron séparé, pas de double dépense de budget.

### Le débit : l'auto-chaînage, pas le cron

Un tick = **une** tâche. Avec près de 190 tâches en attente, faire reposer le
débit sur le cron supposerait qu'il parte à l'heure, tous les quarts d'heure,
sans faute — or il ne part pas du tout sur ce dépôt (diagnostic complet dans
l'en-tête de `queue.yml`).

Le script se **redéclenche donc lui-même** en fin de tick tant qu'il reste des
tâches. Le cron est repassé à **une fois par heure** et n'a plus qu'un rôle :
rallumer une chaîne éteinte. Deux conditions d'arrêt :

- plus rien d'éligible ;
- plafond `max_chain` atteint (défaut **6** ticks d'affilée), pour qu'une file
  qui se regarnit toute seule — les détecteurs tournent chaque semaine — ne
  puisse pas boucler indéfiniment.

Le redéclenchement passe par `AGENTS_DISPATCH_TOKEN`, **jamais** par
`github.token` : un `workflow_dispatch` émis avec le jeton par défaut ne crée
pas de nouveau run, c'est le garde-fou anti-récursion de GitHub Actions. D'où
la nécessité que le PAT porte aussi sur `ocourses/agents` lui-même, en
`Actions:write`.

Pour lancer une chaîne à la main : *Actions → File d'attente → Run workflow*,
en laissant `chain` à 0. `max_chain` y est réglable au coup par coup.

**Ordre de grandeur observé** : ~40 min pour une migration, ~4 min pour un
triage conventions. Les runs d'agent s'exécutent dans les dépôts de cours, qui
restent **privés donc facturés** — vider toute la file dépasserait le quota
mensuel inclus. À surveiller avant de lancer une longue chaîne.

### Le verrou global — pourquoi un nouveau workflow, pas juste `concurrency:`

`agent.yml` est un *workflow réutilisable* : sa `concurrency: group:
agent-albert-${{ github.repository }}` s'évalue dans le contexte du dépôt
**appelant**. GitHub Actions ne fait **pas** interagir deux groupes de
concurrency situés dans deux dépôts différents, même identiques par leur nom
— deux dépôts de cours peuvent donc consommer Albert en même temps.

`queue.yml` contourne ça en ne bougeant pas : il tourne **toujours dans
`ocourses/agents`** (jamais en `workflow_call`), déclenche
`agent-migrate-latex.yml` sur le dépôt cible via `gh workflow run`, puis
**attend la fin** (`gh run watch`) avant de rendre la main. Tant qu'un tick
n'est pas fini, `concurrency: group: agent-albert-global,
cancel-in-progress: false` retient le suivant en file — cette fois, pour de
vrai, puisque tous les ticks sont des runs du *même* workflow dans le *même*
dépôt.

### Mise en place (une fois)

1. **PAT fine-grained** (GitHub → Settings → Developer settings → Fine-grained
   tokens), portée sur les dépôts de `config/course-repos.txt` :
   `Issues` (lire/écrire), `Actions` (lire/écrire), `Contents` (lire),
   `Metadata` (lire, obligatoire). Poser comme secret **`AGENTS_DISPATCH_TOKEN`
   sur `ocourses/agents` uniquement** — pas besoin de le dupliquer par dépôt
   de cours, contrairement à `ALBERT_API_KEY` / `AGENTS_READ_TOKEN` : ce PAT
   est utilisé *depuis* `ocourses/agents`, jamais injecté ailleurs.
2. **`config/course-repos.txt`** — un dépôt par ligne, seulement ceux qui ont
   déjà `agent.yml` + `agent-migrate-latex.yml` + `agent-review-conventions.yml`
   + `ALBERT_API_KEY` (sinon le déclenchement échoue proprement, avec un
   commentaire d'erreur sur l'issue). Un cours pas encore embarqué : on
   l'ajoute plus tard, rien à changer ailleurs.
3. Sans le secret, `queue.yml` échoue vite et clairement (`::error::`) — pas
   de comportement silencieux.

### Comportement en échec

Un run qui échoue — ou, selon le type de tâche, dont la PR n'est pas
retrouvée ou dont la revérification trouve encore des noms de
`ocots-compat.sty` (migration) ou dont l'issue candidate n'a pas changé
d'état (conventions) — **n'est pas retenté automatiquement** : l'issue reçoit le
label `agent:failed` et un commentaire avec le lien du run. Retirer le label
la remet en file. Ce choix délibéré évite qu'une cible cassée ne boucle en
silence sur le budget Albert.

### Coordination avec un travail manuel — protocole de réclamation

Le verrou global (`concurrency: agent-albert-global`) protège les runs de
`queue.yml` **entre eux**. Il ne protège rien du tout contre un travail
manuel — par exemple une session Claude Code locale — qui lirait/modifierait
la même issue sans passer par cette file : ce chemin-là ne touche jamais
GitHub Actions, donc jamais ce verrou.

`scripts/claim-issue.sh` est la **source unique** du protocole de
réclamation, utilisée par `queue-next.sh` et par tout travail manuel :

```bash
scripts/claim-issue.sh status  <repo> <issue>            # libre / réclamée / échec
scripts/claim-issue.sh claim   <repo> <issue> <origine>   # échoue si déjà réclamée
scripts/claim-issue.sh release <repo> <issue>             # fin normale (succès)
scripts/claim-issue.sh fail    <repo> <issue> <raison>    # échec, libère la réclamation
```

GitHub n'offre pas de transaction sur les labels (pas de compare-and-swap) :
ce n'est donc **pas** un verrou parfait, seulement une convention — vérifier,
réclamer tout de suite après, ne jamais commencer le travail avant que
`claim` ait réussi. Avec un seul bot (verrou global : jamais deux ticks
automatisés en même temps) et un seul humain à la fois, la fenêtre de course
est nulle en pratique si le protocole est suivi des deux côtés.

**Réclamation abandonnée** (run Actions annulé/tué avant sa propre gestion
d'échec, ou session locale interrompue sans être allée jusqu'à `release` ou
`fail`) : `queue-next.sh` scanne, à chaque tick et pour chaque dépôt, les
issues `agent:dispatched` dont le commentaire de prise en charge date de plus
de `STALE_HOURS` (défaut 3 h, largement au-dessus du pire cas observé
~40 min) et les marque `agent:failed` automatiquement — sans ce filet, une
réclamation morte resterait bloquée pour de bon, invisible.

*(Un validateur séparé qui interdirait la coexistence de certains labels a été
envisagé et écarté : GitHub ne permettant pas de vraie transaction, un tel
validateur ne ferait que détecter une course après coup — exactement ce que
fait déjà le ramasse-miettes ci-dessus, pour moins de complexité.)*

**Confier une issue à une session Claude Code locale** — modèle à copier en
adaptant `<repo>` et `<issue>` :

> Tu vas traiter l'issue `<repo>#<issue>` de la file d'attente
> `ocourses/agents`.
>
> 1. Vérifie d'abord : `bash scripts/claim-issue.sh status <repo> <issue>`
>    (dans un clone de `ocourses/agents`, avec `gh` déjà authentifié). Si le
>    résultat n'est pas `libre`, **arrête-toi et préviens-moi** — ne touche à
>    rien.
> 2. Réclame : `bash scripts/claim-issue.sh claim <repo> <issue> "Claude Code
>    local (Olivier)"`. Si ça échoue, quelqu'un t'a devancé entre les deux
>    étapes — arrête-toi.
> 3. Regarde le label présent sur l'issue (`template-migration`,
>    `conventions-candidate` ou `conventions-style`) et suis les instructions
>    du rôle correspondant (`roles/latex-template-migrator.md`,
>    `roles/conventions-reviewer.md` ou `roles/conventions-fixer.md` dans
>    `ocourses/agents`) — mêmes consignes que l'agent automatisé.
> 4. Ouvre une PR dont le corps contient `Closes #<issue>` (lien natif
>    GitHub, fermeture automatique à la fusion).
> 5. À la fin : succès → `bash scripts/claim-issue.sh release <repo>
>    <issue>` ; échec → `bash scripts/claim-issue.sh fail <repo> <issue>
>    "<raison>"`. Dans les deux cas, ne me laisse jamais l'issue réclamée sans
>    rien d'autre.

## Rôles fournis

| Rôle | Mission |
|---|---|
| `latex-template-migrator` | passe un document `.tex` (et ses `\input`) au template `ocots`, sans toucher au fond |
| `exercise-corrector` | rédige les corrigés d'un TD |
| `course-author` | complète / rédige une section de poly |
| `reviewer` | relit et produit un rapport, sans réécrire |
| `conventions-reviewer` | trie un candidat `conventions-candidate` (sortie brute de `conventions/bin/verifier`) : confirme, rejette ou complète — jamais de réécriture |
| `conventions-fixer` | corrige les points **confirmés** d'une issue `conventions-style`, remède documenté par `ocots-conventions` — ne tranche pas un choix d'auteur (ex. C2) |

## Ajouter un rôle

Créer `roles/<nom>.md` : Mission · Périmètre (interdits) · Cible/références ·
Méthode · Diff idéal. Pas d'instructions sur les outils (OpenCode s'en charge),
pas de scission plan/travail. Le workflow le trouve par son nom.

## Maintenance

- **OpenCode est épinglé** (`OPENCODE_VERSION` dans `scripts/run-opencode.sh`).
  Bumper de temps en temps, tester via un run avant de merger.
- Les identifiants de modèles Albert peuvent devenir périmés — vérifier
  `GET /v1/models`.

### Échéances des secrets

Tous les jetons de ce montage expirent, à des dates échelonnées — quatre rien
que pour les PAT. Le jour où l'un tombe, le symptôme est muet et trompeur :
échec de checkout du dépôt privé `agents`, ou 401 d'Albert au milieu d'un run.
Rien ne dit « jeton expiré ».

`secrets-expiry.yml` (hebdomadaire) relit `config/secrets-expiry.txt` et ouvre
une issue dès qu'une échéance passe sous 30 jours, est dépassée, ou n'est pas
renseignée. **Après chaque rotation, mettre ce fichier à jour** : GitHub
n'expose pas l'échéance d'un PAT par l'API, les dates y sont saisies à la main
et le fichier ment dès qu'on l'oublie.

Ce workflow n'utilise que `github.token` et ne lit aucun des secrets qu'il
surveille : il ne peut donc pas tomber en panne pour la raison même qu'il
surveille. En contrepartie il suit des **dates**, il ne teste pas la validité
des clés — un secret ne se teste que depuis le dépôt qui le détient, ce qui
demanderait un job dans chacun des trois cours.

**Recoupement automatique côté Albert.** Contrairement à GitHub, Albert expose
l'échéance : `GET /v1/keys/{id}` renvoie un champ `expires` (timestamp Unix,
`null` si la clé n'expire jamais). C'est pourquoi la dernière colonne du
fichier porte l'identifiant numérique de la clé — `albert-api-key-automatique
(#50717)`. Si le secret **facultatif** `ALBERT_API_KEY` est posé sur
`ocourses/agents`, le job compare chaque date saisie à la date réelle, signale
les écarts, et **calcule l'alerte sur la date d'Albert** : une date saisie trop
optimiste ne peut donc plus masquer une échéance imminente. Sans ce secret,
tout fonctionne à l'identique sur les seules dates du fichier.

Le script ne journalise jamais la réponse d'Albert : `GET /v1/keys/{id}`
renvoie aussi un champ `value` qui est **la clé en clair**. Seul `expires` en
est extrait.

Rappel : chaque cours a ses propres `ALBERT_API_KEY` et `AGENTS_READ_TOKEN`
(valeurs distinctes sous des noms identiques). Il n'y a pas de rotation
groupée possible, et c'est voulu — une clé compromise sur un cours n'expose
pas les autres.
