# Modular AI Simulation Engine

A generic, domain-agnostic simulation engine in Python that bridges deterministic world mechanics (**Mesa**) with data contract validation (**Pydantic**) and cognitive decision-making (**LLMs**).

The engine is completely decoupled from domain logic. By implementing scenario adapters, you can simulate virtually any multi-agent system—ranging from economic micro-markets and socio-cultural decisions to physical queueing, traffic networks, or emergency evacuations.

---

## 🏗 Architecture Overview

The simulation engine uses a **hybrid cognitive-deterministic architecture**:

* **Deterministic Physics & Rules:** Physics, collisions, pathing, time progression, and strict physical constraints are handled deterministically in fast local code.
* **Cognitive Decision Layer:** Large Language Models (LLMs) operate strictly at strategic decision nodes, evaluating agent observations, personas, culture, and goals to select structured actions.
* **Scenario Adapters:** Scenario-specific logic (world state, observation building, action validation) is cleanly separated from the core execution loop.

```
+-----------------------------------------------------------------------+
|                         Core Simulation Loop                          |
|                             (Mesa Model)                              |
+-----------------------------------+-----------------------------------+
                                    |
            +-----------------------+-----------------------+
            |                                               |
            v                                               v
+-----------------------+                       +-----------------------+
|  Scenario Adapter     |                       |    Agent Scheduler    |
| (Domain Rules/Space)  |                       |  (Universal Agents)   |
+-----------+-----------+                       +-----------+-----------+
            |                                               |
            | Observation Context                           | Decision Prompt
            v                                               v
+-----------------------+                       +-----------------------+
|   Pydantic Schemas    |                       |    LLM Decision Engine|
| (Validation & State)  |<======================| (Structured Output API) |
+-----------------------+     Agent Action      +-----------------------+
```

---

## 🛠 Tech Stack

| Component | Tool / Library | Role & Purpose |
| :--- | :--- | :--- |
| **Engine Skeleton** | [Mesa 3.x](https://github.com/mesa/mesa) | Agent containers, time scheduler, spatial grids/networks, telemetry, and browser UI. |
| **Data Contracts** | [Pydantic v2](https://docs.pydantic.dev/) | Validates scenario configs, agent attributes, state transitions, and structured LLM JSON outputs. |
| **Cognitive Engine** | Standard LLM SDK / Ollama | Generates context-aware, persona-driven decisions and choices. |
| **Graph Topology** | [NetworkX](https://networkx.org/) *(Optional)* | Models room-to-corridor networks, street intersections, transit nodes, and pathfinding. |
| **Queue Subsystems** | [SimPy](https://simpy.readthedocs.io/) *(Optional)* | Process-based discrete event queues for bottlenecked service points (e.g., checkout lines, security screening). |

---

## 🔌 Scenario Extensibility

This engine is **100% scenario-neutral**. The repository includes three illustrative baseline examples demonstrating different engine capabilities:

1. **Commercial Location Choice (e.g., Downtown Halal Burger):** Demonstrates socio-cultural agent reasoning, dietary preferences, price sensitivity, and marketing visibility with minimal spatial constraints.
2. **Discrete Spatial Bottlenecks (e.g., Airplane Passenger Boarding):** Demonstrates 2D spatial grid collision, row blocking, overhead stowing delays, and aisle queue physics.
3. **Emergency Hazards (e.g., Multi-Story Building Evacuation):** Demonstrates dynamic graph/grid re-routing, panic dynamics, hazard propagation, and exit throughput.

To build **your own custom scenario**, simply inherit from `BaseScenarioAdapter` and define your own Pydantic action/state models without touching the core engine execution loop.

---

## 🐍 Core Architecture Code

Below is the minimal contract for the scenario-agnostic engine:

```python
from abc import ABC, abstractmethod
from pydantic import BaseModel, Field
from typing import Any, Dict, List, Optional
import mesa

# 1. Base Scenario Adapter Interface (Inherit this for ANY custom scenario)
class BaseScenarioAdapter(ABC):
    @abstractmethod
    def build_observation(self, agent: mesa.Agent, model: mesa.Model) -> Dict[str, Any]:
        """Construct what an agent can see or know in this specific scenario."""
        pass

    @abstractmethod
    def apply_action(self, agent: mesa.Agent, action: BaseModel, model: mesa.Model) -> None:
        """Enforce domain rules, spatial constraints, and state transitions."""
        pass

    @abstractmethod
    def advance_environment(self, model: mesa.Model) -> None:
        """Update environmental timers, hazards, queues, or global state."""
        pass

# 2. Generic Pydantic Action Contract for LLM Structured Outputs
class GenericAgentAction(BaseModel):
    action_type: str = Field(description="Generic action category defined by the scenario adapter")
    target_id: Optional[str] = Field(default=None, description="Target node, entity, or coordinate ID")
    payload: Dict[str, Any] = Field(default_factory=dict, description="Arbitrary action parameters")
    reasoning: str = Field(description="Cognitive rationale for telemetry, analytics, and replays")

# 3. Universal Engine Agent
class UniversalSimulationAgent(mesa.Agent):
    def __init__(self, model: mesa.Model, persona: Dict[str, Any]):
        super().__init__(model)
        self.persona = persona
        self.state: Dict[str, Any] = {}

    def step(self):
        observation = self.model.adapter.build_observation(self, self.model)
        action = self.decide(observation)
        self.model.adapter.apply_action(self, action, self.model)

    def decide(self, observation: Dict[str, Any]) -> GenericAgentAction:
        # Calls configured LLM or local fallback runner using response_format=GenericAgentAction
        return GenericAgentAction(
            action_type="interact",
            target_id=observation.get("default_target"),
            reasoning="Action selected based on current agent persona and local observation."
        )

# 4. Core Engine Model Loop
class CoreSimulationEngine(mesa.Model):
    def __init__(self, scenario_adapter: BaseScenarioAdapter, agent_configs: List[Dict[str, Any]]):
        super().__init__()
        self.adapter = scenario_adapter
        for cfg in agent_configs:
            agent = UniversalSimulationAgent(self, cfg)
            self.agents.add(agent)

    def step(self):
        self.agents.do("step")
        self.adapter.advance_environment(self)
```

---

## 🚀 Quick Start & Installation

### 1. Clone Repository & Submodules
```bash
git clone https://github.com/your-username/your-repo-name.git
cd your-repo-name

# If Mesa is vendor-included as a submodule:
git submodule update --init --recursive
```

### 2. Set Up Python Environment
```bash
python -m venv venv_AISim
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies in editable mode
pip install -e "./vendor/mesa[rec]"
pip install pydantic
```

---

## 🗺 Development Roadmap

* [x] **Phase 1: Foundation Engine:** Core `Mesa` model loop, generic `UniversalSimulationAgent`, and abstract `BaseScenarioAdapter` interface.
* [ ] **Phase 2: Structured Decision & Caching:** Implement Pydantic LLM action parsing, local model fallback, and decision caching for redundant agent personas.
* [ ] **Phase 3: Spatial & Network Adapters:** Add grid physics, continuous collision spaces, and NetworkX topological routing support.
* [ ] **Phase 4: Telemetry & Visualization:** Integrate `SolaraViz` for real-time web UI simulation replay and export structured JSON metrics.

---

## 📄 License
Distributed under the MIT License. See `LICENSE` for more information.