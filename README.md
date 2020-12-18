# Ruby code for AOE2DE replays

This repository contains code for reading and manipulating recorded games
from Age of Empires II: Definitive Edition.

The code depends on Ruby, and nothing else.

## Dumping

To dump some info from a recorded game, run:

    ./dump.rb FILENAME


## Merging

To merge replays from different players together so that you can
see all the chats in one replay, run:

    ./merge.rb -o OUTPUT INPUT1 INPUT2 ...

The resulting recording will be a copy of the first
full-length input (which we call the main input) except for some
chat messages being modified or added.
Flares and view lock information of this main input are not touched.

- To view flares, you have to select the perspective of the user
  who sent the flare or saw the flare.
- The output file will only have view lock information from the
  main input.

Warning: This command prints out the chat on the screen, so you
might get spoiled about the results of the game!

There is also a command that automates the process of downloading
a match using aoe2.net and aoe.ms, and then merges it.  For details,
run `./download_and_merge.rb` with no arguments.
