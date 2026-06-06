# VHS tape for the localports README demo.
# Regenerate with:  vhs assets/demo.tape   (requires localports + docker;
# the --tree shot uses whatever real process is listening on :3000)

Output assets/demo.gif

Require localports

Set Shell "bash"
Set FontSize 14
Set Width 1200
Set Height 600
Set Padding 20
Set Theme "Catppuccin Mocha"
Set TypingSpeed 50ms

# --- Hidden setup: a container + a dummy server to kill ---
Hide
Type `export PS1="❯ "`
Enter
Type "docker run -d --rm -p 5432:5432 -e POSTGRES_PASSWORD=x --name demo-pg postgres:16-alpine >/dev/null 2>&1"
Enter
Type "python3 -m http.server 9999 --bind 127.0.0.1 &>/dev/null &"
Enter
Type "sleep 4 && clear"
Enter
Sleep 5s
Show

# --- Who and what command is on the port ---
Type "localports -p 7265 --verbose"
Sleep 700ms
Enter
Sleep 3s

# --- Drill into one process's ancestry (unique) ---
Type "localports 3000 --tree"
Sleep 700ms
Enter
Sleep 3s

# --- Find and safely kill the process on port 9999 ---
Type "localports 9999"
Sleep 700ms
Enter
Sleep 2s

Type "localports --kill 9999"
Sleep 700ms
Enter
Sleep 500ms
Type "y"
Sleep 300ms
Enter
Sleep 2s

Type "localports 9999"
Sleep 700ms
Enter
Sleep 2s

# --- Resolve the Docker mystery port to its container ---
Type "localports 5432 --docker"
Sleep 700ms
Enter
Sleep 3s

# --- Hidden teardown ---
Hide
Type "kill $(lsof -ti:9999) 2>/dev/null; true"
Enter
Type "docker rm -f demo-pg >/dev/null 2>&1"
Enter
Sleep 1s
