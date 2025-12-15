# Kserve VS Code Workspace

Prereqs: Install all tools such as kubectl, oc, golang, python, uv, openssl, etc. Make sure they are available in your PATH including for non-interactive shells (i.e. add bin dirs to ~/.zshenv).

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
    uv sync --group test --group dev
    ```
3. Start vs code
    ```
    cd ../..
    code .
    ```
4. Once VS Code has loaded, press F1 and type 'show recommended extensions'. Press ENTER. Install all of the workspace recommendations.