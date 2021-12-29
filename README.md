# factorio-mod-belt-overflow
A mod for the game Factorio, causing full belts to overflow at the end.

Whenever items on a belt are unable to proceed ahead smoothly, they will fall off the belt onto a nearby tile. That tile might be empty, or it could be onto another belt, wreaking havoc on your production line.

Items can fall off at the end of a series of belts (and splitters and underground belts), at a side loading location, at a splitter being used to combine two belts, and a few other places that items can get stuck.

Suggested approaches for avoiding overflowing belts:
* Ensure demand exceeds supply, more assemblers than furnaces
* Put chests at overflow points
* Return unused materials back to the main bus
* Pull items directly from your main bus
* Use logisitic bots
* Use belt loops everywhere, so inserters won't put items on full belts
* Use direct insertion between buildings, furnace to assembler to assembler
* Use circuits and/or smart inserters to avoid over-production

Suggested approaches for minimizing damage from overflow:
* Ensure no belt terminates near another belt
* Use splitter filters or smart inserters to filter trash from belts before they reach your assemblers

Known bugs:
https://github.com/sparr/factorio-mod-belt-overflow/issues