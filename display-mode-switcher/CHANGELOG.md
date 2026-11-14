# 1.1.4

- Reduce icon size slightly while keeping the icon and label group centered.

# 1.1.3

- Replace stretched SVG image textures with native Qt Quick vector curves.
- Preserve icon proportions and use slightly rounded screen corners and stroke joins.

# 1.1.2

- Normalize visible icon dimensions across all buttons.
- Increase the shared icon/label gap and make labels bold.

# 1.1.1

- Center icons and labels as a single group with a tighter gap.
- Increase the menu radius slightly to match the inset button corners.
- Remove the stand from the upper screen in the Mirror icon.

# 1.1.0

- Open the chooser without an external display; repeated shortcuts cycle modes.
- Apply and dismiss one second after the last shortcut, extending visibility during rapid presses.
- Remove the header, close button, and current-mode caption; compact the buttons and enlarge icons.
- Redraw Mirror and Extend with consistent monitor geometry.
- Move multi-monitor target selection to a right-click / Menu-key context menu.

# 1.0.0

- Add shell-native projection menu and `ambxst run displaymode` command.
- Discover disabled connected outputs and numeric-string mirror sources.
- Verify destinations before disabling other outputs; recover the internal panel after unplug.
- Package local icons, keyboard navigation, target selection, tests, and installation guidance.
