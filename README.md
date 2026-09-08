# `ocourses/agents` — base d'agents IA pour les cours

Workflow GitHub Actions réutilisable qui fait travailler un agent IA (modèle
**Albert**, API souveraine) sur un dépôt de cours, **sans jamais perdre son
travail** : chaque run laisse une trace complète (issue, branche, fichier de
suivi, plan d'action, commits, PR Draft, commentaire de bilan).

## Principe : deux couches

| Couche | Qui | Fait quoi |
|--------|-----|-----------|
| **A — orchestration** | `scripts/*.sh` + `gh`, 100 % déterministe | issue → branche → suivi → commit dummy → PR Draft → … → maj suivi → commentaire de bilan |
| **B — agent** | `harness/agent_loop.py` + un rôle | phase *plan* (exploration + plan d'action) puis phase *travail* (édition + commits) |

Le **rôle** d'un agent est un simple fichier Markdown (`roles/<nom>.md`) qui sert
de *system prompt*. Ajouter un agent = ajouter un fichier.

## Séquence d'un run

1. Ouvre une **issue** (rôle + tâche), assignée à `ocots`.
2. Crée la **branche** `agent/<slug>-<run_id>`.
3. Écrit le **fichier de suivi** `.agents/runs/<slug>-<run_id>.md` (nom unique →
   runs parallèles sans conflit), le commite (*commit dummy*), le pousse.
4. Ouvre une **PR Draft**, assignée à `ocots`, liée à l'issue.
5. **Phase plan** : l'agent explore le dépôt (commandes en lecture seule) et
   écrit `.agents/plans/<slug>-<run_id>.md`. Commit + push. Suivi mis à jour.
6. **Phase travail** : l'agent implémente le plan, **commits réguliers**.
7. **Clôture** : suivi mis à jour, **commentaire de bilan** sur la PR.
   La PR **reste en Draft** — relecture humaine avant « Ready ».

En cas d'échec, l'état partiel est poussé et un commentaire signale l'interruption.

## Appeler l'agent depuis un dépôt de cours

Un workflow minimal dans le dépôt de cours :

```yaml
name: Agent — migration LaTeX
on:
  workflow_dispatch:
    inputs:
      target: { description: "Fichier .tex à migrer", required: true }

permissions:
  contents: write
  issues: write
  pull-requests: write

jobs:
  run:
    uses: ocourses/agents/.github/workflows/agent.yml@main
    with:
      role: latex-template-migrator
      task: "Migrer ${{ inputs.target }} vers le template ocots, sans changer le fond."
      title: "Migration ${{ inputs.target }}"
    secrets: inherit
```

### Entrées du workflow réutilisable

| Entrée | Défaut | Rôle |
|--------|--------|------|
| `role` | — | fichier sous `roles/` (sans `.md`) |
| `task` | — | tâche confiée à l'agent |
| `title` | le rôle | titre court des issue / PR |
| `model` | `deepseek` | alias ou id Albert (voir `scripts/resolve-model.sh`) |
| `protocol` | `react` | `react` (robuste) ou `tools` (function calling) |
| `agents_ref` | `main` | ref de ce dépôt (rôle + harness) |
| `base_branch` | branche par défaut | branche de base de la PR |
| `assignee` | `ocots` | login assigné aux issue / PR |
| `max_steps` | `40` | pas max de l'agent par phase |

### Secrets attendus (org `ocourses`)

| Secret | Usage |
|--------|-------|
| `ALBERT_API_KEY` | appels modèle |
| `AGENTS_READ_TOKEN` | PAT lecture seule : sous-modules privés + checkout de ce dépôt |

L'écriture (issue, PR, commits) passe par le `GITHUB_TOKEN` du dépôt appelant ;
activer *Settings → Actions → « Allow GitHub Actions to create and approve pull
requests »* au niveau de l'org.

## Modèles Albert

`scripts/resolve-model.sh` mappe des alias vers les identifiants canoniques
(à vérifier via `GET /v1/models`, le catalogue évolue) :

| Alias | Identifiant | Note |
|-------|-------------|------|
| `deepseek` | `deepseek-v4-flash` | coding agentique, *tool calling*, contexte 131k — défaut |
| `qwen-coder` | `qwen3-coder-30b-A3b-instruct` | spécialisé code |
| `gpt-oss` | `openai/gpt-oss-120b` | généraliste, tâches complexes |
| `gemma` | `gemma-4-31b-it` | généraliste |
| `mistral-small` | `mistral-small-3-2-24b-instruct-2506` | tâches moyennes |
| `ministral` | `ministral-3-8b-instruct-2512` | tâches simples |

## Arborescence

```
.github/workflows/agent.yml   workflow réutilisable (couches A + B)
harness/agent_loop.py         boucle tool-use Albert (stdlib seule)
scripts/scaffold.sh           couche A — mise en place du chantier
scripts/finalize.sh           couche A — clôture (suivi + bilan)
scripts/resolve-model.sh      alias de modèle → identifiant Albert
roles/                        system prompts, un fichier par rôle
guides/                       règles transverses injectées dans le prompt
```

Un dépôt de cours peut **surcharger** un rôle en plaçant `.agents/roles/<nom>.md`
chez lui.

## Guides

Règles transverses (rédaction, template) dans `guides/<nom>.md`. Un rôle déclare
ceux qu'il veut par un commentaire en tête de son fichier :

```markdown
<!-- guides: template-ocots redaction-poly -->
```

Le harness concatène ces guides au *system prompt*. Guides fournis :

| Guide | Contenu |
|-------|---------|
| `template-ocots` | préambule, environnements, exercices, migration v0 |
| `redaction-poly` | règles de style (texte entre les boîtes, amorces, typo…), tirées de `calcul-differentiel-edo-enseignants` |

## Rôles fournis

| Rôle | Mission |
|------|---------|
| `latex-template-migrator` | passe un `.tex` au template `ocots`, sans toucher au fond |
| `exercise-corrector` | rédige les corrigés d'un TD |
| `course-author` | complète / rédige une section de poly |
| `reviewer` | relit et produit un rapport, sans réécrire |

## Ajouter un rôle

Créer `roles/<nom>.md` : mission, périmètre (ce qui est interdit), méthode par
phase (plan / travail / bilan). C'est tout — le workflow le trouve par son nom.

## Limites connues

- Le harness est volontairement minimal (un seul appel d'outil par tour). Pour
  des tâches très longues, augmenter `max_steps` ou découper la tâche.
- La vérification de compilation LaTeX lourde (TeX Live complet) est laissée aux
  workflows de CI du dépôt de cours, pas au run d'agent.
- Le fond mathématique produit par un modèle doit toujours être relu.
