#!/usr/bin/env python3
"""Boucle tool-use minimale pour un agent Albert (API OpenAI-compatible).

Couche B de la base d'agents : une fois l'issue, la branche, le fichier de suivi
et la PR Draft créés par la couche A (``scripts/scaffold.sh``), ce script fait
travailler le modèle.

Deux phases :
  * ``plan``  — le modèle explore le dépôt (commandes en lecture seule) et écrit
                un plan d'action ; il ne modifie aucun fichier du cours.
  * ``work``  — le modèle implémente le plan, commite au fil de l'eau, puis
                appelle ``finish`` avec un résumé.

Dépendances : bibliothèque standard uniquement.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

DEFAULT_BASE = "https://albert.api.etalab.gouv.fr/v1"
READ_TRUNCATE = 16_000
BASH_TRUNCATE = 8_000
BASH_TIMEOUT = 300

# Chemins interdits en écriture (relatifs à la racine du dépôt).
WRITE_DENY = (".git", ".github/workflows", "template")
# Motifs bash refusés : footguns qui casseraient l'orchestration.
BASH_DENY = (
    r"\bgit\s+push\b",
    r"\bgit\s+remote\b",
    r"\bgh\s+auth\b",
    r"\bgh\s+secret\b",
    r"\bgit\s+reset\s+--hard\b",
    r"rm\s+-rf\s+/(?:\s|$)",
)


class AgentError(RuntimeError):
    pass


# --------------------------------------------------------------------------- API


def call_model(base: str, api_key: str, model: str, messages: list[dict],
               timeout: int = 180) -> str:
    """Un appel /chat/completions, renvoie le texte de la réponse."""
    payload = json.dumps({
        "model": model,
        "messages": messages,
        "temperature": 0.2,
    }).encode("utf-8")
    req = urllib.request.Request(
        f"{base.rstrip('/')}/chat/completions",
        data=payload,
        method="POST",
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
    )
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                body = json.load(resp)
            return body["choices"][0]["message"]["content"] or ""
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", "replace")[:500]
            if exc.code in (429, 500, 502, 503, 504) and attempt < 3:
                time.sleep(2 ** attempt * 3)
                continue
            raise AgentError(f"HTTP {exc.code} d'Albert : {detail}") from exc
        except (urllib.error.URLError, TimeoutError) as exc:
            if attempt < 3:
                time.sleep(2 ** attempt * 3)
                continue
            raise AgentError(f"Albert injoignable : {exc}") from exc
    raise AgentError("Albert : échec après plusieurs tentatives")


# ------------------------------------------------------------------------- outils


class Tools:
    def __init__(self, repo: Path, branch: str, summary_path: Path,
                 plan_only: bool, plan_path: Path, dry_run: bool):
        self.repo = repo
        self.branch = branch
        self.summary_path = summary_path
        self.plan_only = plan_only
        self.plan_path = plan_path
        self.dry_run = dry_run
        self.finished: str | None = None

    # -- helpers -----------------------------------------------------------
    def _resolve(self, rel: str) -> Path:
        p = (self.repo / rel).resolve()
        if self.repo not in p.parents and p != self.repo:
            raise AgentError(f"chemin hors dépôt : {rel}")
        return p

    def _check_writable(self, rel: str) -> None:
        norm = os.path.normpath(rel).replace(os.sep, "/")
        if norm.startswith("../") or norm == "..":
            raise AgentError(f"chemin hors dépôt : {rel}")
        for deny in WRITE_DENY:
            if norm == deny or norm.startswith(deny + "/"):
                raise AgentError(f"écriture interdite sous {deny}/ : {rel}")
        if self.plan_only:
            plan_rel = self.plan_path.relative_to(self.repo).as_posix()
            if norm != plan_rel:
                raise AgentError(
                    f"phase plan : seule l'écriture de {plan_rel} est permise")

    def _git(self, *args: str) -> str:
        out = subprocess.run(
            ["git", *args], cwd=self.repo, capture_output=True, text=True)
        if out.returncode != 0:
            raise AgentError(f"git {' '.join(args)} : {out.stderr.strip()}")
        return out.stdout.strip()

    # -- outils exposés au modèle ---------------------------------------
    def read_file(self, path: str) -> str:
        p = self._resolve(path)
        if not p.is_file():
            raise AgentError(f"fichier absent : {path}")
        text = p.read_text("utf-8", "replace")
        if len(text) > READ_TRUNCATE:
            text = text[:READ_TRUNCATE] + "\n… [tronqué]"
        return text

    def list_dir(self, path: str = ".") -> str:
        p = self._resolve(path)
        if not p.is_dir():
            raise AgentError(f"répertoire absent : {path}")
        rows = []
        for entry in sorted(p.iterdir()):
            if entry.name == ".git":
                continue
            rows.append(f"{'d' if entry.is_dir() else 'f'} {entry.name}")
        return "\n".join(rows) or "(vide)"

    def run_bash(self, cmd: str) -> str:
        for pat in BASH_DENY:
            if re.search(pat, cmd):
                raise AgentError(f"commande refusée (motif {pat!r})")
        proc = subprocess.run(
            ["bash", "-lc", cmd], cwd=self.repo, capture_output=True,
            text=True, timeout=BASH_TIMEOUT)
        out = (proc.stdout or "") + (proc.stderr or "")
        if len(out) > BASH_TRUNCATE:
            out = out[:BASH_TRUNCATE] + "\n… [tronqué]"
        return f"exit={proc.returncode}\n{out}".strip()

    def write_file(self, path: str, content: str) -> str:
        self._check_writable(path)
        p = self._resolve(path)
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content, "utf-8")
        return f"écrit {path} ({len(content)} caractères)"

    def commit(self, message: str) -> str:
        if self.plan_only:
            raise AgentError("phase plan : pas de commit")
        self._git("add", "-A")
        status = self._git("status", "--porcelain")
        if not status:
            return "rien à committer"
        if self.dry_run:
            return f"[dry-run] aurait committé :\n{status}"
        self._git("commit", "-m", message)
        subprocess.run(
            ["git", "push", "origin", f"HEAD:{self.branch}"],
            cwd=self.repo, check=True)
        return f"commité et poussé : {message}"

    def finish(self, summary: str) -> str:
        self.summary_path.parent.mkdir(parents=True, exist_ok=True)
        self.summary_path.write_text(summary.strip() + "\n", "utf-8")
        self.finished = summary
        return "résumé enregistré"

    def dispatch(self, name: str, args: dict) -> str:
        fn = {
            "read_file": self.read_file,
            "list_dir": self.list_dir,
            "run_bash": self.run_bash,
            "write_file": self.write_file,
            "commit": self.commit,
            "finish": self.finish,
        }.get(name)
        if fn is None:
            raise AgentError(f"outil inconnu : {name}")
        return fn(**args)


# ------------------------------------------------------------------ prompt / boucle

TOOLS_DOC = """\
Outils disponibles (un seul appel par réponse) :
  read_file(path)              lire un fichier du dépôt
  list_dir(path)               lister un répertoire
  run_bash(cmd)                exécuter une commande shell à la racine du dépôt
  write_file(path, content)    écrire/remplacer un fichier
  commit(message)              git add -A + commit + push (phase travail seulement)
  finish(summary)              terminer en résumant ce qui a été fait

Réponds EXACTEMENT avec un bloc, et rien d'autre :

```action
{"thought": "…", "tool": "read_file", "args": {"path": "..."}}
```
"""

PLAN_INSTRUCTIONS = """\
PHASE : PLAN.
Explore le dépôt avec read_file / list_dir / run_bash (lecture seule uniquement).
Ne modifie aucun fichier du cours. Quand tu as compris la tâche, écris le plan
d'action avec write_file vers « {plan_rel} » : une liste d'étapes concrètes,
les fichiers touchés, les commandes de vérification, et tout point de blocage
(commande LaTeX sans équivalent, ambiguïté…). Termine ensuite avec finish("plan
rédigé").
"""

WORK_INSTRUCTIONS = """\
PHASE : TRAVAIL.
Voici le plan d'action validé :

{plan}

Implémente-le. Fais des commits petits et fréquents (commit(message) après
chaque étape cohérente). Vérifie ton travail avec run_bash quand c'est possible.
Ne touche pas au fond mathématique si la tâche est une migration de forme.
Quand tout est fait, appelle finish(summary) avec un résumé destiné à un
commentaire de PR (ce qui a changé, ce qui reste à vérifier à la main).
"""


GUIDES_RE = re.compile(r"<!--\s*guides?\s*:\s*([^>]+?)\s*-->", re.IGNORECASE)


def load_guides(role_text: str, guides_dir: Path | None) -> str:
    """Concatène les guides déclarés dans le rôle par `<!-- guides: a b -->`."""
    if guides_dir is None:
        return ""
    names: list[str] = []
    for m in GUIDES_RE.finditer(role_text):
        names += re.split(r"[\s,]+", m.group(1).strip())
    chunks = []
    for name in dict.fromkeys(n for n in names if n):
        path = guides_dir / f"{name}.md"
        if path.is_file():
            chunks.append(f"### Guide — {name}\n\n{path.read_text('utf-8').strip()}")
        else:
            print(f"::warning::guide introuvable : {path}")
    if not chunks:
        return ""
    return "\n\n---\nRègles communes à respecter :\n\n" + "\n\n".join(chunks)


def build_system(role_text: str, ctx: dict, guides: str = "") -> str:
    return (
        role_text.strip()
        + guides
        + "\n\n---\nContexte d'exécution :\n"
        + f"- Dépôt appelant : {ctx['repo_slug']}\n"
        + f"- Modèle : {ctx['model']}\n"
        + f"- Branche de travail : {ctx['branch']}\n"
        + f"- Issue : #{ctx['issue']}  ·  PR : #{ctx['pr']}\n"
        + f"- Tâche : {ctx['task']}\n\n---\n"
        + TOOLS_DOC
    )


ACTION_RE = re.compile(r"```(?:action|json)?\s*(\{.*?\})\s*```", re.DOTALL)


def parse_action(text: str) -> dict | None:
    m = ACTION_RE.search(text)
    blob = m.group(1) if m else None
    if blob is None:
        stripped = text.strip()
        if stripped.startswith("{") and stripped.endswith("}"):
            blob = stripped
    if blob is None:
        return None
    try:
        obj = json.loads(blob)
    except json.JSONDecodeError:
        return None
    if "tool" not in obj:
        return None
    obj.setdefault("args", {})
    return obj


def run(args: argparse.Namespace) -> int:
    api_key = os.environ.get("ALBERT_API_KEY")
    if not api_key:
        raise AgentError("ALBERT_API_KEY manquant")
    base = os.environ.get("ALBERT_BASE", DEFAULT_BASE)

    repo = Path(args.repo).resolve()
    role_text = Path(args.role).read_text("utf-8")
    plan_path = Path(args.plan).resolve()
    summary_path = Path(args.summary).resolve()
    log_dir = Path(args.log_dir).resolve()
    log_dir.mkdir(parents=True, exist_ok=True)

    ctx = {
        "repo_slug": args.repo_slug, "model": args.model, "branch": args.branch,
        "issue": args.issue, "pr": args.pr, "task": args.task,
    }
    guides_dir = Path(args.guides_dir).resolve() if args.guides_dir else None
    guides = load_guides(role_text, guides_dir)

    plan_only = args.phase == "plan"
    tools = Tools(repo, args.branch, summary_path, plan_only, plan_path,
                  args.dry_run)

    if plan_only:
        user = PLAN_INSTRUCTIONS.format(
            plan_rel=plan_path.relative_to(repo).as_posix())
    else:
        plan_text = plan_path.read_text("utf-8") if plan_path.is_file() else \
            "(plan absent — déduis les étapes de la tâche)"
        user = WORK_INSTRUCTIONS.format(plan=plan_text)

    messages = [
        {"role": "system", "content": build_system(role_text, ctx, guides)},
        {"role": "user", "content": user},
    ]

    transcript = []
    deadline = time.time() + args.max_minutes * 60
    step = 0
    while step < args.max_steps and time.time() < deadline:
        step += 1
        reply = call_model(base, api_key, args.model, messages)
        transcript.append({"step": step, "assistant": reply})
        messages.append({"role": "assistant", "content": reply})

        action = parse_action(reply)
        if action is None:
            messages.append({"role": "user", "content": (
                "Format invalide. Réponds uniquement avec un bloc ```action { … }```."
            )})
            transcript[-1]["note"] = "format invalide"
            continue

        name, a = action["tool"], action.get("args", {})
        try:
            result = tools.dispatch(name, a)
            ok = True
        except (AgentError, TypeError, subprocess.SubprocessError) as exc:
            result = f"ERREUR : {exc}"
            ok = False
        transcript[-1]["action"] = {"tool": name, "args": a, "ok": ok}
        transcript[-1]["result"] = result
        print(f"[{step}] {name}({json.dumps(a, ensure_ascii=False)[:120]}) "
              f"-> {'ok' if ok else 'erreur'}", flush=True)

        if tools.finished is not None:
            break
        messages.append({"role": "user", "content": f"Résultat de {name} :\n{result}"})

    (log_dir / f"transcript-{args.phase}-{args.run_id}.json").write_text(
        json.dumps(transcript, ensure_ascii=False, indent=2), "utf-8")

    if plan_only and not plan_path.is_file():
        raise AgentError("phase plan terminée sans fichier de plan")
    if not plan_only and tools.finished is None:
        print("::warning::phase travail terminée sans finish() — budget épuisé ?")
        tools.finish("Budget de pas épuisé avant la fin. Voir les commits et le "
                     "transcript pour l'état d'avancement.")
    return 0


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--phase", choices=("plan", "work"), required=True)
    p.add_argument("--repo", required=True, help="racine du dépôt appelant")
    p.add_argument("--role", required=True, help="fichier markdown du rôle")
    p.add_argument("--task", required=True)
    p.add_argument("--run-id", required=True)
    p.add_argument("--branch", required=True)
    p.add_argument("--plan", required=True, help="chemin du fichier de plan")
    p.add_argument("--summary", required=True, help="chemin du fichier de résumé")
    p.add_argument("--model", default="deepseek")
    p.add_argument("--repo-slug", default=os.environ.get("GITHUB_REPOSITORY", "?"))
    p.add_argument("--issue", default="?")
    p.add_argument("--pr", default="?")
    p.add_argument("--max-steps", type=int, default=40)
    p.add_argument("--max-minutes", type=int, default=25)
    p.add_argument("--log-dir", default="_agent_logs")
    p.add_argument("--guides-dir", default=None,
                   help="répertoire des guides (déclarés dans le rôle)")
    p.add_argument("--dry-run", action="store_true")
    args = p.parse_args()
    try:
        return run(args)
    except AgentError as exc:
        print(f"::error::{exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
