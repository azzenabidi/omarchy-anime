# Omarchy Anime

An Omarchy shell plugin that keeps track of the current anime season on your
status bar and lets you download episodes straight from the popup.

It pulls the current season's shows from MyAnimeList (via the MAL-based
Jikan API), lists **every** entry of the season — currently airing, finished
while the season ran, and still upcoming — with each show's airing day/time
in a panel, and — with a click on a show's download button — looks up
released episodes on SubsPlease (720p `[SubsPlease]` releases), falling back
to Nyaa (English-subbed 720p), and hands the chosen magnet to a headless
`aria2c` download.

## Features

- **Status bar badge** with the number of anime in the current season
- **Season panel**: cover art, title, airing day/time (JST), type, airing
  status, score and genres for every show listed on MAL for the season
- **New / sequel badges** (S1 drops the badge, later parts are tagged, e.g.
  "S4")
- **Pagination** for large seasons
- **Episode downloader**:
  - per-show download button opens an episode picker
  - looks up released episodes on **SubsPlease** first (`[SubsPlease]` 720p)
    with a smart title matcher (STOP-word filtering, season-aware grouping —
    correctly matching e.g. "Ascendance of a Bookworm S4" over the original)
  - falls back to **Nyaa** for English-subbed 720p releases when SubsPlease
    has nothing, filtering out batches/specials/movies
  - pick the exact episode, and a headless `aria2c --seed-time=0` grabs the
    magnet into your configured download folder
  - **Live download progress**: each started download shows a progress bar in
    the episode picker (percent, downloaded/total, transfer speed and ETA),
    updated by polling aria2c's per-download log file until it finishes;
    completed rows show the save folder and open it on click
  - **Survives restarts**: downloads run detached from the shell, so closing
    the panel, reloading the plugin, or restarting Quickshell won't kill an
    in-progress transfer — the episode picker re-adopts still-running
    downloads (progress, save folder) from their registry on the next load
- **Stale-friendly refresh**: the list is kept across failed refreshes so the
  popup never flashes empty, with automatic retries
- Finished/upcoming entries are tagged with their status (e.g. "Finished
  Airing") instead of being hidden

## Dependencies

- `aria2c` (for downloads) — `omarchy pkg add aria2`
- `jq`, `node` (only if you run the helper scripts by hand; the plugin itself
  uses the bundled stdlib-only `anime-fetch` helper)

## Installation

```bash
# 1. Add the plugin from git and enable it
omarchy plugin add https://github.com/azzenabidi/omarchy-anime.git --enable

# 2. Install aria2 if you want downloads
omarchy pkg add aria2

# 3. The bar widget should now appear; find it in the layout with:
omarchy bar list
```

The shell hot-reloads the widget on save — no restart needed.

## Settings

Settings live in `~/.config/omarchy/shell.json` under the widget config for
`azzen.anime`.

| Setting | Default | Description |
|---|---|---|
| `refreshMinutes` | `60` | How often to refresh the season list (min 5) |
| `refreshMinutes` | `60` | How often to refresh the season list (min 5) |
| `maxItems` | `30` | Max anime shown in the popup |
| `downloadDir` | `~/Downloads` | Folder `aria2c` saves downloads into |

## Usage

1. Click the badge (shows the airing count) to open the panel.
2. Find a show and click its download button (**download icon**, right side of
   the row).
3. The panel switches to an episode picker — click any episode to start the
   download. A live progress bar (percent, speed, ETA) tracks each download
   under the episode list until it completes.
4. `Esc` or the back button returns to the season list.

## Helper script

`anime-fetch` is a self-contained Python 3 (stdlib only) script, also usable
directly:

```bash
# Check for aria2c
~/.config/omarchy/plugins/azzen.anime/anime-fetch --check

# Look up a show's released episodes (SubsPlease, then Nyaa)
~/.config/omarchy/plugins/azzen.anime/anime-fetch "<romaji>" "<english>" "<japanese>"

# Download an episode via a detached aria2c (prints {ok, pid, dir, log};
# live progress is in the log file)
~/.config/omarchy/plugins/azzen.anime/anime-fetch download "<magnet>" "<show>" "<ep>" "~/Downloads"
```

## Credits

- Season data: [MyAnimeList](https://myanimelist.net) via the Jikan API
- Releases: [SubsPlease](https://subsplease.org) and [Nyaa](https://nyaa.si)
- Icon: FontAwesome (used via the bundled Ui toolkit)

## License

[MIT](LICENSE)