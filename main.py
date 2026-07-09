#!/usr/bin/env python3

# Import routes to register them with the app
from Core.routes import *

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=8000)