# assets/fonts

Font files (.ttf, .otf).

**Everything in this folder is a binary tracked by Git LFS** (see `/.gitattributes`).
Run `git lfs install` once on your machine before committing anything here, and check
with `git lfs ls-files` that your files show up before you push.

- Use `snake_case` file names, and put each asset set in a subfolder (e.g. `fonts/rifle/`).
- Commit the `.import` file Godot creates next to each asset. It's plain text, not LFS.
- Don't commit huge work-in-progress files. If it's over ~100 MB, ask in the club channel first.
