# Guess Your Gay Song (GYGS for short)

Guess Your Gay Song is a game about guessing songs (obviously).

## Free play

In free play the game picks a random song from your indexed library and picks a fragment to play.
If you can guess right you score points, congratulations, you can proceed with the next song!
But if you didn't guess, you can use hints to help you out, or if you not having any luck guessing, you can reveal the answer.
You can also limit selection of music to specific artists if you want to see how much of a fan you really are.

## Survival play

Survival play limits amount of wrong guesses you can make to 10 but your records can be added to the scoreboard.
Just like in free play, you can also limit the artists that are featured in random picks so now your knowledge can be truly challenged.

## Installation

Ensure you have `ffplay` and `ffprobe` available in your system PATH
```shell
ffplay
ffprobe
```
If any of these commands are missing, install system-wide ffmpeg according to your distribution instructions.

Once you ensure everything is installed:
Clone the repository and move into it
```shell
git clone https://github.com/rutarita/guess_your_gay_music/
cd guess_your_gay_music
```

Build the executable
```shell
shards build --release --no-debug
```

Run the executable
```shell
cd bin
./guess_your_gay_music
```

Now you will see the game menu menu and you will be asked to create index of your music folder by entering command 'rei'/
After you enter this command, you will be prompted to enter you music folder path, which is what you should do.
Wait until the indexing is done and you are ready to play!

## Usage

TODO: Write usage instructions here

## Development

TODO: Write development instructions here

## Contributing

1. Fork it (<https://github.com/rutarita/guess_your_gay_music/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [rutarita](https://github.com/rutarita) - creator and maintainer
