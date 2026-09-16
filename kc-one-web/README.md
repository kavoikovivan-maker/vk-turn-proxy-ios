# K&C One Web

Первый набор инструментов K&C, который работает без подписи iOS:

- устанавливается на экран iPhone как PWA;
- открывается как Telegram Mini App;
- работает офлайн после первого запуска;
- не отправляет выбранные фотографии, тексты и пароли на сервер.

## Локальный запуск

```sh
python3 -m http.server 4173 -d kc-one-web
```

Откройте `http://127.0.0.1:4173`.

Для установки на iPhone нужен HTTPS-адрес: Safari → «Поделиться» → «На экран Домой».

## Telegram Mini App

После публикации по HTTPS укажите URL в BotFather: `/mybots` → бот → Bot Settings → Configure Mini App.
