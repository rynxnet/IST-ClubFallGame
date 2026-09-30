# IST Club Fall Game

A collaborative 3D game built in **Godot 4** by the IST club, Fall 2026, using real 3D models.

The genre and style are still open. It could end up a shooter, an adventure, a platformer, or
something else. The club decides that together, and this repo gives everyone a shared place
to build it.

For now this repo is only a **skeleton**: the folders, config, placeholder scenes, and stub
scripts are in place, and no gameplay has been written yet. The starter systems (player,
weapons, enemies) are just a common starting point, so rename or replace them as the game
takes shape. The work is divided into issues
that club members claim and build in parallel. [ARCHITECTURE.md](ARCHITECTURE.md) explains how
the pieces fit together, and [CONTRIBUTING.md](CONTRIBUTING.md) explains how to pick one up.

## Setup

You need:

- **Godot 4.4 or newer** (standard build, not .NET/C#): <https://godotengine.org/download>
- **Git** and **Git LFS**: <https://git-lfs.com>

```sh
git lfs install            # once per machine, BEFORE cloning or committing assets
git clone https://github.com/rynxnet/IST-ClubFallGame.git
cd IST-ClubFallGame
git lfs pull               # fetch the real binary assets
```

> ⚠️ If you skip `git lfs install`, your images, models and audio get committed as normal
> files and bloat the repo for everyone. See [CONTRIBUTING.md](CONTRIBUTING.md#assets--git-lfs).

## Opening in Godot

1. Launch Godot and open the **Project Manager**.
2. Click **Import**, pick this folder's `project.godot`, then **Import & Edit**.
3. The first import takes a moment while Godot builds its `.godot/` cache (that folder is gitignored).
4. Press **F5** (Run Project). You should see a floor with a "project skeleton" label.

## Folder map

```
project.godot          Engine config: main scene, autoloads, physics layer names
scenes/
  main.tscn            Run scene. Currently loads the placeholder map
  player/              Player scene(s)
  weapons/             One scene per weapon
  maps/                Levels (placeholder_map.tscn lives here for now)
  ui/                  HUD and menu scenes
  enemies/             One scene per enemy type
scripts/               Mirrors scenes/: a script lives in the folder matching its scene
  core/                game_manager.gd (autoload, no scene)
  player/              player_controller.gd
  weapons/             weapon_base.gd, with concrete weapons extending it
  maps/                Map-specific scripts
  ui/                  ui_manager.gd (autoload)
  enemies/             enemy_base.gd, with concrete enemies extending it
assets/                Raw binaries, ALL tracked by Git LFS
  models/  textures/  audio/  fonts/
resources/             Shared .tres resources (materials, weapon stats, themes)
addons/                Third-party Godot plugins
docs/                  Design notes, diagrams, meeting notes
```

To find where your piece goes, look up your system in [ARCHITECTURE.md](ARCHITECTURE.md). Its
scene goes in `scenes/<area>/`, its script in `scripts/<area>/`, and its art in `assets/`.
