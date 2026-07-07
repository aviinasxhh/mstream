# Contributing to mstream

First off, thank you for considering contributing to `mstream`! 

We want to keep this project lightweight, blazing fast, and incredibly reliable. To maintain this standard, we have a few strict guidelines for contributors.

## 🚫 No "Vibe Coding"

We take engineering rigor seriously. We do not accept PRs from "vibe coders" (coding without understanding, guessing syntax, failing to test edge cases, or throwing code at the wall until it sticks). 

Before submitting a Pull Request, you must ensure:
1. **You fully understand the code you are modifying.**
2. **You have thoroughly tested your changes.** (Test it against missing dependencies, weird characters in search queries, and abrupt terminal exits).
3. **Your code is clean and readable.**

## Guidelines

- **Stay 100% Native Bash**: Do not introduce dependencies on Python, Node, Ruby, or other heavy runtimes. The beauty of this project is that it requires nothing more than `bash`, `yt-dlp`, and `mpv`.
- **Keep it POSIX-friendly where possible**: While we use Bash-specific features (like arrays and `[[ ]]`), try to avoid overly obscure bashisms that make the code impossible to read.
- **Maintain UI consistency**: If you add a new command or output, use the existing terminal color codes and keep the output clean.
- **Lowercase Comments**: By convention in this project, keep inline code comments entirely in lowercase.

## How to Submit a Pull Request

1. Fork the repository.
2. Create a new branch for your feature (`git checkout -b feature/amazing-feature`).
3. Commit your changes (`git commit -m 'Add amazing feature'`).
4. Push to the branch (`git push origin feature/amazing-feature`).
5. Open a Pull Request and clearly describe *what* you changed, *why* you changed it, and *how* you tested it.

Thank you for helping make `mstream` better!
