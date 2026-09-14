# LibreTranslate — локальний переклад без лімітів

## 1. Підняти сервер

```bash
docker run -d --name libretranslate \
  -p 5000:5000 \
  -e LT_LOAD_ONLY=uk,en \
  --restart unless-stopped \
  libretranslate/libretranslate
```

`LT_LOAD_ONLY=uk,en` — вантажить лише потрібну пару мов, а не весь набір
(~30 мов) — суттєво швидший старт і менше диска/RAM.

Перший запуск качає моделі (кілька хвилин, кілька сотень МБ). Перевірити,
що піднялось:

```bash
curl -s http://localhost:5000/languages
```

Має повернути JSON зі списком `uk`/`en`.

## 2. Швидкий тест перекладу

```bash
curl -s -X POST http://localhost:5000/translate \
  -H "Content-Type: application/json" \
  -d '{"q": "Привіт, як справи?", "source": "uk", "target": "en", "format": "text"}'
```

## 3. Автозапуск при вході в систему

`--restart unless-stopped` вище вже подбає про це, поки в тебе увімкнений
Docker daemon при старті системи (`systemctl enable docker`, якщо ще не
ввімкнено).
