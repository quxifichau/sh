apt-get update && apt-get install -y tigervnc-standalone-server novnc websockify fluxbox x11-utils fonts-liberation
 
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
wget -O /tmp/google-chrome-stable_current_amd64.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
dpkg -i /tmp/google-chrome-stable_current_amd64.deb
apt-get install -y -f
rm -rf ~/cdp
mkdir -p ~/cdp
 
npm install -g @playwright/cli@latest
mkdir -p ~/.playwright
cat > ~/.playwright/cli.config.json <<'PWCF'
{
  "browser": {
    "cdpEndpoint": "http://127.0.0.1:9222"
  }
}
PWCF
 
curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
pip install crawl4ai 
# cd /workspace
npx skills add brettdavies/crawl4ai-skill --skill crawl4ai --yes
 
f="$(python3 -c 'import crawl4ai,os;print(os.path.dirname(crawl4ai.__file__))')/async_configs.py"
sed -i \
  -e 's/browser_mode: str = "dedicated"/browser_mode: str = "custom"/' \
  -e 's|cdp_url: str = None|cdp_url: str = "http://127.0.0.1:9222"|' \
  "$f"
  
echo "=== Chrome ===" && google-chrome-stable --version
echo "=== uv ===" && uv --version
echo "=== uvx ===" && uvx --version
echo "=== crwl ===" && which crwl
echo "=== crawl4ai skill ===" && ls -la .agents/skills/crawl4ai/
echo "=== cdp_url ===" && grep -n 'cdp_url: str' "$f" | head -2

# ==============write functions===========================

cat > ~/.functions.sh <<'FUNCTION'
vnc() {
  pkill -f Xtigervnc; pkill -f fluxbox; pkill -f websockify
  sleep 1
  rm -rf ~/.fluxbox
  rm -f /tmp/.X99-lock /tmp/.X11-unix/X99
  Xtigervnc :99 -geometry 2560x1440 -depth 24 -SecurityTypes None -AlwaysShared -rfbport 5900 >/dev/null 2>&1 &
  export DISPLAY=:99
  for i in $(seq 1 30); do [ -S /tmp/.X11-unix/X99 ] && break; sleep 0.2; done
  fluxbox >/dev/null 2>&1 &
  websockify --web=/usr/share/novnc 6080 localhost:5900 >/dev/null 2>&1 &
}
chpw() {
  pkill -f google-chrome-stable; pkill -f playwright-cli
  google-chrome-stable \
      --user-data-dir=$HOME/cdp \
      --remote-debugging-port=9222 \
      --remote-debugging-address=0.0.0.0 \
      --window-size=800,600 \
      --start-maximized \
      --disable-gpu \
      --no-first-run \
      --no-sandbox \
      "https://example.com" chrome.log 2>&1 &
}
FUNCTION

grep -qxF '. ~/.functions.sh' ~/.zshrc || echo '. ~/.functions.sh' >> ~/.zshrc
grep -qxF '. ~/.functions.sh' ~/.bashrc || echo '. ~/.functions.sh' >> ~/.bashrc

. ~/.bashrc
. ~/.zshrc
