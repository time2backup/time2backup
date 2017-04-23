# time2backup
## A powerful backup tool using rsync, written in Bash
Backup and restore your files easely on Linux and macOS!

No dependencies, just [download it](https://time2backup.github.io/) and run!


## Why another backup tool? Why is it written in Bash?
time2backup wants to be as light as possible, working without any dependencies.
All you need is just bash and rsync.

Run it on any Linux/macOS system, it will work out of the box.
You can also put time2backup on a USB stick/external disk drive and use it in portable mode.


## Download and install
1. [Download time2backup here](https://time2backup.github.io/)
2. Uncompress archive where you want
3. Run the `time2backup.sh` file in a terminal or just by clicking on it in your file explorer
4. Then follow the instructions.


## Command usage
```bash
/path/to/time2backup.sh [GLOBAL_OPTIONS] [COMMAND] [OPTIONS]
```
For more usage, see the [command help](docs/command.md).


## Documentation
For global usage, see the [user manual](docs/user_manual.md).


## Install from sources (developers edition)
Follow theses steps to install time2backup from last sources:
1. Clone this repository:
```bash
git clone https://github.com/time2backup/time2backup.git
```
2. Go into the folder:
```bash
cd time2backup
```
3. Initialize and update the libbash submodule:
```bash
git submodule update --init --recursive
```

If you want to use the unstable version, go on the `unstable` branch:
```bash
git checkout unstable
```

To download the last updates, to:
```bash
git pull
```

## License
time2backup is licensed under the MIT License. See [LICENSE.md](LICENSE.md) for the full license text.

## Credits
Author: Jean Prunneaux http://jean.prunneaux.com

Website: https://time2backup.github.io

Source code: https://github.com/time2backup/time2backup
