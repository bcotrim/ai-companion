# Pet SDK

AI Companion uses the Codex pet format so the same pet folder works in Codex and AI Companion.

Required files:

- `pet.json`
- `spritesheet.webp`

Default sprite grid:

- 8 columns
- 9 rows
- 192 x 208 px cells
- 1536 x 1872 px spritesheet

Rows:

| Row | Animation | Used for |
| --- | --- | --- |
| 0 | `idle` | idle / asleep |
| 1 | `running-right` | dragging right |
| 2 | `running-left` | dragging left |
| 3 | `waving` | done |
| 4 | `jumping` | hover / compacting fallback |
| 5 | `failed` | failed tool or turn |
| 6 | `waiting` | needs you |
| 7 | `running` | working / subagent fallback |
| 8 | `review` | planning / task fallback |

Validate a pet:

```sh
make validate-pet PET=/path/to/pet-folder-or.zip
```

Install a pet from the app:

1. Right-click the pet.
2. Choose **Pet > Install Pet...**.
3. Select a pet folder or zip.

The app validates the package before copying it into `~/.claude/pets/`.
