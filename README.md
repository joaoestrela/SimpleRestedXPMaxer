# SimpleRestedXPMaxer

A small World of Warcraft addon that shows how much rested XP you have on the main experience bar, and tells you when you have hit the rested cap.

The bar text gains a suffix such as `Rested: 87.5%`, which turns green and reads `(CAPPED)` once rested XP reaches the cap.

Hovering the XP bar adds a section to its tooltip with your rested XP, the cap, how much is left, and how long you still need to rest to reach the cap, both at an inn or city (5% of a level every 8 hours) and outside one (a quarter of that rate).

## How the cap is worked out

The base cap is 150% of the current level's XP. Each rank of the **Well Rested** node in the Adventure talent tree (tree `1188`, node `110301`) raises it by 4%, and also makes rested XP build 4% faster, so the tooltip's time-to-cap accounts for both. The addon re-reads the rank on every XP, rested or talent event, so a rank that is not loaded yet at login is picked up shortly after.

## Install

Copy the `SimpleRestedXPMaxer` folder (with `SimpleRestedXPMaxer.toc` and `SimpleRestedXPMaxer.lua`) into your game's `Interface/AddOns` directory, then reload the UI or restart the game.

## License

[MIT](LICENSE)
