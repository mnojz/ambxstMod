# Lock Screen Customizer

Adds a dedicated **Lockscreen** tab to Ambxst Settings. The mod targets Ambxst 1.3.15.

## Install

Run from the root of this repository.

```sh
ambxst mods install ./lockscreen-customizer
ambxst mods enable mnojz.lockscreen-customizer
ambxst reload
```

To update an existing installation, run `ambxst mods check-updates mnojz.lockscreen-customizer`, apply the returned plan with `ambxst mods apply-updates <plan-id>`, and run `ambxst reload`.

## Customize

Open **Ambxst Settings → Lockscreen**. The preview updates as you edit. Click the floating **Save changes** button to apply the draft to the actual lock screen.

- **Preview** shows your current layout. Click the preview card to open it full-screen. Press Esc, use Close, or submit any placeholder text in the preview password field to dismiss it. The preview never needs your account password.
- **Edit widget layout** opens a full-screen editor. Click a widget to select it, drag it to move it, or drag an edge or corner to resize it. Widgets snap to screen edges, the center, and neighboring widgets. A guide highlights each snap. Dropping a widget updates the draft. A preset restores that widget’s preset size and position.
- **Wallpaper** lets you select a single image, tick several images for a slideshow, or pick a muted looping video or GIF. **Use desktop** restores Ambxst’s desktop wallpaper. Adjust blur from 0% to 100% and set the slideshow interval in the same section.
- **Shortcuts** lets you toggle the circular Power off and Restart buttons. Selected buttons use your theme’s primary color. Move and resize them individually in the layout editor, then click **Save changes**. Power actions require a second click on the actual lock screen.
- **Clock, Media player, and Login** offer visual preset cards that follow the current shell palette. The media widget shows sample content in the preview when no MPRIS player is active.

The wallpaper gallery lives in `$XDG_DATA_HOME/ambxst/lockscreen-wallpapers` or `~/.local/share/ambxst/lockscreen-wallpapers`. The mod seeds three bundled Ambxst images on the first visit and includes supported images and videos from subfolders of both the gallery and the current desktop wallpaper folder. **Import files** copies your selections into that folder. Click **Save changes** to apply the selected wallpapers. You can also add files in your file manager and refresh the gallery. FFmpeg is optional and generates thumbnails for local videos when available. Video playback uses Qt Multimedia and depends on the available codecs.

The Glance clock and Now playing and Minimal presets draw on centered-clock and compact-panel ideas from [Caelestia](https://github.com/caelestia-dots/shell/tree/main/modules/lock) and [DavnFs’s Caelestia setup](https://github.com/DavnFs/caelestia-setup).

## Disable

```sh
ambxst mods disable mnojz.lockscreen-customizer
ambxst reload
```
