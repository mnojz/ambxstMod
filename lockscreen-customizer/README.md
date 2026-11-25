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
- **Edit widget layout** opens a full-screen editor. Click a widget to select it, drag it to move it, or drag an edge or corner to resize it. Media, login, and the visualizer can be resized independently along both axes. Clock resizing scales its contents proportionally. Click empty space to hide the inspector and resize grips. Widgets snap to screen edges, the center, and neighboring widgets. A guide highlights each snap. Click the wrench inside the lower-right resize grip to open controls for the selected widget. Drag the panel by its header to snap it to either edge. It also moves aside if a selected widget is dragged into it. Right-click empty space to add a widget. Right-click a widget and choose **Remove widget**. Login is always available. Built-in presets keep the current layout. Saved presets restore the captured size and position. Edits and drops update the draft, which you can save from Settings after clicking **Done**.
- The inspector opens on **Presets**. Use **Content** for widget options and **Style** for widget-wide appearance. Click a component to open **Parts**, where you can customize its appearance. Clock positions use 0% for the center and ±100% for the edges. The clock frame fits its visible parts, and the Ambxst preset shows the actual position of each digit block. Select **Album art** in **Parts** for artwork placement, sizing, crop, and outline.

- **Wallpaper** lets you select a single image, tick several images for a slideshow, or pick a muted looping video or GIF. **Use desktop** restores Ambxst’s desktop wallpaper. Use **Tint** to apply the shell theme palette to the lock screen wallpaper. Adjust blur and dimming independently from 0% to 100% and set the slideshow interval in the same section.
- The **Add widget** menu includes the circular Power off and Restart buttons. Move and resize them individually in the layout editor, or right-click to remove them. Power actions require a second click on the actual lock screen.
- **Clock** has Glance, Ambxst, Stacked, and Orbit presets. Set date, weekday, seconds, greeting, 12/24-hour format, AM/PM visibility, a searchable font picker, weight, date proportion, and letter spacing. Orbit uses an analogue dial with an optional second hand.
- **Media player** offers five built-in presets. Arrange artwork to the left, right, or above the text. Artwork stays square when placed above the track, and the card grows to make room. Automatic placement stacks artwork in narrow, tall cards and move the progress bar below the controls. Set the artwork fit and spacing, and choose which metadata and controls are displayed. **Login** offers six built-in presets and can position the avatar above or beside the password field. The media widget shows sample content in the preview when no MPRIS player is active. Widget text and controls are laid out at their displayed size. Album art and profile photos retain the resolution limits of their source images.
- Add **Audio visualizer** from the layout editor’s right-click menu. Choose Gradient wave, Rounded bars, Mirrored bars, Ripple ring, or Spectrum dots, then set a custom color or use the shell theme. Ripple ring keeps its center clear for a profile picture and uses the shorter side of the widget to set its diameter. The visualizer resizes independently along both axes. Wider bar layouts draw more bars, and the widget height sets the amplitude ceiling. Each stereo channel runs from sub-bass to 20 kHz, with a more sensitive, compact kick region in the center and more space for treble at the outer edges. The independent analyzer uses the band weighting, automatic sensitivity, and falloff from CAVA 1.0.0. The built-in analyzer reads the default playback monitor using PulseAudio or PipeWire’s PulseAudio compatibility service. It uses the `libpulse-simple` and `libfftw3f` shared libraries.
- **Appearance** controls opacity, background fill, border, corner radius, and shadow for the clock, media player, login, and audio visualizer. When your edits differ from the existing presets, **Save to preset** adds a named card to the widget’s preset grid. Click a card to apply it or use its pencil button to rename it. Presets are stored as versioned JSON records in `lockscreen-customizer.json` when you click **Save changes**.

The wallpaper gallery lives in `$XDG_DATA_HOME/ambxst/lockscreen-wallpapers` or `~/.local/share/ambxst/lockscreen-wallpapers`. The mod seeds three bundled Ambxst images on the first visit and includes supported images and videos from subfolders of both the gallery and the current desktop wallpaper folder. **Import files** copies your selections into that folder. Click **Save changes** to apply the selected wallpapers. You can also add files in your file manager and refresh the gallery. FFmpeg is optional. When available, the shell prepares a still frame and a display-sized playback copy for oversized videos in the background. The still frame appears while Qt Multimedia prepares motion.

The Glance clock and Now playing and Minimal presets draw on centered-clock and compact-panel ideas from [Caelestia](https://github.com/caelestia-dots/shell/tree/main/modules/lock) and [DavnFs’s Caelestia setup](https://github.com/DavnFs/caelestia-setup).

## Disable

```sh
ambxst mods disable mnojz.lockscreen-customizer
ambxst reload
```
