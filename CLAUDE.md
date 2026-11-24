# Project: AISim (Python 3.12 + venv_AISim)

Codebase map (generated once by run-tasks.ps1, kept up to date, see "Codebase awareness" below):
@CODEBASE_MAP.md

## Project facts
- Python 3.12.0. The virtual environment `venv_AISim` is already active when you run commands: use plain `python`, never a full path.
- The project root is the folder that holds this file. All paths below are relative to it.
- All your code lives in `src/`. Each folder directly under `src/` is one module (a Python package) with an `__init__.py`. `src/` itself is on the import path (PYTHONPATH), has no `__init__.py` and is not a package. Import by folder name: `from simulation.world import World`.
- Third-party code that is not on PyPI lives in `vendor/`. It is read-only for you and importable by its top-level name (`vendor/` is on PYTHONPATH). Never edit, copy or reformat it. If its behaviour must be adapted, write a small adapter class in `src/`.
- `requirements.txt` lists every package that is installed. Import only those and the standard library. You cannot install anything: no pip, uv, conda or poetry.
- If a task cannot be done without a package that is not in `requirements.txt`, stop, write no code for that task, and put this on its own line in your reply: `NEEDS_PACKAGE: <package> - <why>`.
- `ruff`, `pytest` and `mypy` exist only if they are listed in `requirements.txt`. Use the ones that exist. Never assume one is installed.
- Tests live in `src/tests/<folder>/test_<file>.py`, mirroring the module they test. Every folder under `src/tests/` has an `__init__.py`.

## Scope rules (strict)
- Do only the task you are given. No extra features, refactors, or "improvements" to code the task does not mention.
- Write Python (`.py`) code only. No config, JSON, YAML or data files unless the task asks for them.
- Never run any git command (no commit, add, stash, push, checkout, reset). The user reviews and commits the work.
- Never edit: `TASKS.md`, `CLAUDE.md`, `requirements.txt`, `pyproject.toml`, anything in `.claude/`, `vendor/` or `venv_AISim/`, and `CODEBASE_MAP.md` except to update it at the end.
- Never create or edit the virtual environment. Never run `python -m pip`, `python -m venv` or similar.
- After writing code, run the checks that exist and fix every error until they pass. Do not stop on a failing check:
  - `python -m ruff check src` (if ruff is installed)
  - `python -m pytest src -q` (if pytest is installed and tests exist)
  - `python -m mypy src --explicit-package-bases --ignore-missing-imports` only if the task or `requirements.txt` makes type checking part of the project
  - A quick import check with `python -c "import <folder>.<module>"` for every module you created or changed.
- When finished, reply with a short summary: files created or changed, and anything the user must do by hand (a package to install, a config value, an entry point to run).

## Codebase awareness
- Read `CODEBASE_MAP.md` first. It describes the modules (folders), key classes and functions, entry points and how they connect. Then open only the files the task touches.
- Before writing new code, check whether something existing already does the job (a manager, cache, logger, config class, helper). Reuse it instead of writing a near-copy.
- After adding or removing files, classes or public functions, update `CODEBASE_MAP.md` with one short line each.

## Folders, modules and files (always)
- One public class per file. The file name is the class name in snake_case (`WorldState` is `world_state.py`). A file of related pure functions is named after its topic (`geometry.py`, `text_utils.py`) and holds no classes.
- One folder per system under `src/<folder>/`, short snake_case names (`simulation`, `agents`, `world`). The task says where a file goes. Create the folder with an empty `__init__.py` if it does not exist. If the task gives no folder, use the existing folder that fits, or create one.
- `__init__.py` files stay empty (or hold only `__all__`). No logic, no imports of heavy modules, no re-export tricks.
- Always use absolute imports from the folder name (`from agents.agent_state import AgentState`). No relative imports, no `import *`, no `sys.path` changes.
- No circular imports. Dependencies point one way: low-level folders (data, utilities) never import from high-level ones (simulation loop, app entry points). If two folders need each other, move the shared part into a third, lower folder.
- No work at import time: a module only defines classes, functions and constants. No file reads, network calls, random numbers, threads or `print` when it is imported.
- Entry points (the file that is run) are the only files with `if __name__ == "__main__":`, and they only call a `main()` function.
- Never give a module the same name as a standard library module or an installed package (`random.py`, `logging.py`, `typing.py`).

## Data classes vs classes
- Pure data with no behaviour: `@dataclass(slots=True)`, or `@dataclass(frozen=True, slots=True)` when it must not change (configs, events, messages). Use `enum.Enum` or `enum.IntEnum` for fixed choices, never magic strings or numbers.
- Anything with behaviour, state management or identity: a plain class.
- No inheritance unless two or more real classes share real behaviour today. Prefer composition. No abstract base classes, protocols, metaclasses or decorators that nothing needs yet. Exception: if a task explicitly requires an abstract base class, follow the task.
- Never use mutable default arguments (`def f(x=[])`) or mutable dataclass defaults; use `field(default_factory=...)`.

## Naming and layout (always)
- Follow PEP 8. 4 spaces, lines up to 100 characters, no tabs, double quotes for strings.
- Modules and functions: `snake_case`. Classes: `PascalCase`. Constants: `UPPER_SNAKE_CASE` at module level. Parameters and locals: `snake_case`, no prefix.
- Private attributes and methods start with one underscore (`self._speed`, `_update_cell`). Public only if another class needs it. Never use name mangling (`__x`).
- Expose read access through `@property`, not `get_x()` methods and not public mutable attributes. Fields of dataclasses are public.
- Every function and method has full type hints on parameters and return value. Use modern syntax: `list[int]`, `dict[str, float]`, `X | None`, and `collections.abc` for abstract types. Avoid `Any`; if you need it, leave a short comment saying why.
- One-line docstring (`"""..."""`) on every public class and public function. A short `#` comment only where the code is not obvious. No commented-out code, no TODO comments.
- Order inside a class: class constants, `__init__`, other dunder methods, properties, public methods, private methods.
- Imports at the top in three blocks separated by a blank line: standard library, third-party, then project folders. Alphabetical inside each block. No unused imports.
- Match the style of the existing files. Do not reformat code you are not changing.

## Construction and lifecycle (always)
- Create and assign everything in `__init__`. Pass dependencies in as constructor parameters (no hidden globals, no singletons, no module-level mutable state).
- A class that owns a resource (file, thread, process, model) has an explicit `close()` or is a context manager (`__enter__` / `__exit__`). Use `with` for files and locks.
- Configuration is a frozen dataclass created once and passed in. No reading of environment variables or files deep inside logic.
- Use `pathlib.Path` for paths, never string concatenation. Open text files with `encoding="utf-8"`.
- Format floats written as text (JSON, logs, save files) explicitly, e.g. `f"{value:.6f}"`, so output is stable.

## Simulation rules (determinism and testability)
- Randomness: never call the module-level `random.*` functions. Create one `random.Random(seed)` (or `numpy.random.Generator` if numpy is in `requirements.txt`) at the top and pass it down. The same seed must give the same result.
- Time: logic never calls `time.time()`, `datetime.now()` or `sleep`. The simulation step passes in `dt` (or a tick number). Only the outermost loop and entry points touch the real clock.
- Keep simulation logic pure: no printing, no file or network access, no logging inside inner loops. Reading and writing live in separate small classes in their own folder.
- Do not iterate over a `set` or rely on `dict` ordering where order changes results; sort or use a list.

## Errors and logging
- Use the standard `logging` module: `logger = logging.getLogger(__name__)` at the top of a module (check `CODEBASE_MAP.md` first in case the project has its own logging helper). Never use `print` except in an entry point that talks to the user.
- Pass log arguments lazily: `logger.debug("moved %s to %s", agent_id, cell)`, never f-strings in log calls.
- Raise specific exceptions (`ValueError`, `KeyError`, or a small project exception class) with a clear message. Never write a bare `except:` or `except Exception: pass`. Catch only what you can handle, and at the narrowest place.
- Validate inputs at the boundary (constructors, file loading, public entry functions), not in every inner function.

## Quality and performance
- Code must be clean, simple and scalable. Prefer small focused classes and functions (a function does one thing and fits on one screen) over large ones. Avoid deep nesting; return early.
- Performance matters a lot. In hot code (the simulation step, loops over many agents or cells, per-tick handlers):
  - No allocations inside loops: do not create new lists, dicts, tuples, strings or objects per iteration if a reused buffer or a preallocated structure works.
  - Bind attributes and methods used in a loop to local variables before the loop (`append = items.append`, `speed = self._speed`).
  - Use comprehensions, generator expressions and built-ins (`sum`, `min`, `max`, `any`, `all`, `zip`) instead of manual loops where they are clearer or faster. Use `"".join(parts)`, never `+=` on strings in a loop.
  - Use the right container: `set` or `dict` for membership and lookup (never `x in some_list` on big lists), `collections.deque` for queues, `heapq` for priority queues, `bisect` for sorted data, `array` or `numpy` arrays for big numeric data.
  - If `numpy` is in `requirements.txt`, vectorise bulk numeric work instead of Python loops. If it is not, do not import it.
  - Use `__slots__` (or `@dataclass(slots=True)`) for classes with many instances.
  - Cache pure, repeatable results with `functools.cache` / `lru_cache(maxsize=...)`. Never cache methods that use mutable `self` state.
  - Do not do I/O, parsing or logging formatting inside hot loops. Load once, keep in memory.
  - Do not guess about speed. Only optimise code the task says is slow, or code that is obviously quadratic or worse. Keep the simple version otherwise.
- Heavy imports at the top of the module, except a rarely used heavy dependency, which may be imported inside the one function that needs it.
- Keep the simulation core free of I/O and framework types, so it can be tested without anything running (see tests).
- Tests: if `pytest` is installed, every new class or function with real logic gets a small test file (3 to 6 focused tests, plain `assert`, no mocks unless unavoidable, a fixed seed for anything random). Tests must run in under a second each and must not touch the network, the real clock or files outside a pytest `tmp_path`.
- Do not over-engineer: no interfaces, generics, plugin systems, factories or patterns that nothing needs yet.
- Do not introduce new ruff or mypy warnings. Do not silence a warning with `# noqa` or `# type: ignore` unless you cannot fix it, and then add a short reason.

## Example of the house style
```python
# src/agents/agent_state.py
from dataclasses import dataclass


@dataclass(slots=True)
class AgentState:
    """Position and energy of one agent."""

    x: float = 0.0
    y: float = 0.0
    energy: float = 100.0
```

```python
# src/agents/agent_mover.py
import logging
import random

from agents.agent_state import AgentState

logger = logging.getLogger(__name__)


class AgentMover:
    """Moves agents by a random step each tick."""

    DEFAULT_SPEED = 1.0

    def __init__(self, rng: random.Random, speed: float = DEFAULT_SPEED) -> None:
        if speed <= 0:
            raise ValueError("speed must be positive")
        self._rng = rng
        self._speed = speed

    @property
    def speed(self) -> float:
        return self._speed

    def step(self, agents: list[AgentState], dt: float) -> None:
        """Move every agent one step of length speed * dt."""
        uniform = self._rng.uniform
        distance = self._speed * dt
        for agent in agents:
            agent.x += uniform(-1.0, 1.0) * distance
            agent.y += uniform(-1.0, 1.0) * distance
        logger.debug("moved %d agents", len(agents))
```
