from fastapi import FastAPI, Request
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse

app = FastAPI(title="Blueprint UI Backend")


@app.get("/")
async def index():
    return FileResponse("static/index.html")


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


# Serve the vendored litegraph.js fork (from the git submodule) directly,
# so the browser loads it locally instead of from a CDN.
import os
if os.path.isdir("vendor/litegraph"):
    app.mount("/litegraph-assets", StaticFiles(directory="vendor/litegraph"), name="litegraph-assets")
else:
    print("WARNING: vendor/litegraph not found. Run setup.sh / setup.bat "
          "(or 'git submodule update --init --recursive') first.")

# Mount static files last so it doesn't shadow the API routes above
app.mount("/static", StaticFiles(directory="static"), name="static")

