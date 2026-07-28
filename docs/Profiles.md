# Profiles

Profiles live in `manifest/components.yaml` under `profiles:` — the same file,
validated by the same compiler. A profile referencing a component that no
longer exists fails CI rather than failing on someone's laptop.

| Profile | Agents | For |
|---|---|---|
| `minimal` | Claude Code | Build tools, git, Node, one agent |
| `developer` | all three | The default workstation |
| `django` | all three | + PostgreSQL/Redis clients, libpq |
| `gis` | all three | + GDAL, PROJ, GEOS, PostGIS client, spatialite |
| `full` | all three | Everything |

```bash
ai install developer
ai install gis --harness=claude-code   # profile components, one agent
```

## Overlays

`profiles/*.conf` are optional environment overlays — they set defaults such as
`AI_ALLOW_REMOTE_SCRIPTS` or `CPLUS_INCLUDE_PATH` for GDAL builds. They cannot
define components; that would reintroduce a second source of truth.

## Adding a profile

```yaml
profiles:
  embedded:
    description: Firmware work.
    harnesses: [claude-code, codex]
    components: [base, git, cli-utils, python, node, claude-code, codex, caveman]
```

Then `make manifest`. The compiler rejects unknown component ids.
