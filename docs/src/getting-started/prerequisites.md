# Prerequisites

Before you begin, make sure your system has the following dependencies installed.

## mise (Version Manager)

Liteskill uses [mise](https://mise.jdx.dev/) to manage language runtimes. mise ensures every developer and CI environment uses the exact same versions of Elixir, Erlang, and Node.js.

Install mise by following the instructions at [mise.jdx.dev](https://mise.jdx.dev/getting-started.html). On most systems this is a single command:

```bash
curl https://mise.run | sh
```

After installation, activate mise in your shell:

```bash
# For bash
echo 'eval "$(~/.local/bin/mise activate bash)"' >> ~/.bashrc

# For zsh
echo 'eval "$(~/.local/bin/mise activate zsh)"' >> ~/.zshrc

# For fish
echo '~/.local/bin/mise activate fish | source' >> ~/.config/fish/config.fish
```

Restart your shell or source the profile file for the changes to take effect.

## Tool Versions

The repository includes a `mise.toml` file that pins the exact tool versions:

| Tool       | Version |
|------------|---------|
| **Elixir** | 1.18    |
| **Erlang** | 28      |
| **Node**   | 24      |

When you run `mise install` inside the project directory, mise reads `mise.toml` and installs these versions automatically. You do not need to install Elixir, Erlang, or Node manually -- mise handles everything.

> **Note:** Erlang compilation can take several minutes the first time if mise needs to build it from source. Subsequent installs are cached.

## PostgreSQL

Liteskill requires **PostgreSQL 14 or later** with the [pgvector](https://github.com/pgvector/pgvector) extension installed. pgvector provides vector similarity search, which powers the RAG (Retrieval-Augmented Generation) pipeline.

### Installing PostgreSQL

**macOS (Homebrew):**

```bash
brew install postgresql@16
brew services start postgresql@16
```

**Ubuntu/Debian:**

```bash
sudo apt-get install postgresql-16
```

**Fedora/RHEL:**

```bash
sudo dnf install postgresql16-server
sudo postgresql-setup --initdb
sudo systemctl start postgresql
```

### Installing pgvector

**macOS (Homebrew):**

```bash
brew install pgvector
```

**Ubuntu/Debian (from source):**

```bash
sudo apt-get install postgresql-server-dev-16
cd /tmp
git clone --branch v0.8.0 https://github.com/pgvector/pgvector.git
cd pgvector
make
sudo make install
```

After installation, the extension is enabled automatically by the Ecto migrations when you run `mix setup`. You do not need to run `CREATE EXTENSION` manually.

> **Tip:** If you prefer not to install PostgreSQL and pgvector locally, use the Docker Compose setup described in the [Docker](docker.md) guide. The `pgvector/pgvector:pg16` image includes pgvector out of the box.

### Default Development Database

In development mode (`MIX_ENV=dev`), Liteskill connects to PostgreSQL with these defaults (defined in `config/dev.exs`):

| Setting    | Default Value      |
|------------|--------------------|
| Host       | `localhost`        |
| Port       | `5432`             |
| Username   | `postgres`         |
| Password   | `postgres`         |
| Database   | `liteskill_dev`    |

Make sure your local PostgreSQL instance accepts these credentials, or adjust `config/dev.exs` to match your setup.

## Docker (Optional)

If you want to run Liteskill in containers rather than installing dependencies locally, you need:

- [Docker Engine](https://docs.docker.com/engine/install/) 20.10 or later
- [Docker Compose](https://docs.docker.com/compose/install/) v2 (included with Docker Desktop)

The Docker setup handles PostgreSQL, pgvector, and the application itself -- no local Elixir, Erlang, or Node installation required. See the [Docker](docker.md) guide for details.

## Summary

| Dependency   | Required? | Purpose |
|-------------|-----------|---------|
| **mise**     | Yes (for local dev) | Manages Elixir, Erlang, and Node versions |
| **PostgreSQL 14+** | Yes | Primary database |
| **pgvector** | Yes | Vector similarity search for RAG |
| **Docker**   | Optional | Containerized deployment without local tool installation |
