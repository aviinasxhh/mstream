# mstream

`mstream` is a lightweight, incredibly fast music streaming CLI tool written entirely in Bash. It allows you to search, play, and manage music playlists directly from your terminal, without a heavy UI, leveraging the power of `yt-dlp` and `mpv`.

## Features
- **Instant Search & Play**: Find and play high-quality audio tracks instantly from the command line.
- **Background Streaming**: Built-in interactive shell (`mstream>`) lets you queue songs, skip tracks, and manage playlists seamlessly while music plays in the background.
- **Local Playlists**: Create, manage, and shuffle your own personal music playlists locally.

## Prerequisites
You need the following installed on your system:
- `mpv`
- `yt-dlp`

You can install these using your system's package manager:
```bash
# Ubuntu / Debian
sudo apt install mpv yt-dlp

# Arch Linux
sudo pacman -S mpv yt-dlp

# macOS
brew install mpv yt-dlp
```

## Installation

### Method 1: Global Install (Recommended)
This installs `mstream` globally on your system, exactly like `ani-cli`.

1. Clone the repository:
```bash
git clone https://github.com/yourusername/mstream.git
cd mstream
```

2. Install it globally using `make`:
```bash
sudo make install
```
You can now run `mstream` from anywhere in your terminal! 

*(To uninstall later, you can run `sudo make uninstall` inside the folder).*

### Method 2: Portable Install
If you don't have root access or just want to run it from a folder:
```bash
git clone https://github.com/yourusername/mstream.git
cd mstream
chmod +x mstream.sh
./mstream.sh
```

## Usage

Simply run the script to enter the interactive shell:
```bash
./mstream.sh
```
Or execute a command directly from your terminal:
```bash
./mstream.sh play blinding lights
```

### Commands

Once inside the `mstream>` shell:

- `play <query>`: Instantly search and queue the top result.
- `search <query>`: Interactively search and select a song from a list.
- `pause` / `resume`: Control background playback.
- `skip`: Skip the current track.
- `clear`: Clear the upcoming queue.
- `add <playlist_name> <query>`: Add a song to a local playlist.
- `list`: View all your saved playlists.
- `playlist <playlist_name> [shuffle]`: Queue an entire playlist. Add `shuffle` to randomize it.
- `quit`: Exit and stop all music.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
