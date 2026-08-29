## 1.58.1
**Character Panel:**
- The resistance tooltips now rate the value: how much matching spell damage you resist on average against boss enemies, by the game's own formula, plus a colored verdict from Low to Maximum.

**Loadouts:**
- Two copies of the same item that differ only in their gems or enchants now swap correctly when switching sets. A regemmed single copy still counts as equipped and is never reported missing. If a set was saved before the gems went in, save it once more while wearing the right copy.

**Performance:**
- A sweep over thirteen files cuts memory churn and idle work in hot paths: timer texts only rebuild when their value changes, the trinket queue checks once per second instead of every frame, the arena binds its aura events per zone, and the dark skin, bags, tooltips and class trackers reuse what they already computed.
