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
.github/workflows/agent.yml   workflow réutilisable
scripts/scaffold.sh           couche A — mise en place du chantier
scripts/run-opencode.sh       couche B — assemble AGENTS.md + lance OpenCode
scripts/finalize.sh           couche A — clôture (suivi + bilan)
config/opencode.json          provider Albert, permissions
config/AGENTS.base.md         socle commun injecté dans AGENTS.md
roles/                        un fichier par rôle
```

## Rôles fournis

| Rôle | Mission |
|---|---|
| `latex-template-migrator` | passe un `.tex` au template `ocots`, sans toucher au fond |
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
