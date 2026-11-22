# Lock Screen Customizer

Adds a dedicated **Lockscreen** tab to Ambxst Settings. Tested on Ambxst 1.3.15 and 1.4.1.

## Install

Run from the root of this repository.

```sh
ambxst mods install ./lockscreen-customizer
ambxst mods enable mnojz.lockscreen-customizer
ambxst reload
```

To update an existing installation, run `ambxst mods check-updates mnojz.lockscreen-customizer`, apply the returned plan with `ambxst mods apply-updates <plan-id>`, and run `ambxst reload`.

## Colorbxst compatibility

The customizer uses its own lock screen component, so [Colorbxst](https://github.com/Ecta250/ambxst-colorbxst) can patch Ambxst’s stock lock screen independently. With Colorbxst enabled, the custom clock follows the theme’s Primary variant. Both mod load orders were tested with Colorbxst 0.7.0 on Ambxst 1.3.15 and Colorbxst 0.8.0 on Ambxst 1.4.1.

## Customize

Open **Ambxst Settings → Lockscreen**. The preview updates as you edit. Click the floating **Save changes** button to apply the draft to the actual lock screen.

- **Preview** shows your current layout. Click the preview card to open it full-screen. Press Esc, use Close, or submit any placeholder text in the preview password field to dismiss it. The preview never needs your account password.
- **Edit widget layout** opens a full-screen editor. Click a widget to select it, drag it to move it, or drag an edge or corner to resize it. Widgets snap to screen edges, the center, and neighboring widgets. A guide highlights each snap. Click the wrench inside the lower-right resize grip to open controls for the selected widget. The panel moves to the other side if the widget reaches it and there is room. Right-click empty space to add a widget. Right-click a widget and choose **Remove widget**. Login is always available. Built-in presets keep the current layout. Saved presets restore the captured size and position. Edits and drops update the draft, which you can save from Settings after clicking **Done**.
- **Wallpaper** lets you select a single image, tick several images for a slideshow, or pick a muted looping video or GIF. **Use desktop** restores Ambxst’s desktop wallpaper. Use **Tint** to apply the shell theme palette to the lock screen wallpaper. Adjust blur and dimming independently from 0% to 100% and set the slideshow interval in the same section.
- The **Add widget** menu includes the circular Power off and Restart buttons. Move and resize them individually in the layout editor, or right-click to remove them. Power actions require a second click on the actual lock screen.
- **Clock** has Glance, Ambxst, Stacked, and Orbit presets. Set date, weekday, seconds, greeting, 12/24-hour format, AM/PM visibility, a searchable font picker, weight, date proportion, and letter spacing. Orbit uses an analogue dial with an optional second hand.
- **Media player** offers four built-in presets, sliders for background and thumbnail rounding and relative thumbnail size, and a blurred artwork background toggle. **Login** offers six built-in presets. The media widget shows sample content in the preview when no MPRIS player is active. Widget text and controls are laid out at their displayed size. Album art and profile photos retain the resolution limits of their source images.
- **Appearance** includes a drop shadow toggle for Clock, Media player, and Login. When your edits differ from the existing presets, **Save to preset** adds a named card to the widget’s preset grid. Click a card to apply it or use its pencil button to rename it. Presets are stored as versioned JSON records in `lockscreen-customizer.json` when you click **Save changes**.

The wallpaper gallery lives in `$XDG_DATA_HOME/ambxst/lockscreen-wallpapers` or `~/.local/share/ambxst/lockscreen-wallpapers`. The mod seeds three bundled Ambxst images on the first visit and includes supported images and videos from subfolders of both the gallery and the current desktop wallpaper folder. **Import files** copies your selections into that folder. Click **Save changes** to apply the selected wallpapers. You can also add files in your file manager and refresh the gallery. FFmpeg is optional and generates thumbnails for local videos when available. Video playback uses Qt Multimedia and depends on the available codecs.

The Glance clock and Now playing and Minimal presets draw on centered-clock and compact-panel ideas from [Caelestia](https://github.com/caelestia-dots/shell/tree/main/modules/lock) and [DavnFs’s Caelestia setup](https://github.com/DavnFs/caelestia-setup).

## Disable

```sh
ambxst mods disable mnojz.lockscreen-customizer
ambxst reload
```
