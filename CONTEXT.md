# Project Context

## What this is
A Python-based simulation system built around Drawflow. Users build a flow
graph visually (nodes + connections) in the Drawflow editor, then trigger a
simulation that walks the graph from a start node, flows through connected
nodes according to their logic, and finishes at an end node.

## Architecture
High-level shape — fill in/adjust as the structure solidifies:

- `vendor/drawflow/` — third-party Drawflow library (JS/CSS for the node-graph
  editor), used as our frontend. Prefer extending/configuring it from our own
  code rather than editing vendor files, but direct edits here are allowed
  when actually needed (e.g. a behavior isn't reachable any other way). If you
  do edit vendor files, leave a short note in "Key decisions" or "Gotchas"
  below explaining what was changed and why, so it doesn't get silently
  overwritten or mistaken for a bug.
- Backend (Python) — owns simulation logic: graph parsing, node execution,
  simulation state/stepping, and (if applicable) serving the frontend.
- Frontend (HTML/CSS/JS) — hosts the Drawflow canvas, lets the user build the
  graph, and sends the graph definition to the backend (or runs simulation
  client-side — clarify once decided).
- Data flow: user builds graph in Drawflow -> graph exported as JSON ->
  backend/simulation engine consumes it -> simulation executes node-by-node
  from start to end -> results/state surfaced back to the UI.

_Update this section once the module/folder layout is real — e.g. where
`main.py`, node definitions, and simulation engine code actually live._

## Conventions
- Python: clean, simple, scalable over clever. Prefer straightforward
  functions/classes over premature abstraction.
- Keep simulation logic (Python) decoupled from Drawflow rendering (JS) —
  the graph JSON exported by Drawflow is the contract between them.
- Editing `vendor/drawflow/` directly is fine when needed — it's our
  frontend, not a locked black box. Default to config/extension points or a
  thin wrapper when that's enough, but don't avoid a direct edit just
  because it's "vendor" code if that's the simplest correct fix.
- Never run `pip install` (or similar) directly. If a new dependency is
  needed, add it to `requirements.txt` (with a version pin if it matters)
  and tell me what was added and why — I'll install it myself.
- New files should go in a sensible module (e.g. `simulation/`, `nodes/`,
  `static/` or `frontend/`) rather than the project root — propose a
  structure early and stick to it.

## Key decisions
- (empty — log decisions here as they're made, e.g. "chose to represent
  each node type as a Python class with a `run()` method because...")

## Current state / in progress
- Project is early-stage: Drawflow is vendored in, simulation engine and
  node-type system not yet built out.
- Basic FastAPI + Drawflow scaffold now exists with:
  - main.py serving the Drawflow editor at /
  - Static file serving for Drawflow assets from vendor/drawflow/dist
  - Simple HTML page with basic nodes and connections
  - Can be run directly with `python main.py` on http://127.0.0.1:8000

## Gotchas
- 
