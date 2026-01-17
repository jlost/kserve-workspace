# KServe Development Workflow

This document describes the different development paths available via VS Code tasks.

## Workflow Diagram

```mermaid
flowchart TB
    subgraph start["🎯 Choose Platform"]
        A{{"Select Environment"}}
    end

    %% ============================================================
    %% KIND / UPSTREAM PATH (Yellow)
    %% ============================================================
    subgraph kind["☸️ KIND / UPSTREAM (Local Kubernetes)"]
        direction TB
        K1["🔄 Kind Refresh<br/><i>Delete & recreate Kind cluster</i>"]
        K2["📦 Install KServe Dependencies<br/><i>cert-manager, Knative/KEDA</i>"]
        K2b["🌐 Install Network Dependencies<br/><i>Istio, Gateway API</i>"]
        K3["🚀 Clean Deploy KServe<br/><i>make undeploy-dev; make deploy-dev</i>"]
        K4["⚙️ Patch Deployment Mode<br/><i>Knative or Standard</i>"]
        K5["🔄 Recreate E2E ns (upstream)<br/><i>kserve-ci-e2e-test</i>"]
        K6["▶️ Setup E2E + Port Forward<br/><i>Create ns + port-forward 8080:80</i>"]
        
        K1 --> K2
        K2 --> K2b
        K2b --> K3
        K3 --> K4
        K4 --> K5
        K5 --> K6
    end

    %% ============================================================
    %% OPENSHIFT PATH (Red)
    %% ============================================================
    subgraph ocp["🔴 OPENSHIFT / ODH / RHOAI"]
        direction TB
        O1["🖥️ CRC Refresh<br/><i>Start/refresh CRC cluster</i>"]
        O2["🔑 Pull Secret<br/><i>Configure RH registry access</i>"]
        
        subgraph manual["Manual Repro Path"]
            O3["☁️ Install ODH/RHOAI Operator<br/><i>From OperatorHub</i>"]
            O4["🔧 Apply DSCI + DSC<br/><i>DataScienceCluster CRs</i>"]
        end
        
        subgraph e2e["E2E Tests Path"]
            O5["⚙️ Setup E2E<br/><i>OpenShift E2E environment</i>"]
            O6["🔄 Recreate E2E ns<br/><i>setup-ci-namespace.sh</i>"]
        end
        
        O7["🌐 Open Console<br/><i>OpenShift web console</i>"]
        O8["🔌 Fix Dashboard Route<br/><i>CRC passthrough route</i>"]
        O9["🗑️ Teardown E2E<br/><i>Clean up E2E setup</i>"]
        
        O1 --> O2
        O2 --> O3
        O2 --> O5
        O3 --> O4
        O5 --> O6
        O4 -.-> O7
        O4 -.-> O8
        O6 -.-> O9
    end

    %% ============================================================
    %% DEVELOPMENT TOOLS (Green - Platform Agnostic)
    %% ============================================================
    subgraph dev["🟢 DEVELOPMENT TOOLS (Platform Agnostic)"]
        direction TB
        D1["☕ Devspace Dev<br/><i>Live controller development</i>"]
        D2["🔐 Create HF Token Secret<br/><i>HuggingFace access</i>"]
        D3["📦 Setup Dev Environment<br/><i>Python venv + deps</i>"]
        D4["👁️ Watch Resource Status<br/><i>deployments, pods, isvc...</i>"]
        D5["📋 Watch Controller Logs<br/><i>kserve-controller-manager</i>"]
    end

    %% ============================================================
    %% END GOALS
    %% ============================================================
    subgraph goals["🎯 Common Scenarios"]
        direction TB
        G1["🧪 Run E2E Tests<br/><i>pytest with markers</i>"]
        G2["🔍 Manual Reproduction<br/><i>Apply ISVC, observe behavior</i>"]
        G3["🐛 Debugging<br/><i>Devspace + logs + watches</i>"]
    end

    %% Connections
    A -->|"Local Dev<br/>Upstream Testing"| K1
    A -->|"ODH/RHOAI<br/>OpenShift Testing"| O1

    K6 --> G1
    K6 --> G2
    O6 --> G1
    O6 --> G2

    %% Development tools connect to both paths
    K3 -.-> D1
    K6 -.-> D4
    K6 -.-> D5
    K6 -.-> D2
    O4 -.-> D1
    O6 -.-> D4
    O6 -.-> D5
    O6 -.-> D2

    D1 --> G3
    D4 --> G3
    D5 --> G3

    D3 -.->|"Auto on folder open"| G1

    %% Styling
    classDef kindStyle fill:#fff3cd,stroke:#ffc107,stroke-width:2px,color:#000
    classDef ocpStyle fill:#f8d7da,stroke:#dc3545,stroke-width:2px,color:#000
    classDef devStyle fill:#d4edda,stroke:#28a745,stroke-width:2px,color:#000
    classDef goalStyle fill:#cce5ff,stroke:#004085,stroke-width:2px,color:#000
    classDef startStyle fill:#e2e3e5,stroke:#6c757d,stroke-width:2px,color:#000

    class K1,K2,K2b,K3,K4,K5,K6 kindStyle
    class O1,O2,O3,O4,O5,O6,O7,O8,O9 ocpStyle
    class D1,D2,D3,D4,D5 devStyle
    class G1,G2,G3 goalStyle
    class A startStyle
```

## Path Descriptions

### 🟡 KIND / Upstream Path (Local Kubernetes)

**Sequence:**
```
Kind Refresh -> Install Dependencies -> Install Network -> Deploy KServe -> Patch Mode -> E2E ns -> Port Forward
```

**Use when:**
- Testing upstream KServe changes
- Local development without OpenShift
- CI-like testing environment
- Quick iteration on controller code

**Tasks:**
| Task | Statusbar Label | Description |
|------|-----------------|-------------|
| Kind Refresh | `kind` | Delete and recreate Kind cluster |
| Install KServe Dependencies | `deps` | Install cert-manager, Knative or KEDA (based on deployment mode) |
| Install Network Dependencies | `network` | Install Istio, Gateway API (Istio or Envoy) |
| Clean Deploy KServe | `deploy` | `make undeploy-dev; make deploy-dev` with Gateway config |
| Patch Deployment Mode | `mode` | Set Knative or Standard mode (auto-detects if not specified) |
| Recreate E2E ns (upstream) | `e2e ns` | Create `kserve-ci-e2e-test` namespace |
| Setup E2E + Port Forward | `e2e+fwd` | Create ns + port-forward to Istio gateway |

**Deployment Mode Options:**

When running "Install KServe Dependencies", select the deployment mode:
| Option | Description |
|--------|-------------|
| Knative (serverless) | Install Knative Serving for serverless deployments |
| Standard (raw deployment) | Skip Knative, use raw Kubernetes deployments |

Optionally install KEDA for autoscaling with Standard mode.

**Network Layer Options:**

When running "Install Network Dependencies", select the network layer:
| Option | Description |
|--------|-------------|
| Istio Ingress (default) | Standard Istio ingress gateway |
| Istio + Gateway API | Istio with Kubernetes Gateway API |
| Envoy + Gateway API | Envoy Gateway with Kubernetes Gateway API |

When running "Clean Deploy KServe", select the matching gateway config:
| Option | Use When |
|--------|----------|
| None (Istio Ingress) | Selected "Istio Ingress" for network dependencies |
| Istio Gateway API | Selected "Istio + Gateway API" for network dependencies |
| Envoy Gateway API | Selected "Envoy + Gateway API" for network dependencies |

---

### 🔴 OpenShift / ODH / RHOAI Path

**Sequence:**
```
CRC Refresh -> Pull Secret -> [Choose Path]
                              |
                              +-> Manual Repro: Install Operator -> Apply DSCI+DSC
                              |
                              +-> E2E Tests: Setup E2E -> Recreate E2E ns
```

**Use when:**
- Testing ODH/RHOAI integration
- OpenShift-specific features (routes, ServiceMesh)
- Downstream validation before cherry-picks
- Reproducing customer issues on OpenShift

**Common Setup Tasks:**
| Task | Statusbar Label | Description |
|------|-----------------|-------------|
| CRC Refresh | `crc` | Start or refresh CRC OpenShift cluster |
| Pull Secret | `pull secret` | Configure Red Hat registry access |

**Manual Repro Path** (for manual testing/reproduction):
| Task | Statusbar Label | Description |
|------|-----------------|-------------|
| Install ODH/RHOAI Operator | `operator` | Install from OperatorHub (ODH or RHOAI) |
| Apply DSCI + DSC | `dsci+dsc` | Apply DataScienceCluster CRs |

**E2E Tests Path** (for running pytest E2E tests):
| Task | Statusbar Label | Description |
|------|-----------------|-------------|
| Setup E2E | `e2e setup` | Setup E2E test environment (installs operator, applies CRs) |
| Recreate E2E ns | `e2e ns` | Delete and recreate test namespace |

**Optional Tasks:**
| Task | Statusbar Label | Description |
|------|-----------------|-------------|
| Open OpenShift Console | `console` | Open web console in browser |
| Fix ODH Dashboard Route | `fix route` | Create passthrough route (CRC workaround) |
| Teardown E2E | `e2e teardown` | Clean up E2E environment |

---

### 🟢 Development Tools (Platform Agnostic)

These tools work with both Kind and OpenShift clusters.

| Task | Statusbar Label | Description |
|------|-----------------|-------------|
| Devspace Dev | `devspace` | Live controller development with hot reload |
| Create HF Token Secret | `hf secret` | Create HuggingFace token for model access |
| Setup Dev Environment | `setup py` | Python venv + dependencies (auto-runs on folder open) |
| Watch Resource Status | `watch` | Monitor deployments, pods, ISVC status |
| Watch KServe Controller Logs | `logs` | Stream kserve-controller-manager logs |

---

## Common Scenarios

### 🧪 Running E2E Tests

**From Kind:**
1. Complete Kind setup through "Setup E2E + Port Forward"
2. Run pytest: `pytest test/e2e/ -m predictor`

**From OpenShift:**
1. Complete E2E Tests Path: CRC Refresh -> Pull Secret -> Setup E2E -> Recreate E2E ns
2. Run pytest: `pytest test/e2e/ -m predictor`

**Available Markers:**
| Marker | Kind | OpenShift | Description |
|--------|:----:|:---------:|-------------|
| `predictor` | ✅ | ✅ | Basic predictor tests |
| `kserve_on_openshift` | ❌ | ✅ | OpenShift-specific tests |
| `graph` | ✅ | ✅ | Inference graph tests |
| `path_based_routing` | ✅ | ✅ | Path-based routing tests |
| `batcher` | ✅ | ✅ | Request batching tests |
| `explainer` | ✅ | ✅ | Model explainer tests |
| `transformer` | ✅ | ✅ | Transformer tests |

---

### 🔍 Manual Reproduction

**Kind workflow:**
1. Setup cluster and port forward
2. Apply InferenceService: `kubectl apply -f my-isvc.yaml -n kserve-ci-e2e-test`
3. Test via localhost: `curl localhost:8080/v1/models/my-model:predict -d @input.json`
4. Watch logs and resources using dev tools

**OpenShift workflow:**
1. Setup cluster with operator
2. Apply InferenceService to test namespace
3. Get route: `oc get routes -n <namespace>`
4. Test via route URL
5. Use OpenShift console for monitoring

---

### 🐛 Debugging

**Live Development with Devspace:**
1. Deploy KServe normally first
2. Run "Devspace Dev" task
3. Edit controller code - changes sync automatically
4. Use "Watch Controller Logs" to see output

**Log Analysis:**
1. "Watch KServe Controller Logs" - stream live logs
2. "Watch Resource Status" - monitor resource changes
3. Check events: `kubectl get events -n <namespace> --sort-by='.lastTimestamp'`

**Debug Launch Configurations:**
See `launch.json` for debugger configurations targeting the controller.

---

## Task Color Coding (Statusbar)

| Background Color | Meaning |
|-----------------|---------|
| 🟡 Yellow (warning) | Kind/Upstream tasks |
| 🔴 Red (error) | OpenShift tasks |
| 🟢 Green (default) | Platform-agnostic dev tools |

---

## Quick Start Cheatsheets

### Kind: Zero to E2E Tests
```bash
# Via tasks (Ctrl+Shift+P -> Tasks: Run Task)
1. Kind Refresh
2. Install KServe Dependencies
   - Deployment mode: Knative or Standard
   - Install KEDA: No (or Yes for autoscaling with Standard)
3. Install Network Dependencies
   - Network layer: Istio (default), Istio+GatewayAPI, or Envoy+GatewayAPI
4. Clean Deploy KServe
   - Gateway network layer: Match your network layer selection (None/Istio/Envoy)
5. Patch Deployment Mode
6. Setup E2E + Port Forward
7. pytest test/e2e/ -m predictor
```

### Kind: Gateway API Setup (Raw Deployment)
```bash
# For testing with Envoy Gateway API (matches CI test-raw job)
1. Kind Refresh
2. Install KServe Dependencies
   - Deployment mode: Standard (raw deployment)
   - Install KEDA: No (or Yes for autoscaling)
3. Install Network Dependencies
   - Network layer: Envoy + Gateway API
4. Clean Deploy KServe
   - Gateway network layer: Envoy Gateway API
5. Patch Deployment Mode (auto-detects Standard)
6. Setup E2E + Port Forward
7. pytest test/e2e/ -m raw
```

### OpenShift: Manual Repro
```bash
# Via tasks (Ctrl+Shift+P -> Tasks: Run Task)
1. CRC Refresh
2. Pull Secret
3. Install ODH/RHOAI Operator
4. Apply DSCI + DSC
# Ready for manual testing - apply your ISVC, check routes, etc.
```

### OpenShift: E2E Tests
```bash
# Via tasks (Ctrl+Shift+P -> Tasks: Run Task)
1. CRC Refresh
2. Pull Secret
3. Setup E2E (select marker)
4. Recreate E2E ns
# Ready for pytest
```

### Quick Controller Iteration
```bash
# After initial cluster setup (Kind Refresh + Dependencies + Network + Deploy)
1. Make code changes
2. Clean Deploy KServe (or Devspace Dev for hot reload)
3. Watch Controller Logs
4. Apply test resources
5. Watch Resource Status
```

