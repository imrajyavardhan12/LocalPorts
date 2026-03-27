# localports

Fast local TCP port inspector for macOS, written in Zig. Shows which processes are listening and where.

## Performance

Typical warm runs complete in ~3–5ms on Apple Silicon. First run may be slower due to disk cache.

## Requirements

- Zig 0.15.x
- macOS (Linux backend planned)

## Build

```bash
zig build -Doptimize=ReleaseFast
```

The binary is output to `./zig-out/bin/localports`.

## Install (Homebrew)

```bash
brew tap imrajyavardhan12/localports
brew install localports
```

## Usage

```bash
./zig-out/bin/localports
./zig-out/bin/localports --json
./zig-out/bin/localports --port 3000
./zig-out/bin/localports -p 3000
```

Run with `sudo` to see all system processes:

```bash
sudo ./zig-out/bin/localports
```

## Example

```
PORT   PID    PROCESS        ADDRESS
3000   12345  node           0.0.0.0
5432   67890  postgres       127.0.0.1
```
