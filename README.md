# Ruby code for AOE2DE replay

This repository contains code for reading and manipulating recorded games
from Age of Empires II: Definitive Edition.

The code depends on Ruby, and nothing else.

## Dumping

To dump some info from a recorded game, run:

    ./dump.rb FILENAME


## Merging

To merge replays from different players together so that you can
see all the chats in one replay, run:

    ./merge -o OUTPUT INPUT1 INPUT2 ...

The resulting recording will be a copy of the first input
except for some chat messages being modified or added.
Flares and view lock information in the first input are not touched.

- To view flares, you have to select the perspective the user
  who sent the flare or viewed the flare.
- The output file will only have view lock information from the
  first input file (INPUT1).

Warning: This command prints out the chat on the screen, so you
might get spoiled about the results of the game!
