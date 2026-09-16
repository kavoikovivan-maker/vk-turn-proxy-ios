# K&C upstream research

This directory keeps reviewed upstream source references for future K&C work.
They are pinned Git submodules: cloning this repository does not execute their
installers, hooks, package scripts, or application code.

## Sources

| Project | Purpose for K&C | Pinned revision |
| --- | --- | --- |
| `upstream/ECC` | Agent workflow, skills, memory, review and verification | `8321021c54d670126ce3b2969d5deb880b4b0c2a` |
| `upstream/agentshield` | Agent configuration and tool security auditing | `b0891303bdcd6037376a94263d45cfd2ff3dfb98` |
| `upstream/claude-swarm` | Multi-agent decomposition, coordination and quality gates | `9b1c5561157abd2d0d043758b7bfcb0319267d9f` |
| `upstream/JARVIS` | Streaming research, graceful fallback and Telegram intake patterns | `4369c34babd21d539c420866da51c7a8365f1c9e` |

## Integration rules

1. Treat every upstream repository as untrusted reference code until reviewed.
2. Do not run install scripts, hooks, MCP servers, or package lifecycle scripts directly.
3. Copy only the smallest required module into K&C after license and security review.
4. Run AgentShield and the normal K&C tests before accepting extracted code.
5. Do not import JARVIS face identification, hidden profiling, or personal-dossier features.
6. Keep upstream attribution and applicable license notices with reused code.

## Checkout

```sh
git clone --recurse-submodules <repository-url>
```

For an existing checkout:

```sh
git submodule update --init --recursive
```
