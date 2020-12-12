# Ruby code for AOE2DE replay

This repository contains code for reading and manipulating recorded games
from Age of Empires II: Definitive Edition.

The code depends on Ruby, and nothing else.

## Dumping

To dump some info from a recorded game, run:

    ./dump.rb FILENAME


## Merging

To merge together multiple replays from different players together
so that you can see all the chats in one replay, run:

    ./merge -o OUTPUT INPUT1 INPUT2 ...

The resulting recording will be a copy of the first input
except for some chat messages being modified or added.

Flares and view lock information are not merged (yet).
So if you care about flares and view lock, the first input (INPUT1)
should be recording with the information you wish to preserve.

Warning: This command prints out the chat on the screen, so you
might get spoiled about the results of the game!
