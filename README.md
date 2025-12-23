# KServe VS Code Workspace

A batteries-included development environment for KServe on OpenShift. Clone, install extensions, and start coding -- debugging, testing, formatting, and cluster management are all pre-configured.

## Features

* **Go intellisense** - Code completion, signature help, go-to-definition, and refactoring via the Go extension
* **Python intellisense** - Cursorpyright with type checking, auto-imports, and code navigation
* **Test Explorer integration** - E2E and unit tests discoverable in the Test Explorer with results display
* **Debug configurations** - Pre-configured launch configs for e2e tests and remote debugging via devspace
* **Formatters and linters** - Black formatter, Flake8 linting, and ShellCheck for shell scripts
* **Kubernetes tooling** - Cluster exploration, manifest editing, and resource management
* **YAML support** - Schema validation and autocompletion for Kubernetes manifests
* **Task automation** - One-click tasks for common workflows:
  - E2E test setup/teardown and namespace recreation
  - Devspace Dev for remote controller debugging
  - CRC Refresh to restart OpenShift Local
  - Pull Secret installation for private registries
  - ODH/RHOAI operator installation
  - DSCI + DSC application
  - HuggingFace token secret creation
  - Open OpenShift Console in browser

## Prereqs

Install all tools required for development. Make sure they are available in your PATH including for non-interactive shells (i.e. add bin dirs to `~/.zshenv`).

Non-exhaustive list of tools:
* Cursor or VS Code
* oc
* kubectl
* crc (OpenShift Local)
* golang
* dlv
* python3.11
* uv
* openssl
* podman
* yq
* jq
* envsubst (gettext)
* devspace
* ko
* A web browser (set `$BROWSER`, defaults to `brave-browser`)

The following variables must be available in your env for non-interactive shells (i.e. `~/.zshenv` or `~/.profile`):
```sh
QUAY_USERNAME=yourname
QUAY_PASSWORD=abcdefg
QUAY_REPO=quay.io/reponame
KO_DOCKER_REPO=${QUAY_REPO}
RUNNING_LOCAL=true
GITHUB_SHA=master
ENGINE=podman
BUILDER=${ENGINE}
HF_TOKEN=hf_abcdefg  # HuggingFace token for private model access
BROWSER=firefox  # optional, defaults to brave-browser
```

Use `podman login` to log in to docker and quay. Afterward, your credentials should be stored in `~/.config/containers/auth.json`:
```json
{
    "auths": {
        "docker.io": {
            "auth": "abcdefg"
        },
        "quay.io": {
            "auth": "abcdefg"
        }
    }
}
```

## Setup

1. Clone this repository into your kserve repository at the root, named as .vscode:
    ```sh
    cd kserve
    git clone git@github.com:jlost/kserve-workspace.git .vscode
    ```
    You should now have a .vscode directory at the root of the kserve repository.
2. Make sure the python venv is set up:
    ```sh
    cd python/kserve
    uv sync --group test --group dev
    ```
3. Start vs code
    ```sh
    cd ../..
    code .
    ```
4. Once VS Code has loaded, press `F1` and type **'show recommended extensions'**. Press `ENTER`. Install all of the workspace recommendations.

## FAQ

**Q: pytest keeps running in the background after I click Stop. How do I actually stop it?**

Always run e2e tests in debug mode. When you click stop in debug mode, the process will actually stop.

**Q: Software Catalog shows up instead of OperatorHub in OpenShift Local. How do I install operators?**

Operators are still available and can be listed with `oc get packagemanifests` and installed by creating Subscriptions. Use the "Install ODH Operator" or "Install RHOAI Operator" tasks to install operators.

**Q: I'm getting ImagePullBackOff errors. How do I fix this?**

Run the "Install Pull Secret" task to inject your docker and quay credentials.

## Contributions

Contributions welcome! Fork and submit a pull request.

Make a best effort to fashion contributions to be as environment-agnostic as possible and document exceptions in [Prereqs](README.md#prereqs).