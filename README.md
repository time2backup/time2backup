# time2backup

## A powerful backup tool using rsync, written in Bash
Backup and restore your files easely on Linux and macOS!

No dependencies, just [download it](http://jean.prunneaux.com/projects/time2backup/) and run!


## Download and install
1. [Download time2backup here](http://jean.prunneaux.com/projects/time2backup/)
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
git clone https://github.com/pruje/time2backup.git
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
Author: Jean Prunneaux [http://jean.prunneaux.com](http://jean.prunneaux.com)

Website:
[http://jean.prunneaux.com/projects/time2backup](http://jean.prunneaux.com/projects/time2backup)

Source code:
[https://github.com/pruje/time2backup](https://github.com/pruje/time2backup)
