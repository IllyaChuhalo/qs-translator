# LibreTranslate — local translation without limits

## 1. Start the server

```bash
docker run -d --name libretranslate \
  -p 5000:5000 \
  -e LT_LOAD_ONLY=uk,en \
  --restart unless-stopped \
  libretranslate/libretranslate
```

`LT_LOAD_ONLY=uk,en` loads only the required language pair instead of the
whole set (~30 languages), which means a much faster startup and less disk/RAM
usage.

The first run downloads the models (a few minutes, a few hundred MB). Check
that it is up:

```bash
curl -s http://localhost:5000/languages
```

It should return JSON with the `uk`/`en` languages.

## 2. Quick translation test

```bash
curl -s -X POST http://localhost:5000/translate \
  -H "Content-Type: application/json" \
  -d '{"q": "Привіт, як справи?", "source": "uk", "target": "en", "format": "text"}'
```

## 3. Autostart on login

`--restart unless-stopped` above already takes care of this, as long as the
Docker daemon is enabled at system startup (`systemctl enable docker`, if it is
not enabled yet).
