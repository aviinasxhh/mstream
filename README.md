<p align=center>
<br>
<a href="Linux"><img src="https://img.shields.io/badge/os-linux-brightgreen">
<a href="MacOS"><img src="https://img.shields.io/badge/os-mac-brightgreen">  
<a href="Windows"><img src="https://img.shields.io/badge/os-windows-brightgreen">
<br>
<p align=center>
<a href="https://discord.gg/YeY8jeakFY"><img src="https://invidget.switchblade.xyz/YeY8jeakFY"></a>
</p>
<p align=center>  
<a href="https://github.com/aviinasxhh"><img src="https://img.shields.io/badge/lead-aviinasxhh-lightblue"></a> 
</p>  

<h3 align="center">
Mstream is a lightweight, incredibly fast music streaming CLI tool written entirely in Bash. It allows you to search, play, and manage music playlists directly from your terminal.
</h3>

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
This installs `mstream` globally on your system.

1. Clone the repository:
```bash
git clone https://github.com/aviinasxhh/mstream.git
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
git clone https://github.com/aviinasxhh/mstream.git
cd mstream
chmod +x mstream.sh
./mstream.sh
```

### Windows & macOS Support
- **macOS**: Fully supported! You can use `sudo make install` just like on Linux. Just make sure you install the prerequisites first using `brew install mpv yt-dlp`.
- **Windows**: Windows does not natively support `make` or Bash scripts. However, you can easily use `mstream` by installing [Git Bash](https://gitforwindows.org/) or [WSL](https://learn.microsoft.com/en-us/windows/wsl/install). Open Git Bash, clone the repository, and use **Method 2 (Portable Install)**. Ensure you have downloaded the Windows executables for `mpv` and `yt-dlp` and added them to your system PATH!

## Usage

Simply run the script to enter the interactive shell:
```bash
./mstream.sh
```
Or execute a command directly from your terminal:
```bash
./mstream.sh play blinding lights
```

### Basic Commands

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

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](https://github.com/aviinasxhh/mstream/blob/master/LICENSE) file for details.

## Disclaimer

This project does not host, store, or distribute any copyrighted content — it simply streams audio by interacting with publicly available third-party data sources.

- Users are solely responsible for ensuring their use of this tool complies with the **terms of service** of any third-party platforms it interacts with, applicable copyright law, and any other relevant regulations in their jurisdiction.
- This project is **not affiliated with, endorsed by, or sponsored by** any third-party platform it may interact with.
- The developer(s) of this project assume **no liability** for misuse of this tool, including but not limited to copyright infringement, violation of third-party terms of service, or any other unlawful use.
- Use at your own risk. If you are a rights holder and believe this project infringes on your rights, please open an issue and it will be addressed promptly.
