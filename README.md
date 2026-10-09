# Storage Alert Monitor 1.0.1.3

## Build

Run `python tools/build.py` from the Git checkout. The command writes
`builds/FS25_z_StorageAlertMonitor.zip` and verifies that all 13 packaged files
match the source byte for byte. Text files use LF line endings, enforced by
`.gitattributes`; ZIP timestamps and permissions are fixed for repeatable builds.
Build tools and Git metadata are excluded from the mod package.

## Mouse control

Press **Left Ctrl+Left Alt+S** or reassign **Storage Alerts: Toggle mouse / move HUD** in Controls. The default was checked against this player's saved bindings. Press it on foot or in a vehicle to enable the cursor and HUD move mode. Drag the title bar, then press it again or click outside the HUD to finish. The previous cursor state is restored. It works on foot and in vehicles without another cursor mod. The existing menu Move HUD button continues to work.

Mouse camera movement pauses while the cursor is visible, on foot and in vehicles. Keyboard and controller camera input remain available. Hiding the cursor immediately restores mouse look.

## Changelog

### 1.0.1.3

- Localize menu, HUD, building categories, animal metrics and all controls in English and German.
- Keep saved building and product keys unchanged.

### 1.0.1.2

- Pause mouse camera movement while using the HUD cursor.

### 1.0.1.1

- Added an assignable mouse control so HUD movement works without another mod.
- Repeated requests to enter move mode preserve the original cursor state.

### 1.0.1.0

- Standardized Lua/XML formatting and metadata.
