# claude-unity-devkit

A Claude Code plugin marketplace hosting one plugin, **`claude-unity-devkit`**: workflow skills,
live agents, slash commands, hooks, and templates for Unity / C# game development — sub-agent
orchestration keyed to assembly definitions, an implement → review → ship chain, GameCI pipelines,
and Droplet deploys for dedicated servers and WebGL builds.

The layout mirrors [claude-t3-devkit](https://github.com/brezzy1337/claude-t3-devkit) so the repo
can host more plugins later:

```
claude-GameCI-devkit/                     # this repo = the marketplace "claude-unity-devkit"
├── .claude-plugin/marketplace.json       # one entry, source "./claude-unity-devkit"
├── README.md                             # you are here
└── claude-unity-devkit/                  # the plugin — see its README for everything inside
    ├── .claude-plugin/plugin.json
    ├── skills/  agents/  commands/  hooks/  scripts/  templates/
    ├── bootstrap.sh
    ├── .mcp.json
    └── README.md
```

## Install

The GitHub repo is `brezzy1337/claude-GameCI-devkit`; the marketplace and plugin inside it are both
named `claude-unity-devkit`, so you add the repo and install `claude-unity-devkit@claude-unity-devkit`.

Inside an interactive `claude` session:

```
/plugin marketplace add brezzy1337/claude-GameCI-devkit
/plugin install claude-unity-devkit@claude-unity-devkit

# recommended companions from the built-in official marketplace
/plugin install csharp-lsp@claude-plugins-official
/plugin install github@claude-plugins-official
/reload-plugins
```

To try it without installing: clone the repo and run
`claude --plugin-dir ./claude-GameCI-devkit/claude-unity-devkit`.

## Quick start

| Starting point | Run |
| --- | --- |
| New game | `/claude-unity-devkit:new-project my-game`, then Unity Hub → *Add project from disk* |
| Existing Unity repo | `/claude-unity-devkit:add-to-project` |
| Add CI (GameCI) | `/claude-unity-devkit:setup-ci` |
| Add deploys (dedicated server or WebGL → Droplet) | `/claude-unity-devkit:setup-deploy` |
| Day-to-day | `/claude-unity-devkit:code-todo <change>` → approve → `/claude-unity-devkit:ship` |

Full documentation — what's inside, agents, hooks, MCP slots, pinned versions — is in
[`claude-unity-devkit/README.md`](claude-unity-devkit/README.md).

## Validate

Fill in (or delete) the placeholder server slots in `claude-unity-devkit/.mcp.json`, then:

```
claude plugin validate .
claude plugin validate ./claude-unity-devkit
bash claude-unity-devkit/scripts/sync-templates.sh --check
```
