# 🐦 Birdwatchers Pasta & Stuff

A one-page restaurant website for the family gag. One glorious dish, three
drinks, and a QR code so people can scan their way to the menu.

## Run it (one command)

From inside this `site/` folder:

```bash
python3 serve.py
```

That's it — no installs needed. You'll see something like:

```
On this computer : http://localhost:8000/
On your phone    : http://192.168.1.42:8000/
Big QR to show   : http://192.168.1.42:8000/qr
```

- **On the same computer:** open the `localhost` link.
- **On a phone (same Wi-Fi):** scan the QR code printed in the terminal, or
  open the `Big QR to show` link on your screen and have guests scan that.

Press `Ctrl+C` to stop the server.

> Phones must be on the **same Wi-Fi** as the computer running the server.
> If a phone can't connect, your firewall may be blocking port 8000.

### Different port?

```bash
PORT=8080 python3 serve.py
```

## Adding your About photos

Drop your photos into the `images/` folder named:

- `about-1.jpg` (big top photo)
- `about-2.jpg`
- `about-3.jpg`

`.jpg` or `.png` both work — if you use `.png`, open `index.html` and change
the three `about-1.jpg` style filenames to `.png`. Until photos are added,
tidy placeholders show automatically.

## Files

| File            | What it is                                  |
|-----------------|---------------------------------------------|
| `index.html`    | The website                                 |
| `styles.css`    | All the styling                             |
| `serve.py`      | Local server + QR code generator            |
| `images/`       | Put your About photos here                  |
| `vendor/`       | Bundled QR library (no pip install needed)  |
