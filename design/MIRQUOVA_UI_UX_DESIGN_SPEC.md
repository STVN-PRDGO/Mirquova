# Mirquova UI/UX Design Specification

**Purpose:** Recreate the approved Mirquova desktop and mobile mockup as
closely as possible. Treat the mockup image as the visual source of
truth. Do not redesign or simplify the visual direction without
approval.

**Product:** Mirquova\
**Tagline:** Every screen. One connection.

## 1. Design direction

Mirquova is a unified application for local file transfer, wireless
screen casting, and media playback across computers, phones, and Smart
TVs.

The approved visual direction is a premium dark interface: - Deep navy
and blue-black backgrounds. - Electric blue as the primary action
color. - Cyan for active states, connection indicators, and selected
highlights. - Violet/purple as a secondary accent for media, casting,
and gradient details. - Rounded panels and cards, subtle borders,
restrained shadows, and generous spacing. - Clean sans-serif typography
with a clear hierarchy. - Simple outline icons and compact status
indicators.

The desktop version uses a dashboard layout with persistent left
navigation. The mobile version is a touch-first companion experience
using the same visual identity.

### Non-negotiable rules

1.  Preserve the dark navy foundation and blue/cyan/purple accent
    palette.
2.  Preserve the mockup's information hierarchy and screen composition.
3.  Use consistent rounded cards, buttons, inputs, and status chips.
4.  Keep primary actions prominent and easy to find.
5.  Do not overcrowd screens or add unrelated decorative content.
6.  Keep the product name **Mirquova** and tagline **Every screen. One
    connection.**
7.  Where this specification and the reference image differ, the
    reference image takes precedence.

## 2. Design tokens

Use these as starting values. Sample the reference image for more exact
values when possible.

### Colors

  Token              Suggested value   Usage
  ------------------ ----------------- --------------------------------------
  `background`       `#080D18`         Main app background
  `surface`          `#0E1728`         Sidebar and large panels
  `surface-raised`   `#142138`         Cards and nested panels
  `surface-hover`    `#1A2B45`         Hover and pressed surfaces
  `border-subtle`    `#22334D`         Card outlines and separators
  `text-primary`     `#F4F7FC`         Headings and important labels
  `text-secondary`   `#A7B4C8`         Descriptions and secondary labels
  `text-muted`       `#71819A`         Hints, timestamps, disabled labels
  `primary`          `#3478F6`         Main buttons and selected navigation
  `primary-bright`   `#4C9BFF`         Focus, hover, active emphasis
  `cyan`             `#22D3EE`         Connected states and highlights
  `violet`           `#8B5CF6`         Media/casting accent
  `success`          `#22C98A`         Completed transfers
  `warning`          `#F5B84B`         Waiting or attention states
  `danger`           `#F16B78`         Errors and destructive actions

Suggested accent gradient, used sparingly:

``` css
linear-gradient(115deg, #3478F6 0%, #22D3EE 55%, #8B5CF6 100%)
```

### Typography

Use **Inter** if available; otherwise use a comparable modern
sans-serif.

  Style                           Desktop                Mobile
  ----------------- --------------------- ---------------------
  Page title          26--32 px, semibold   23--27 px, semibold
  Section heading     17--20 px, semibold   16--18 px, semibold
  Card title          14--16 px, semibold   14--16 px, semibold
  Body                          13--15 px             13--14 px
  Caption                       11--12 px             11--12 px
  Button label          13--14 px, medium     13--14 px, medium

Use sentence case and avoid excessive uppercase labels.

### Shape and spacing

-   Main cards: 16--20 px corner radius.
-   Buttons and inputs: 10--12 px corner radius.
-   Status chips: pill-shaped.
-   Desktop page padding: 24--32 px.
-   Desktop card gap: 16--20 px.
-   Mobile page padding: 16--20 px.
-   Mobile card gap: 12--16 px.
-   Use subtle borders and soft shadows; avoid heavy outlines.
-   Reserve blue glow effects for selected or actively connected
    elements.

### Icons

Use one consistent outline icon family, such as Lucide. Use a consistent
18--22 px icon grid. Avoid mixing unrelated icon styles.

## 3. Desktop application shell

Use a persistent left sidebar and a flexible main content area.

``` text
┌──────────────────┬───────────────────────────────────────────────────┐
│ Mirquova         │ Page title                         Context actions│
│                  ├───────────────────────────────────────────────────┤
│ Home             │                                                   │
│ Transfer         │ Main page content                                 │
│ Cast             │ Cards, panels, controls, and activity              │
│ Player           │                                                   │
│ Devices          │                                                   │
│                  │                                                   │
│ Settings         │                                                   │
└──────────────────┴───────────────────────────────────────────────────┘
```

### Sidebar

-   Dark surface, visually distinct from the page background.
-   Mirquova logo/wordmark at the top.
-   Navigation rows with icon and label.
-   Active item highlighted with a blue-tinted background and bright
    icon/text.
-   Settings positioned near the bottom.
-   Target width: approximately 220--250 px on desktop.
-   Keep the sidebar fixed while the main content scrolls.

### Top bar

-   Page title and optional short description.
-   Contextual actions aligned to the right.
-   Keep the top bar visually quiet; content cards should remain the
    focus.

### Main content

-   Use a flexible grid and consistent card spacing.
-   Collapse columns cleanly on smaller laptop screens.
-   Avoid fixed widths that cause clipping.
-   Keep hierarchy and alignment consistent across screens.

## 4. Desktop screens

### 4.1 Home dashboard

Purpose: provide an immediate overview and quick access to the three
core features.

Include: - Welcome/page heading and concise supporting line. - Prominent
quick actions: **Send files**, **Screen cast**, and **Open media
player**. - Nearby/available devices panel. - Recent activity or recent
transfers panel. - Connection status and device information. - Empty
states when no devices or activity exist.

Make quick actions prominent, using coordinated blue, cyan, and violet
accents. Device cards should show device name, device type, connection
state, and a relevant action.

### 4.2 File transfer

Include: - Page heading. - Send and receive modes or clearly separated
actions. - Large drag-and-drop/file-selection area. - Destination-device
selector. - Selected-file list with file name, type icon, size, and
remove action. - Primary transfer action. - Progress bar and
percentage. - Transfer speed and estimated remaining time when
available. - Completed, paused, failed, cancelled, and retry states. -
Recent transfer history.

Interaction: - Support file picker and desktop drag-and-drop. - Show the
selected destination clearly. - Disable the primary action until
required inputs are ready. - Never fabricate progress, speed, or
completion. - Show pause, resume, cancel, and retry only when supported
by the transfer engine.

### 4.3 Screen casting

Include: - Page heading and short explanation. - Available
receiver/device cards. - Source selector, such as full screen or a
supported application/window. - Prominent **Start casting** action. -
Casting/connected state with visible status. - Preview or casting-status
panel where appropriate. - Stop-casting control. - Receiver name and
connection state.

Explain permission requirements before screen capture. Show an empty
state if no receiver is found. Do not imply every TV supports every
casting protocol.

### 4.4 Media player

Include: - Large video playback area. - Play/pause, seek, volume, and
fullscreen controls. - Current time and total duration. - Media title
and file information. - Subtitle control panel. - Subtitle language and
source information when available. - Local subtitle import action. -
OpenSubtitles search/download entry point. - Subtitle appearance
controls when supported (size, color, background, position). - Optional
playlist/file area that does not compete with the video.

Keep the video dominant. Clearly distinguish embedded, local, and
downloaded subtitles. Show accurate loading, unavailable, no-results,
and error states. Do not claim a subtitle has downloaded until
confirmed.

### 4.5 Subtitle panel

Treat this as part of the player, not a separate application.

Include: - Available subtitle tracks and language labels. - Source
labels: embedded, local, or OpenSubtitles. - Local subtitle import. -
OpenSubtitles search. - Selected-track styling. - No-subtitles, loading,
no-results, and error states.

### 4.6 TV remote

Include: - Selected TV name and connection status. - Prominent
directional pad with center/select. - Back and Home controls. - Volume
and playback controls where supported. - Keyboard/text-input action
where supported. - Disconnect or change-device action.

Make controls comfortable to use. Do not show unsupported remote
functions as active. Provide a clear disconnected state.

### 4.7 Settings

Organize settings into grouped sections: - General and appearance -
Device discovery and connection - File transfer - Screen casting - Media
player and subtitles - Storage and downloads - Privacy and permissions -
About Mirquova

Use clear labels, concise explanations, consistent switches/selectors,
and accurate save/apply feedback.

## 5. Mobile application

The mobile version must feel like the same product, not a desktop window
shrunk to phone size.

-   Reuse the same palette, typography, icons, card language, and status
    colors.
-   Use a compact top app bar.
-   Use bottom navigation for the primary destinations.
-   Use full-width cards and vertically stacked content.
-   Use sheets or dialogs for secondary actions.
-   Keep important actions within comfortable thumb reach.
-   Respect safe areas, keyboard appearance, and system navigation.
-   Target touch controls of approximately 44--48 px or larger.

### Mobile navigation

Use a compact bottom navigation for the main destinations represented in
the mockup, such as: - Home - Transfer - Cast - Player - Settings / More

Preserve the reference mockup's actual tab order if it differs.
Highlight the active destination with the electric-blue accent.

### 5.1 Mobile home

-   Compact Mirquova header.
-   Connection/device status.
-   Quick actions for Send, Cast, and Play.
-   Nearby devices.
-   Recent activity.
-   Clear empty states.

Stack content vertically and keep the first important action visible
without excessive scrolling.

### 5.2 Mobile transfer

-   Send/receive mode.
-   Large add-files action.
-   Selected files list.
-   Destination-device selector.
-   Primary send action.
-   Transfer progress/status.
-   Recent transfers.

Use a bottom sheet or full-screen selector for device selection when
clearer than a dense dropdown.

### 5.3 Mobile casting

-   Receiver selection.
-   Source selection.
-   Large Start casting action.
-   Clear casting status and Stop casting action.
-   Permission explanation and empty states.

### 5.4 Mobile media player

-   Video area sized for the available screen.
-   Playback controls and seek bar.
-   Subtitle button with selected-language label.
-   Fullscreen action.
-   Bottom sheet for subtitle selection/settings.
-   Clear way to return to the media library or file list.

Do not place a desktop-style sidebar beside the video on a phone.

### 5.5 Mobile TV remote

-   Large directional pad and center/select.
-   Back and Home.
-   Volume/playback controls where supported.
-   Selected TV and connection status.
-   Adequate spacing around disconnect actions.

### 5.6 Mobile settings

Use grouped settings rows with a setting name, optional one-line
explanation, and trailing value, switch, or chevron. Move complex
settings into detail screens.

## 6. Responsive behavior

  -----------------------------------------------------------------------
  Viewport                            Layout
  ----------------------------------- -----------------------------------
  1200 px and wider                   Full sidebar, multi-column
                                      dashboard, spacious cards

  900--1199 px                        Narrower sidebar and fewer content
                                      columns

  600--899 px                         Collapsible navigation, two-column
                                      or single-column content

  Below 600 px                        Bottom navigation, single-column
                                      cards, touch-first controls
  -----------------------------------------------------------------------

Rules: - Prevent horizontal overflow. - Preserve content hierarchy as
columns collapse. - Move secondary actions into menus/sheets before
shrinking controls. - Support 100% system text scaling. - Support
landscape layouts where useful, especially video and remote control.

## 7. Shared reusable components

Build reusable components to maintain consistency:

-   `AppShell`
-   `DesktopSidebar`
-   `MobileBottomNavigation`
-   `TopBar`
-   `PageHeader`
-   `PrimaryButton`
-   `SecondaryButton`
-   `IconButton`
-   `SurfaceCard`
-   `DeviceCard`
-   `DeviceStatus`
-   `ConnectionBadge`
-   `FileDropZone`
-   `SelectedFileRow`
-   `TransferProgressCard`
-   `EmptyState`
-   `LoadingState`
-   `ErrorState`
-   `CastingSourceSelector`
-   `MediaPlayerSurface`
-   `PlaybackControls`
-   `SubtitleTrackRow`
-   `SubtitleSettingsSheet`
-   `RemoteControlPad`
-   `SettingsGroup`
-   `SettingsRow`
-   `ConfirmationDialog`
-   `Toast` / `Snackbar`

All components must use shared design tokens. Avoid one-off screen
styles unless the reference genuinely requires them.

## 8. Interaction and state design

Design all important states, not only the ideal/default screen.

### Global states

-   Initial loading
-   No devices found
-   Device discovered
-   Connecting
-   Connected
-   Disconnected
-   Permission required
-   Permission denied
-   Network unavailable
-   Recoverable error

### Transfer states

-   No files selected
-   Files selected
-   Destination selected
-   Ready to send
-   Transferring
-   Paused
-   Completed
-   Failed
-   Cancelled

### Casting states

-   Searching for receivers
-   No receiver found
-   Receiver available
-   Permission required
-   Connecting
-   Casting
-   Reconnecting
-   Stopped
-   Failed

### Player/subtitle states

-   No media selected
-   Media loading
-   Playing
-   Paused
-   Seeking
-   Subtitle list loading
-   Subtitle selected
-   No subtitles available
-   Subtitle search loading
-   Search results available
-   Downloading subtitle
-   Subtitle download failed

Never rely on color alone to communicate a state.

## 9. Accessibility and usability

-   Maintain strong contrast on dark surfaces.
-   Provide visible keyboard focus on desktop.
-   Support keyboard navigation for menus, dialogs, and player controls.
-   Give icon-only buttons descriptive accessible labels.
-   Keep mobile touch targets large.
-   Respect reduced-motion preferences.
-   Provide text alternatives for important icons and status indicators.
-   Ensure controls work with screen readers.
-   Avoid tiny secondary text and low-contrast disabled states.

## 10. Product behavior boundaries

The interface must reflect real application state.

-   Do not fabricate nearby devices, connection success, transfer
    speed/progress, or media metadata.
-   Use sample data only in an explicitly identified demo mode.
-   Clearly label unsupported or unavailable features.
-   Request screen-capture permission only when the user starts a flow
    that needs it.
-   Distinguish app-to-app casting from platform-specific TV/display
    protocols.
-   Treat OpenSubtitles as an external subtitle source and display its
    loading/error states accurately.
-   Keep UI separate from transfer, discovery, casting, and playback
    services.
-   Design empty, error, permission, and disconnected states as
    carefully as default states.

## 11. Implementation acceptance checklist

### Visual fidelity

-   [ ] Mirquova name and tagline are correct.
-   [ ] Dark navy background and surface hierarchy match the reference.
-   [ ] Blue, cyan, and violet accents are consistent.
-   [ ] Typography hierarchy is consistent.
-   [ ] Cards, buttons, fields, and chips have consistent radii and
    spacing.
-   [ ] Desktop sidebar and mobile bottom navigation match the reference
    structure.
-   [ ] Desktop and mobile feel like one coherent product.

### Screen coverage

-   [ ] Desktop Home dashboard.
-   [ ] Desktop Transfer.
-   [ ] Desktop Cast.
-   [ ] Desktop Media Player and subtitle panel.
-   [ ] Desktop TV Remote.
-   [ ] Desktop Settings.
-   [ ] Mobile Home.
-   [ ] Mobile Transfer.
-   [ ] Mobile Cast.
-   [ ] Mobile Media Player and subtitle sheet.
-   [ ] Mobile TV Remote.
-   [ ] Mobile Settings.

### Responsive and interaction quality

-   [ ] No horizontal overflow at target widths.
-   [ ] Navigation works and active states are visible.
-   [ ] Primary and secondary actions are distinct.
-   [ ] Loading, empty, error, permission, and success states are
    implemented.
-   [ ] Keyboard and touch interactions are usable.
-   [ ] UI state reflects real service state.

## 12. Codex / developer implementation prompt

> Implement the Mirquova UI/UX according to
> `MIRQUOVA_UI_UX_DESIGN_SPEC.md` and the approved desktop/mobile mockup
> image.
>
> **The mockup is the visual source of truth.** Reproduce its visual
> identity, layout hierarchy, navigation, spacing, card structure,
> colors, typography, and screen composition as closely as possible. Do
> not invent a new design system or redesign the screens.
>
> First inspect the existing repository, identify its framework and
> architecture, and report the relevant structure before changing files.
> Reuse existing conventions and components where possible. Do not
> replace working application logic just to create the UI.
>
> Implement reusable design tokens and shared components, then build
> desktop and mobile layouts for Home, Transfer, Cast, Media
> Player/Subtitles, TV Remote, and Settings. Cover the responsive
> behavior and UI states in this specification.
>
> Keep UI separate from business logic and platform services. Connect
> controls to real functionality when available. If a service is not
> implemented, use an honest disabled, placeholder, or demo state; never
> fake a successful transfer, connection, cast session, or subtitle
> download.
>
> Run the project's formatter, analyzer, tests, and build checks. Fix
> issues caused by the implementation. Summarize changed files,
> implemented screens, remaining gaps, and validation results.
>
> Do not claim pixel-perfect matching without screenshot comparison at
> the same viewport sizes. Capture desktop and mobile screenshots,
> compare them with the approved reference, and adjust spacing, sizing,
> colors, and alignment.

## 13. Keep the reference image with the project

Store the approved mockup image beside this specification:

``` text
design/
├── MIRQUOVA_UI_UX_DESIGN_SPEC.md
└── mirquova-approved-ui-mockup.png
```

When implementing, compare screenshots against the actual reference
image at matching viewport sizes. The numeric values in this document
are starting tokens; the reference image takes precedence wherever it
provides a more exact visual measurement.

**Design principle:** Mirquova should feel like one connected product
across desktop and mobile---fast, clear, modern, and visually
consistent.
