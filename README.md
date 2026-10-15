# IST Club Fall Game

A collaborative 3D game built in **Godot 4** by the IST club, Fall 2026, using real 3D models.

The genre and style are still open. The club decides that together, and this repo gives
everyone a shared place to build it.

To have something playable from day one, the repo ships a small **starter loop**: a
first-person **wave survival** game in a concrete container yard. You have a carbine with a
red-dot sight; melee rushers and riflemen come at you in waves, and you win by surviving 5.
It aims for a grounded feel (aim down sights, recoil, crouching behind cover, headshots), but
all art is still built from primitive shapes and procedural materials, and the sounds are
synthesized placeholders. Every system is meant to be extended, reskinned, or replaced.

The work is divided into issues that club members claim and build in parallel.
[ARCHITECTURE.md](ARCHITECTURE.md) explains how the pieces fit together and lists what's built
and what's open. [CONTRIBUTING.md](CONTRIBUTING.md) explains how to pick something up.

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
4. Press **F5** (Run Project). You spawn in the arena and the first wave arrives after a few seconds.

## Controls

| Action              | Default                 |
|---------------------|-------------------------|
| Move                | W A S D                 |
| Look                | Mouse                   |
| Jump / Sprint       | Space / Shift           |
| Crouch              | Ctrl or C (hold)        |
| Aim down sights     | Right mouse (hold)      |
| Interact            | F (hold)                |
| Fire                | Left mouse (hold)       |
| Reload              | R (also automatic when empty) |
| Switch weapon       | Mouse wheel, Q / E      |
| Pause               | Esc or P                |
| Recapture the mouse | Click in the game window |

Change bindings in **Project > Project Settings > Input Map**.

## Game modes

The game opens on a main menu with two levels:

- **Arena — Survival**: the concrete container yard. Survive 5 waves of rushers and riflemen.
- **Forest — Recon & Extract**: a 160 m forest valley with a mission: scout the outpost from the
  ridge, hold F at the laptop to download intel, destroy two supply caches, then hold the landing
  zone for 60 s while reinforcements close in. Patrols don't know you're there until they see you
  or hear your shots. Finishing shows time, kills, headshots, accuracy, and a 1–3 star rating;
  best results are saved and shown on the menu.

## Folder map

```
project.godot          Engine config: main scene, autoloads, input map, physics layer names
scenes/
  main.tscn            Run scene. Instances the map and starts the match
  player/              player.tscn (body, camera, weapon holder, health)
  weapons/             rifle.tscn (one scene per weapon)
  maps/                arena.tscn (CSG greybox with spawn points and navigation)
  ui/                  hud.tscn, pause_menu.tscn, game_over_screen.tscn
  enemies/             grunt.tscn (one scene per enemy type)
scripts/               Mirrors scenes/: a script lives in the folder matching its scene
  main.gd              Hands the map to GameManager
  core/                game_manager.gd (autoload), health.gd (damage component)
  player/              player_controller.gd
  weapons/             weapon_base.gd, hitscan_weapon.gd
  maps/                game_map.gd (shared by every map)
  ui/                  ui_manager.gd (autoload), hud.gd, pause_menu.gd, game_over_screen.gd
  enemies/             enemy_base.gd, grunt.gd
assets/                Raw binaries, ALL tracked by Git LFS
  models/  textures/  audio/  fonts/
resources/             Shared .tres resources
  materials/           Greybox grid materials, hit flash
addons/                Third-party Godot plugins
docs/                  Design notes, diagrams, meeting notes
```

Godot 4.4 creates a `.uid` file next to every script and shader. **Commit them** along with
the script, so everyone shares the same IDs.

To find where your piece goes, look up your system in [ARCHITECTURE.md](ARCHITECTURE.md). Its
scene goes in `scenes/<area>/`, its script in `scripts/<area>/`, and its art in `assets/`.
