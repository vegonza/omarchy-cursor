# Omarchy Cursor

A native Cursor project picker for Omarchy 4 (Quattro). It runs as a menu
plugin inside the existing `omarchy-shell` Quickshell process, replacing the
old Walker-based picker without adding another daemon.

The project list comes from Cursor's own recent-history database and keeps its
most-recent-first order. It supports:

- local folders;
- `.code-workspace` files;
- Remote SSH folders;
- dev containers and other Cursor remote folder URIs;
- keyboard filtering and mouse selection;
- the active Omarchy theme, spacing, typography, and borders.

## Requirements

- Omarchy 4.0 or newer (the Quattro/Quickshell plugin system)
- Cursor installed from the standard Omarchy/Arch package (the plugin launches
  `/usr/share/cursor/cursor` directly to avoid conflicting Cursor Agent shims)
- Python 3 (included with Omarchy)

## Install

Install and enable the plugin with:

```bash
omarchy plugin add https://github.com/vegonza/omarchy-cursor.git --enable
```

For local development, link this checkout into the user plugin directory:

```bash
mkdir -p ~/.config/omarchy/plugins
ln -s "$(pwd)" ~/.config/omarchy/plugins/vegonza.omarchy-cursor
omarchy-shell shell rescanPlugins
omarchy plugin enable vegonza.omarchy-cursor
```

Then add the block from [`examples/bindings.lua`](examples/bindings.lua) to
`~/.config/hypr/bindings.lua`. It uses `Super+N`, matching the original picker.
Validate Hyprland after saving:

```bash
hyprctl reload
hyprctl configerrors
```

## Usage

- `Super+N`: open or close the project picker
- type: filter by project name, path, or remote type
- `Up` / `Down`, `Page Up` / `Page Down`, `Home` / `End`: move selection
- `Enter`: open the selected project in a new Cursor window
- `Ctrl+R`: reload Cursor's recent-project database
- `Esc`: clear the filter, then close the picker

The corresponding IPC command is:

```bash
omarchy-shell shell toggle vegonza.omarchy-cursor '{}'
```

## Validate

```bash
omarchy plugin validate .
qmllint -I /usr/share/omarchy/shell CursorProjects.qml
python -m unittest discover -s tests -v
```
