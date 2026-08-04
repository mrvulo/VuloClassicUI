## 1.52.1
**Action Bars:**
- **NEW: Keep the main bar on its page in every form** – Cat, bear, stealth, stances and Shadowform stop swapping action bar 1 to a page of their own
- The ticker that paints cooldown dimming and range colouring no longer walks switched-off bars. It read and repainted every action bar five times a second, including the ones whose buttons nobody can see, so running two bars cost as much as running all of them.
- Leaving a button no longer builds a fresh check each time. The check only ever reads the bar, not the button, so it is built once per bar and shared by all of its buttons.

**Arena:**
- The opponent frames are left alone unless you actually asked for a different arrangement. They are protected frames: anchoring one from our side is allowed outside a fight, but it marks the frame for the rest of the session, and the next time the default interface repositions it during a round its own call is refused and the block is reported against us. There is no way to anchor a protected frame without leaving that mark, so an untouched setup now keeps the default stacking. Order, spacing, grow direction and slot offsets all still work — the message becomes the price of a feature you asked for rather than something every arena hands out for free.

**Bags:**
- Move up and move down work again on a category you switched off and back on. The order list was filled once, while it was still empty, so anything that did not exist at that moment never got an entry, and its arrows then did nothing at all for the rest of the session without saying so.

**Under the hood:**
- Switching a module off releases its event handlers again. The note recording which module owns a handler stayed behind when the handler was unregistered, and that note kept a hard reference to every handler the module had ever registered.
