# Contributing

Lots of people work on this project at the same time. These rules are here so nobody's
work gets overwritten.

## 1. Claim an issue before you start

- Find an open issue (start with the ones labeled `good first issue`) and **comment "I'll take this"**,
  or ask an officer to assign you.
- **Don't start work on an issue that's assigned to someone else.** If it's been quiet for
  two weeks, ask in the issue whether you can take it over.
- If your idea has no issue yet, **open one first** and wait for a thumbs-up. A surprise
  PR might be doing something someone else is already building.
- If you get stuck or can't finish, say so in the issue and unassign yourself. That's
  completely fine.

## 2. Branch naming

Branch off an up-to-date `main`:

```
<type>/<issue-number>-<short-description>
```

| type       | use for                              | example                         |
|------------|--------------------------------------|---------------------------------|
| `feature/` | new gameplay, systems, scenes        | `feature/12-player-movement`    |
| `fix/`     | bug fixes                            | `fix/31-jump-double-trigger`    |
| `art/`     | models, textures, audio, fonts       | `art/18-rifle-model`            |
| `level/`   | map/level work                       | `level/22-warehouse-blockout`   |
| `docs/`    | documentation only                   | `docs/5-setup-guide-windows`    |

Use lowercase and hyphens, and don't commit directly to `main`.

## 3. One feature per PR

- **One PR = one issue.** Put `Closes #<number>` in the description.
- Keep PRs small. A reviewer should be able to read one in 15 minutes.
- Only touch files that belong to your piece. If you need something changed in another
  system, open an issue for it or ask its owner.
- **`project.godot` and `scenes/main.tscn` are shared hotspots.** Only change them when your
  issue requires it (e.g. adding input actions), and call it out in the PR description.
- Before opening the PR, **open the project in Godot and run it (F5)**. It has to launch with
  no errors in the Output panel. The "Godot check" CI job also runs on every PR and must pass.
- You need at least one approving review before merging.

## 4. Assets & Git LFS

**Every binary asset must go through Git LFS.** The patterns are already set in
[`.gitattributes`](.gitattributes): models (`.blend .fbx .glb .gltf .obj`), images
(`.png .jpg .tga` …), audio (`.wav .ogg .mp3`), fonts, and Godot binary resources
(`.res .scn` …).

1. Run `git lfs install` once on your machine **before** your first commit.
2. Put files in the right `assets/` subfolder with `snake_case` names.
3. Before pushing, check: `git lfs ls-files` should list your new binaries.
4. Commit the matching `.import` files Godot creates, since they're small text files.
5. If you need a file type that's missing from `.gitattributes`, add the pattern
   **in its own PR first**.

Only use assets you made yourself or that have a license allowing it (CC0 / CC-BY, etc.).
Note the source and license in the PR description.

## 5. Godot conventions

- Save scenes as `.tscn` and resources as `.tres` (text formats that can be diffed and merged). Avoid `.scn`/`.res`.
- `snake_case` for files and folders, `PascalCase` for `class_name`s and node names.
- Every scene's root script lives in the matching `scripts/` folder.
- Systems talk to each other through **signals** (see [ARCHITECTURE.md](ARCHITECTURE.md)),
  not by reaching into each other's nodes.
- Don't commit the `.godot/` folder (it's already gitignored).
