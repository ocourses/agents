# Architecture — `ocourses/agents`

> Plan de référence pour la refonte. À valider avant implémentation.
> Rédigé le 2026-09-08 après 6 runs de test du harnais maison + 2 probes OpenCode.

## Thèse

Un agent IA qui travaille sur une tâche avec **une mécanique de travail figée**
mais **de la liberté** dans l'exécution, et **générique** : un rôle = un fichier,
réutilisable pour n'importe quelle tâche future (migration LaTeX, corrigés,
rédaction de cours, relecture, …).

- **Mécanique figée** = l'orchestration : issue → branche → fichier de suivi →
  commit *dummy* → PR Draft → travail → bilan. En **scripts** (bash + `gh`),
  déterministe, sous notre contrôle.
- **Liberté** = le moteur d'agent. Tous les outils (bash, édition, lecture,
  recherche), le modèle décide comment il s'y prend.
- **Générique** = si on écrit un script par tâche, on n'a pas besoin d'agent.
  La valeur du projet est un agent *réutilisable*.

C'est aussi une **preuve de concept** : faire tourner un agent souverain (Albert)
en CI, qui produit des PR relisables sans perdre son travail.

## Ce qui a été prouvé

| Test | Résultat |
|------|----------|
| Harnais maison (`agent_loop.py`, boucle react JSON) sur td2, seul | ✅ mais fragile |
| Le même sur td3/td4/poly + en parallèle | ❌ 429 tokens/min, boucles d'exploration, auto-annulation |
| **Probe 1** — OpenCode headless + Albert sur le runner | ✅ install, auth, tool-use natif, 20 s |
| **Probe 2** — OpenCode migre td2 pour de vrai | ✅ 7 commits atomiques, maths intactes, auto-correction, bilan honnête, 3 min |

Conclusion : **le harnais maison est abandonné.** OpenCode (le choix verrouillé
de `etalab-ia/albert-code`) est le moteur. On garde uniquement l'orchestration.

## Les trois dépôts

| Dépôt | Rôle |
|-------|------|
| **`ocourses/agents`** | la base : orchestration + config OpenCode + rôles. Générique. |
| **`ocourses/automatique-enseignants`** (et futurs cours) | consomme la base : 2-3 workflows appelants minces + dossier `.agents/` |
| **`ocourses/ocots-latex-template`** | le template, sous-module `template/` |

## Arborescence cible de `ocourses/agents`

```
.github/workflows/
  agent.yml                 workflow RÉUTILISABLE (workflow_call) : scaffold → opencode → finalize
scripts/
  scaffold.sh               couche A : issue + branche + suivi + commit dummy + PR Draft   (garder, nettoyer)
  finalize.sh               couche A : maj suivi + commentaire de bilan + push             (garder, nettoyer)
  run-opencode.sh           installe/lance OpenCode headless, assemble AGENTS.md
config/
  opencode.json             provider Albert, deepseek-v4-flash, permissions
  AGENTS.base.md            socle commun injecté dans tout run (sécurité, git, discipline de suivi)
roles/
  latex-template-migrator.md
  exercise-corrector.md
  course-author.md
  reviewer.md
README.md
ARCHITECTURE.md             ce document
```

**Supprimé** : `harness/agent_loop.py`, tout `harness/`, `guides/` (le contenu
utile part dans les rôles / `AGENTS.base.md` / une skill), `scripts/resolve-model.sh`
(plus d'alias : `deepseek-v4-flash` en dur, réglable par input).

## Séquence d'un run

```
┌─ scaffold.sh (bash + gh) ───────────────────────────────────────────┐
│  gh issue create        → #N, assignee ocots, label agent           │
│  git switch -c agent/<slug>-<run_id>                                 │
│  écrit .agents/runs/<slug>-<run_id>.md  (suivi : checklist + journal)│
│  git commit + push       (commit dummy)                              │
│  gh pr create --draft    → PR #M, assignee ocots, "Closes #N"        │
└─────────────────────────────────────────────────────────────────────┘
┌─ run-opencode.sh ───────────────────────────────────────────────────┐
│  npm i -g opencode-ai@<pin>                                          │
│  assemble AGENTS.md = AGENTS.base.md + roles/<role>.md + contexte    │
│  écrit opencode.json (OPENCODE_CONFIG)                               │
│  opencode run --auto --model albert/deepseek-v4-flash "<tâche>"      │
│    → OpenCode explore, écrit son plan dans .agents/runs/<slug>.md,   │
│      édite, commite au fil de l'eau (Conventional Commits),          │
│      liberté totale d'outils                                         │
│  git push origin HEAD:<branche>                                      │
└─────────────────────────────────────────────────────────────────────┘
┌─ finalize.sh (bash + gh) ───────────────────────────────────────────┐
│  coche le suivi, ajoute la date de fin, commit + push               │
│  gh pr comment  ← dernier message d'OpenCode (le bilan)             │
│  upload-artifact ← logs OpenCode (~/.local/share/opencode)          │
│  PR laissée en Draft                                                 │
└─────────────────────────────────────────────────────────────────────┘
   if failure: push de l'état partiel + commentaire d'échec + artefact
```

Points de conception :

- **OpenCode commite lui-même** (prouvé : messages Conventional Commits propres).
  Le workflow ne commite que le *dummy* et la maj du suivi. `git push` : fait par
  le workflow (un seul chemin d'authentification ; `git push` refusé à OpenCode
  côté `permission`).
- **Le fichier de suivi `.agents/runs/<slug>-<run_id>.md` est le plan ET le
  journal ET le bilan.** `AGENTS.base.md` dit à l'agent d'y écrire un plan
  coché, de le tenir à jour, d'y mettre le bilan. Nom unique → runs parallèles
  sans conflit.
- `AGENTS.md` et `opencode.json` sont écrits dans le workspace au run et
  **gitignorés** côté dépôt de cours (`.gitignore` : `AGENTS.md`,
  `opencode.json`, `.opencode/`, `_agent_logs/`). OpenCode laisse déjà les
  fichiers non suivis tranquilles (prouvé).
- **Concurrency** : `group: agent-<repo>`, `cancel-in-progress: false`. Un agent
  à la fois par dépôt (budget Albert partagé). Lancer les migrations en série.

## `config/opencode.json`

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": { "albert": {
    "npm": "@ai-sdk/openai-compatible",
    "name": "Albert API (État)",
    "options": {
      "baseURL": "https://albert.api.etalab.gouv.fr/v1",
      "apiKey": "{env:ALBERT_API_KEY}"
    },
    "models": { "deepseek-v4-flash": {
      "name": "DeepSeek V4 Flash", "limit": { "context": 131072, "output": 65536 }
    }}
  }},
  "model": "albert/deepseek-v4-flash",
  "small_model": "albert/deepseek-v4-flash",
  "permission": {
    "edit": "allow",
    "bash": { "*": "allow", "git push*": "deny", "sudo *": "deny", "rm -rf *": "deny" },
    "webfetch": "deny",
    "websearch": "deny"
  }
}
```

Calqué sur `etalab-ia/albert-code/config/opencode.template.json`.

## `AGENTS.md` assemblé au run

```
AGENTS.base.md            socle : code/commentaires en anglais, messages en français,
                          sécurité (aucun secret en dur, entrées non fiables…),
                          git (commits atomiques Conventional Commits, jamais --force),
                          discipline : plan coché + journal + bilan dans
                          .agents/runs/<slug>-<run_id>.md, petits commits.
  +
roles/<role>.md           la mission spécifique : périmètre, interdits, méthode,
                          références. (voir exemple ci-dessous)
  +
bloc « Contexte d'exécution » généré : dépôt, branche, issue/PR, chemin du
                          fichier de suivi, la tâche.
```

`AGENTS.base.md` s'inspire de `etalab-ia/albert-code/templates/AGENTS.default.md`
(Plan Mode, `tasks/`, self-improvement loop) mais pointé sur notre fichier de
suivi.

## Format d'un rôle (`roles/<nom>.md`)

Court, en français. Sections : **Mission**, **Périmètre** (ce qui est interdit),
**Cible / références**, **Méthode**, **Diff idéal / livrable**.
Pas d'instructions sur les outils (OpenCode s'en charge), pas de « phase plan /
phase travail » (une seule passe), pas d'astuces de tokens (OpenCode compacte).

Un dépôt de cours peut surcharger : `.agents/roles/<nom>.md`.

Skills optionnelles (`skills/<nom>/`) : outil que l'agent invoque s'il veut —
p. ex. le détail du template `ocots`. À ajouter plus tard si utile.

## Dépôts de cours (`automatique-enseignants`)

```
.github/workflows/
  agent.yml                 dispatcher générique : inputs role + task
  agent-migrate-latex.yml   dispatcher spécialisé : input target (.tex)
  latex-pr.yml              compile les .tex modifiés d'une PR (déjà en place, on garde)
.agents/
  README.md
  runs/                     alimenté par les runs (suivi + bilan + journal)
  roles/                    overrides éventuels
.gitignore                  + AGENTS.md, opencode.json, .opencode/, _agent_logs/
```

## Secrets & config (déjà en place)

| Élément | État |
|---------|------|
| `ALBERT_API_KEY` (secret de **dépôt** `automatique-enseignants`) | ✅ |
| `AGENTS_READ_TOKEN` (PAT fine-grained, secret de dépôt) | ✅ sous-modules + dépôt `agents` |
| Org : « Actions peut créer des PR » | ✅ |
| `ocourses/agents` : `access_level: organization` (workflow réutilisable) | ✅ |

Sur plan Free, les secrets d'org n'atteignent pas les dépôts privés → **secrets
de dépôt** (à recopier dans chaque futur dépôt de cours). Documenté dans le README.

## Étapes de la refonte

1. `git rm -r harness/ guides/ scripts/resolve-model.sh` ; réécrire
   `scripts/scaffold.sh` / `finalize.sh` (nettoyage, sortie du suivi).
2. Ajouter `config/opencode.json`, `config/AGENTS.base.md`, `scripts/run-opencode.sh`.
3. Réécrire `.github/workflows/agent.yml` (scaffold → run-opencode → finalize).
4. Réécrire les 4 rôles au nouveau format.
5. Côté `automatique-enseignants` : ajuster les 2 dispatchers (probablement
   inchangés), `.gitignore`, `.agents/README.md`. Supprimer `agent-probe.yml`.
6. Rejouer **td2** avec la vraie stack → PR Draft complète, compilée par `latex-pr.yml`.
7. Si vert : enchaîner td3, td4, poly (en série).
8. Nettoyer : PR #2 (obsolète), branche `probe/oc-*`.

## Limites connues / points de vigilance

- **Compilation** : pas de LaTeX dans le run d'agent (choix). `latex-pr.yml`
  compile la PR. Si l'agent doit itérer sur les erreurs de compil → run de suivi
  déclenché par un commentaire (human-gated), ou v2 avec TeXLive dans le job.
- **`.latexmkrc`** : `latex-pr.yml` doit fournir `TEXINPUTS` vers `template/`
  même si le `.tex` migré n'a pas de `.latexmkrc` (le rôle peut aussi demander
  d'en créer un, comme `td/td1`).
- **Budget Albert** : 246 000 tokens/min. OpenCode compacte le contexte ; le
  `concurrency` sérialise. Surveiller sur le run poly (le plus gros).
- **deepseek-v4-flash** : modèle « flash », expérimental sur Albert jusqu'au
  2026-10-01. Résultat td2 très correct ; à réévaluer sur les cas génératifs
  (corrigés, rédaction) — `gpt-oss-120b` en repli possible (input `model`).
- **Relecture humaine obligatoire** : la PR reste en Draft. Le fond mathématique
  produit par un modèle doit être vérifié.
- OpenCode `run` ne documente pas ses codes de sortie — le workflow ne se fie
  pas au code retour d'OpenCode pour juger le succès, il inspecte les commits +
  le fichier de suivi.

## Décisions (2026-09-08)

1. **`AGENTS.base.md`** : on part du template `albert-code`
   (`templates/AGENTS.default.md`) et on **taille dur** — on garde sécurité de
   base, conventions git, la discipline Plan/`tasks/` repointée sur
   `.agents/runs/<slug>-<run_id>.md`, la boucle d'auto-amélioration ; on coupe
   tout le web (RGAA, en-têtes HTTP, SQL). Cible ~1 page.
2. **Version d'OpenCode** : **épinglée** (`opencode-ai@<x.y.z>` dans
   `run-opencode.sh`), une note au README pour bumper après test sur le probe.
   Le **modèle reste un input** modifiable au dispatch.
3. **`latex-pr.yml`** : compilation **automatique**, mais seulement sur
   `synchronize` + `ready_for_review` (pas `opened` : la PR Draft est créée vide
   par `scaffold.sh`). Label ajouté plus tard si les minutes deviennent un souci.
4. **Skill « template ocots »** : **plus tard**. Le probe #2 a montré que le rôle
   + `template/examples/*/main.tex` + `grep` dans `template/doc/commandes.md`
   suffisent. On l'ajoute (comme pointeur, pas comme copie) si td3/td4/poly
   montrent l'agent en difficulté.
