import os

from fastapi import FastAPI, Request
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse

# Anchor all paths to this file's location, so things work no matter
# what directory you launch from.
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
STATIC_DIR = os.path.join(BASE_DIR, "static")
LITEGRAPH_DIR = os.path.join(BASE_DIR, "vendor", "litegraph")
DRAWFLOW_DIR = os.path.join(BASE_DIR, "vendor", "drawflow")

app = FastAPI(title="Blueprint UI Backend")


@app.get("/")
async def index():
    return FileResponse(os.path.join(STATIC_DIR, "index.html"))


@app.get("/drawflow")
async def drawflow_index():
    return FileResponse(os.path.join(STATIC_DIR, "drawflow.html"))


@app.post("/api/graph")
async def receive_graph(request: Request):
    """
    Receives the serialized litegraph graph (nodes, links, etc. as JSON)
    whenever the user clicks "Run Graph" in the browser.

    This is where YOU add your own logic: walk the nodes, figure out
    execution order from the links, and do whatever your app needs to do.
    """
    graph_data = await request.json()

    nodes = graph_data.get("nodes", [])
    links = graph_data.get("links", [])

    # --- Your custom logic goes here ---
    print(f"Received graph with {len(nodes)} nodes and {len(links)} links")
    for node in nodes:
        print(f"  Node: id={node.get('id')} type={node.get('type')} title={node.get('title')}")

    return {
        "status": "ok",
        "node_count": len(nodes),
        "link_count": len(links),
    }


@app.post("/api/graph-drawflow")
async def receive_drawflow_graph(request: Request):
    """
    Receives Drawflow's editor.export() JSON, which looks like:
    { "drawflow": { "Home": { "data": { "<node_id>": {...}, ... } } } }
    (different shape than litegraph's, since it's keyed by node id
    rather than a flat "nodes" array.)

    This is where YOU add your own logic for the Drawflow graph.
    """
    export_data = await request.json()

    home_data = (
        export_data.get("drawflow", {})
        .get("Home", {})
        .get("data", {})
    )

    print(f"Received drawflow graph with {len(home_data)} nodes")
    for node_id, node in home_data.items():
        print(f"  Node: id={node_id} name={node.get('name')} pos=({node.get('pos_x')}, {node.get('pos_y')})")

    return {
        "status": "ok",
        "node_count": len(home_data),
    }


# Serve the vendored litegraph.js fork (from the git submodule) directly,
# so the browser loads it locally instead of from a CDN.
if os.path.isdir(LITEGRAPH_DIR):
    app.mount("/litegraph-assets", StaticFiles(directory=LITEGRAPH_DIR), name="litegraph-assets")
else:
    print(f"WARNING: {LITEGRAPH_DIR} not found. Run setup.sh / setup.bat "
          "(or 'git submodule update --init --recursive') first.")

# Serve the vendored Drawflow fork the same way.
if os.path.isdir(DRAWFLOW_DIR):
    app.mount("/drawflow-assets", StaticFiles(directory=DRAWFLOW_DIR), name="drawflow-assets")
else:
    print(f"WARNING: {DRAWFLOW_DIR} not found. Run "
          "'git submodule update --init --recursive' first.")

# Mount static files last so it doesn't shadow the API routes above
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")

