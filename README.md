# Kserve VS Code Workspace

Prereqs: Install all tools such as kubectl, oc, golang, python, uv, etc.

VS Code (or cursor) must be installed and available in your PATH.

Currently the config is tightly toupled to `zsh`. If you are using a different shell, adapt `settings.json` accordingly.

1. Clone this repository into your kserve repository at the root:
    ```
    cd kserve
    git clone git@github.com:jlost/kserve-workspace.git .vscode
    ```
    You should now have a .vscode directory at the root of the kserve repository.
2. Make sure the python venv is set up:
    ```
    cd python/kserve
    uv sync
    ```
3. Start vs code
    ```
    cd ../..
    code .
    ```
    If prompted to install recommended extensions, install them.
