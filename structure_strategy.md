# Project Structure Strategy

You have two main paths to deploy Skywire (Elixir) and Rails together on the same server.

## Option 1: The Monorepo (Recommended for MVP)
You merge the Rails app code into this `skywire` repository, or a new parent repo.

**Structure:**
```text
/skywire-project
  /skywire (Elixir Ingestion Engine)
  /web (Rails App)
  docker-compose.yml (Orchestrates everything)
```

**Pros:**
*   **Networking**: Trivial. `service: app` talks to `service: web` by name. No ports exposed to internet.
*   **DevEx**: `docker compose up` starts the *entire* stack. You verify the whole system in one command.
*   **Deployment**: One `git pull`, one `docker compose up`. No version mismatch between "Backend" and "Frontend".

**Cons:**
*   **Size**: Repo gets bigger.
*   **CI**: Logic might get complex if you want to test them separately.

## Option 2: Separate Repos (Polyrepo)
You keep `skywire` and `rails-app` in separate git repos.

**Networking Challenge:**
Docker containers in separate Compose projects *cannot* talk to each other by default.
1.  **Shared Network**: You must create an external docker network (`docker network create skywire-net`) and configure both `docker-compose.yml` files to use it.
2.  **Coordination**: You have to clone two repos, run two commands, and ensure `skywire` is up before `rails` tries to connect.

## Recommendation

**Go Monorepo.**

For a solo/small team building an MVP, the friction of managing two separate deployment pipelines and coordinating local development environments usually slows you down.

Bringing the Rails app into a `/web` folder here lets you treat the entire platform as a single "Appliance" that you verify and ship together.
