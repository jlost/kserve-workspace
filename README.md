# 🚀 KServe VS Code Workspace

A batteries-included development environment for KServe on OpenShift. Clone, install extensions, and start coding -- debugging, testing, formatting, and cluster management are all pre-configured.

<a href="https://github.com/user-attachments/assets/010e60a2-dc4a-43ea-9264-ba0720732824">
  <img src="https://github.com/user-attachments/assets/010e60a2-dc4a-43ea-9264-ba0720732824" alt="VS Code workspace screenshot" width="400" align="right">
</a>

## ✨ Features

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

## 📋 Prereqs

All prereqs (required tools + environment variables) are documented in [Setup -> Install Development Tools -> Manual Setup](#manual-setup).

## 🛠️ Setup

### 1. 📦 Clone Workspace Configuration

Clone this repository into your kserve repository at the root, named as `.vscode`:

```sh
cd kserve
git clone git@github.com:jlost/kserve-workspace.git .vscode
```

You should now have a `.vscode` directory at the root of the kserve repository.

### 2. 🔨 Install Development Tools

#### 🤖 Automated Setup (Fedora Only)

For Fedora users, automated setup scripts are available in `.vscode/`:

**Note**: These scripts are Fedora-specific and assume zsh as your default shell. If you prefer a different shell or have already set up tools manually, use [Manual Setup](#manual-setup) instead.

1. **Install Development Dependencies**:
   ```sh
   ./.vscode/install-fedora-deps.sh
   ```

2. **Configure Environment Variables**:
   ```sh
   ./.vscode/setup-env.sh
   ```

#### 📝 Manual Setup

1. Install the required tools using your system's package manager or preferred installation method. All tools must be available in your `PATH` including for non-interactive shells (i.e. add bin dirs to `~/.zshenv`, `~/.bashrc`, or `~/.profile` depending on your shell).

   ##### 🔧 Required Tools

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

2. Configure environment variables by adding them to your shell's configuration file (`~/.zshenv`, `~/.bashrc`, or `~/.profile` depending on your shell).

   ##### 🔑 Required Environment Variables

   The following variables must be available in your env for non-interactive shells:

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

### 3. 🔐 Log in to Container Registries

Use `podman login` to log in to docker and quay:

```sh
podman login --authfile "$HOME/.config/containers/auth.json" docker.io
podman login --authfile "$HOME/.config/containers/auth.json" quay.io
```

Your credentials will be stored in `~/.config/containers/auth.json`:
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

Some tools (e.g., `ko`) expect Docker's config at `~/.docker/config.json`. Since both files use the same format, create a symlink using an absolute path:

```sh
mkdir -p ~/.docker
ln -s "$HOME/.config/containers/auth.json" ~/.docker/config.json
```

**Note:** The symlink target must be an absolute path. Verify with `ls -la ~/.docker/config.json` - it should show the full path (e.g., `/home/user/.config/containers/auth.json`), not a relative path.

### 4. 🐍 Set Up Python Environment

Make sure the python venv is set up:

```sh
cd python/kserve
uv sync --group test --group dev
```

### 5. 💻 Start VS Code and Install Extensions

Start VS Code:

```sh
cd ../..
code .
```

Once VS Code has loaded, press `F1` and type **'show recommended extensions'**. Press `ENTER`. Install all of the workspace recommendations.

## 🎯 Optional Steps

These steps are not required but can improve your development experience.

### 📄 Create a Global Gitignore

A global gitignore prevents common development artifacts from cluttering `git status` across all your projects. Create one at `~/.gitignore`:

```sh
cat > ~/.gitignore << 'EOF'
.venv
.cursor
.devspace
__debug_bin*
EOF
```

Then configure git to use it:

```sh
git config --global core.excludesFile ~/.gitignore
```

## ❓ FAQ

**Q: pytest keeps running in the background after I click Stop. How do I actually stop it?**

Always run e2e tests in debug mode. When you click stop in debug mode, the process will actually stop.

**Q: Software Catalog shows up instead of OperatorHub in OpenShift Local. How do I install operators?**

Operators are still available and can be listed with `oc get packagemanifests` and installed by creating Subscriptions. Use the "Install ODH Operator" or "Install RHOAI Operator" tasks to install operators.

**Q: I'm getting ImagePullBackOff errors. How do I fix this?**

Run the "Install Pull Secret" task to inject your docker and quay credentials.

## 🤝 Contributions

Contributions welcome! Fork and submit a pull request.

Make a best effort to fashion contributions to be as environment-agnostic as possible and document exceptions in [Prereqs](README.md#prereqs).