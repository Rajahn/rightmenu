# Action Manifest

`actions/rightmenu-actions.json` is the shared product action metadata source.

It is intentionally separate from implementation code:

- Swift reads it through `ActionManifest` for future settings UI, Finder Sync menu planning, and product-level action inventory.
- `scripts/install-quick-actions.py` reads it to decide which Automator Quick Actions to generate and install.
- `scripts/doctor.py` reads it to validate installed workflows and macOS Services registration.

## Fields

- `id`: stable product action identifier.
- `title`: displayed title and workflow package name for Quick Actions.
- `category`: product grouping such as `copy`, `open`, `create`, or `archive`.
- `surfaces`: where the action appears. Current value is `quickAction`; future values can include `finderSync`.
- `coreActionID`: optional link to the Swift `ActionCatalog` action when semantics overlap.
- `quickAction`: Automator-specific metadata.
  - `input`: `selected` for Finder selection, `finder` for frontmost Finder window.
  - `scriptKey`: key mapped to shell implementation in `install-quick-actions.py`.
  - `sendFileTypes`: optional macOS Services file type filter.

## Validation

Run:

```sh
python3 scripts/doctor.py
```

The doctor validates schema version, duplicate IDs/titles, workflow generation, installed workflows, macOS Services registration, and safe behavioral checks.

