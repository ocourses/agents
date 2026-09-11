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
.github/workflows/agent.yml   workflow réutilisable (issue → PR → travail → bilan)
.github/workflows/check.yml   workflow réutilisable, générique (détecteurs, pas de modèle)
.github/workflows/queue.yml   tourne ICI (pas réutilisable) — verrou global, déclenche agent-migrate-latex.yml à distance
scripts/scaffold.sh           couche A — mise en place du chantier
scripts/run-opencode.sh       couche B — assemble AGENTS.md + lance OpenCode
scripts/finalize.sh           couche A — clôture (suivi + bilan)
scripts/checkers/             un détecteur par fichier (template-migration, conventions, …)
scripts/queue-next.sh         dépile une issue de la file, déclenche, attend
config/opencode.json          provider Albert, permissions
config/AGENTS.base.md         socle commun injecté dans AGENTS.md
config/course-repos.txt       dépôts de cours surveillés par la file d'attente
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
| `conventions` | infractions **mécaniques** aux règles de `ocots-conventions` (P2, P3, P5, C4 au 2026-09-11) | `conventions-style` | enveloppe `conventions/bin/verifier` |

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
une issue par fichier (pas par ligne). **Idempotent** — une issue existante
est mise à jour (pas dupliquée), et se ferme toute seule (avec un
commentaire) si le fichier n'a plus d'infraction au run suivant. Chaque
issue rappelle que l'outil *mesure une ampleur, il ne certifie rien* (voir
`ocots-conventions/README.md`, section « Ce que l'outil ne fait pas ») —
zéro trouvaille ne veut pas dire la règle respectée, une trouvaille n'est
pas automatiquement une faute. Nécessite le sous-module `conventions/` ;
s'il est absent, le checker sort proprement sans rien faire (`::warning::`).

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

## File d'attente — déclenchement automatique des migrations

`queue.yml` + `scripts/queue-next.sh` : dépile la plus ancienne issue
`template-migration` (label posé par le checker ci-dessus), **tous dépôts de
`config/course-repos.txt` confondus**, et lui envoie `agent-migrate-latex.yml`
— sans intervention humaine. C'est le côté « travail » automatique, pendant
que le checker reste le côté « détection ».

**Seul `template-migration` est auto-déclenché.** Les issues `conventions`
restent détection seule : pas de correcteur automatique sûr pour des règles
qui demandent du jugement (P2, P3, P5) — voir plus bas si vous voulez brancher
`nettoyer` (mécanique, C4 seulement) en plus.

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
   déjà `agent.yml` + `agent-migrate-latex.yml` + `ALBERT_API_KEY` (sinon le
   déclenchement échoue proprement, avec un commentaire d'erreur sur
   l'issue). Un cours pas encore embarqué : on l'ajoute plus tard, rien à
   changer ailleurs.
3. Sans le secret, `queue.yml` échoue vite et clairement (`::error::`) — pas
   de comportement silencieux.

### Comportement en échec

Un run qui échoue (ou dont la PR n'est pas retrouvée) **n'est pas retenté
automatiquement** : l'issue reçoit le label `agent:failed` et un commentaire
avec le lien du run. Retirer le label la remet en file. Ce choix délibéré
évite qu'une cible cassée ne boucle en silence sur le budget Albert.

## Rôles fournis

| Rôle | Mission |
|---|---|
| `latex-template-migrator` | passe un document `.tex` (et ses `\input`) au template `ocots`, sans toucher au fond |
| `exercise-corrector` | rédige les corrigés d'un TD |
| `course-author` | complète / rédige une section de poly |
| `reviewer` | relit et produit un rapport, sans réécrire |

## Ajouter un rôle

Créer `roles/<nom>.md` : Mission · Périmètre (interdits) · Cible/références ·
Méthode · Diff idéal. Pas d'instructions sur les outils (OpenCode s'en charge),
pas de scission plan/travail. Le workflow le trouve par son nom.

## Maintenance

- **OpenCode est épinglé** (`OPENCODE_VERSION` dans `scripts/run-opencode.sh`).
  Bumper de temps en temps, tester via un run avant de merger.
- Les identifiants de modèles Albert peuvent devenir périmés — vérifier
  `GET /v1/models`.
