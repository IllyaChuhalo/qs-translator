# translator — Quickshell Popup for ii / dots-hyprland

Popup перекладач (uk ↔ en), Voice Input зі стрімінговим розпізнаванням мови в реальному часі та інтегрованим AI-полішингом тексту (SLM Qwen 2.5) під Hyprland + Quickshell. Візуально та тематично узгоджений з [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland) ("ii").

Живе в окремому конфізі Quickshell (`qs -c translator`) — **не форк і не патч самого `ii`**, тож оновлення dots-hyprland його не зачіпають.

---

## Можливості

- **Layer-shell Popup (Overlay)**: Floating-вікно по центру внизу екрана, не резервує простір та не зсуває інші тайлові вікна.
- **Двостороннє відстеження мови**: Напрямок перекладу автоматично синхронізується з поточною розкладкою клавіатури Hyprland (`uk ↔ en`), включно зі зміною розкладки прямо під час набору чи розпізнавання.
- **Dual-Engine Streaming STT (Голосовий ввід)**:
  - **Миттєвий стрімінг**: При вимові слова частковий текст (`PARTIAL:`) з'являється в полі вводу кожні ~300 мс (завдяки легкій моделі Whisper `base`).
  - **Фінальна точність**: По завершенню фрази (авто-детекція тиші VAD або ручний клік) застосовується високоточна модель Whisper `medium` (або `small` на CPU).
  - **Апаратне прискорення GPU (CUDA)**: Інференс на відеокарті NVIDIA RTX займає всього **~0.7 с** для 5-секундного аудіо (у 7 разів швидше за CPU). При відсутності GPU автоматично використовується оптимізований мультипотоковий CPU AVX2.
  - **Живий аудіо-візуалізатор**: Анімований рівень гучності мікрофона в кнопці під час мовлення.
- **AI Polish (Авторедактор тексту на базі Qwen 2.5 1.5B)**:
  - Локальна нейромережа виправляє слова-паразити (*ну*, *типу*, *короче*), обмовки, опечатки, пропущені апострофи (*комп'ютер*, *зв'язок*) та розставляє розділові знаки перед відправкою на переклад.
  - Кнопка зірочок (`auto_awesome`) всередині поля вводу дозволяє вмикати або вимикати авторедагування в один клік.
- **Розумний бекенд перекладу**: Спершу використовує швидкий Google Translate (gtx); у разі тимчасового обмеження за запитами (HTTP 429) автоматично перемикається на локальний контейнер LibreTranslate.
- **Швидка дія**: `Enter` копіює готовий переклад у буфер обміну та автоматично вставляє у вікно, з якого викликали віджет (`wl-copy` + `wtype`). `Escape` — закриває без вставки.
- **Адаптивна палітра**: Кольори та радіуси беруться безпосередньо з живої matugen-палітри `ii` (`colors.json`).

---

## Встановлення

Всі залежності, Python venv, конфіги Quickshell, перевірка GPU та завантаження моделей автоматизовані в одному скрипті:

```bash
git clone <this-repo> translator && cd translator
./scripts/install.sh
```

Під час виконання інсталятор:
1. Перевірить системні бінарники (`pw-record`, `wtype`, `wl-copy`, `hyprctl`, `python3`, `qs`).
2. Скопіює файли інтерфейсу та бекенду в `~/.config/quickshell/translator/`.
3. Створить ізольований віртуальний Python-енвайронмент (`~/.local/share/translator-stt-venv`).
4. **Виявить відеокарту**: якщо знайдено NVIDIA GPU, запропонує увімкнути прискорення **CUDA 12** та автоматично підтягне необхідні рантайм-пакунки (`nvidia-cublas-cu12`, `nvidia-cudnn-cu12`).
5. Перевірить наявність та завантажить локальні моделі (faster-whisper та Qwen 2.5 1.5B GGUF).

---

## Налаштування шорткату в Hyprland

Додайте виклик віджета до вашого `~/.config/hypr/custom/keybinds.lua`:

```lua
-- Виклик попапу перекладача (наприклад, Super + T):
bind({ "SUPER" }, "T", function()
    awm.spawn("qs -c translator ipc call translator toggle")
end)
```

Після додавання перезавантажте конфігурацію:
```bash
hyprctl reload
```

---

## Архітектура

```
+-------------------------------------------------------------------------+
|                         Quickshell GUI (shell.qml)                      |
|  - WlrLayershell Overlay                                                |
|  - TextInput (inputField)  <---+                                        |
|  - MultiEffect Rounded Shimmer | (PARTIAL: / RESULT: / POLISHED:)       |
|  - Dynamic Matugen Theming     |                                        |
+--------------------------------+----------------------------------------+
                                 |  stdin / stdout (IPC)
                                 v
+-------------------------------------------------------------------------+
|                       STT & SLM Daemon (stt_daemon.py)                  |
|                                                                         |
|  [Hardware Layer]                                                       |
|    - NVIDIA CUDA Dynamic Loader (ctypes CDLL preloader)                 |
|    - Auto-detection: CUDA (float16) <---> CPU AVX2 (int8)               |
|                                                                         |
|  [Streaming Engine] (Whisper "base")                                    |
|    - Decoupled background thread reading PCM buffer every ~300ms        |
|    - Emits: PARTIAL:<text>                                              |
|                                                                         |
|  [Final Engine] (Whisper "medium" on GPU / "small" on CPU)              |
|    - High beam-size transcription upon silence (VAD)                    |
|    - Emits: RESULT:<text>                                               |
|                                                                         |
|  [AI Polish Engine] (Qwen 2.5 1.5B Instruct GGUF via llama-cpp)         |
|    - ChatML prompt tuned for UK/EN speech cleanup and typos             |
|    - Emits: POLISHED:<text>                                             |
+-------------------------------------------------------------------------+
```

### Протокол демона (по рядках через stdin / stdout)

| Команда (stdin) | Опис |
|---|---|
| `START` | Почати запис аудіо з автоматичним визначенням мови |
| `START:<lang>` | Почати запис з підказкою мови (`START:uk` або `START:en`) |
| `STOP` | Примусово зупинити запис і перейти до транскрипції |
| `POLISH:<text>` | Відправити текст на обробку моделі Qwen 2.5 1.5B |

| Подія (stdout) | Значення |
|---|---|
| `LOADING` | Фонове завантаження моделей |
| `STREAM_READY` | Стрімінгова модель Whisper base готова до роботи |
| `MODEL_READY` | Фінальна модель готова |
| `DEVICE:<device>` | Поточний бекенд виконання (`cuda` або `cpu`) |
| `POLISH_READY` | Модель AI Polish готова |
| `LISTENING` | Йде захоплення аудіо з PipeWire |
| `LEVEL:<0.0-1.0>` | Амплітуда мікрофона для візуалізатора в реальному часі |
| `PARTIAL:<text>` | Частковий розпізнаний текст прямо під час мовлення |
| `PROCESSING` | Обробка фінального аудіо |
| `RESULT:<text>` | Фінальний результат розпізнавання |
| `POLISHED:<text>` | Очищений і виправлений текст після AI Polish |
| `ERROR:<msg>` | Повідомлення про помилку |

---

## Налаштування параметрів

| Параметр | Файл | Значення | Призначення |
|---|---|---|---|
| Поріг тиші (VAD) | `stt/stt_daemon.py` | `0.032` | Відсікання шуму дихання та кімнати |
| Тривалість тиші для авто-стопу | `stt/stt_daemon.py` | `550` мс | Пауза після фрази перед завершенням запису |
| Keep-alive демона | `qs/shell.qml` | `45000` мс | Час утримання моделі в пам'яті після закриття вікна |
| Дебаунс перекладу | `qs/shell.qml` | `550` мс | Затримка перед HTTP-запитом перекладу |
| Модель AI Polish | `download_models.sh` | `Qwen 2.5 1.5B Q4_K_M` | Шлях у `~/.local/share/translator/models/` |

---

## Ручне тестування

Запуск QuickShell віджета вручну для перегляду логів у терміналі:
```bash
qs -c translator
```

В окремому терміналі перемикання видимості попапу:
```bash
qs -c translator ipc call translator toggle
```

Тест STT демона напряму з командного рядка:
```bash
~/.local/share/translator-stt-venv/bin/python ~/.config/quickshell/translator/stt_daemon.py
```
Введіть `START:uk`, скажіть кілька слів і натисніть Enter або зачекайте на авто-зупинку по тиші.
