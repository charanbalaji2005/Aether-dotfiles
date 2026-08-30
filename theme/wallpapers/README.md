# Wallpapers

AetherOS includes an integrated Wallpaper Engine with a visual GUI selector modal, smooth cross-fading desktop background renderer, CLI management tool, and keybindings.

## Keybindings
- **`Super + W`**: Toggle interactive visual Wallpaper Picker (search, preview cards, click to apply)
- **`Super + Shift + W`**: Randomly select and apply a wallpaper immediately
- **`Super + Ctrl + W`**: Cycle to the next wallpaper in the collection

## CLI Usage (`aether wallpaper` or `aether-wallpaper`)
```bash
aether wallpaper random         # Pick & apply random wallpaper
aether wallpaper next           # Cycle to next wallpaper
aether wallpaper prev           # Cycle to previous wallpaper
aether wallpaper select         # Open GUI picker modal
aether wallpaper list           # List all discovered wallpapers
aether wallpaper set <path>     # Apply specific image file
aether wallpaper current        # Print currently active wallpaper path
```

## Adding Wallpapers
Drop your own wallpapers (`.png`, `.jpg`, `.jpeg`, `.webp`, `.jxl`) into `theme/wallpapers/` or `~/.config/aether-shell/wallpapers/` or `~/Pictures/Wallpapers/`. They will be discovered automatically.
