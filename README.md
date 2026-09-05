# Omarchy Anime

Track the current anime season right from your status bar. A badge shows how
many shows are listed this season; click it to browse the full season, filter
it down, and start downloads of individual episodes without leaving the shell.

## Features

- **Status bar badge** — a live count of the season's shows
- **Full season browser** — every show MAL lists this season (airing,
  finished, or still upcoming), with cover art, score, type, status and
  genres, grouped by airing day
- **Your local timezone** — broadcast slots are converted from JST to your
  system's time, so shows land under the weekday and time you actually see
- **New / sequel badges** — first seasons vs. continuations (e.g. "S4")
- **Instant filters** — type to search titles, or tap a genre chip (all MAL
  genres, incl. Harem/Ecchi); the list narrows as you go
- **Pagination** — comfortable browsing through large seasons
- **One-click downloads** — pick a show, pick the episode: released episodes
  are found automatically (SubsPlease first, then Nyaa) and fetched by a
  lightweight `aria2c`
- **Live progress** — the picker shows a progress bar, percent, speed and ETA
  per download, and finished episodes open their save folder on click
- **Downloads survive restarts** — in-flight transfers keep running even if
  the shell reloads or restarts, and reappear in the picker with their
  progress intact
- **Stale-friendly** — the list never flashes empty on a failed refresh; it
  keeps the last good data and retries

## Installation

```bash
omarchy plugin add https://github.com/azzenabidi/omarchy-anime.git --enable
```

Install `aria2` if you want downloads:

```bash
omarchy pkg add aria2
```

The shell hot-reloads the widget on save. Find the new widget in your bar
layout with:

```bash
omarchy bar list
```

## Settings

Configure the widget under `azzen.anime` in `~/.config/omarchy/shell.json`:

| Setting | Default | Description |
|---|---|---|
| `refreshMinutes` | `60` | How often to refresh the season list |
| `downloadDir` | `~/Downloads` | Where episodes are saved |

## Usage

1. Click the badge to open the season list.
2. Use the search box or genre chips to narrow it down.
3. Click a show's download button to open its episode picker.
4. Click an episode to start downloading — follow the live progress bar.
5. `Esc` or the back arrow returns to the season list.

## Credits

- Season data: [MyAnimeList](https://myanimelist.net)
- Episode releases: [SubsPlease](https://subsplease.org) and [Nyaa](https://nyaa.si)
- Downloads: [aria2](https://aria2.github.io)

## License

[MIT](LICENSE)