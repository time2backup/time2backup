# time2backup

## A simple and powerful backup tool using rsync
Backup and restore your files easily with time2backup on Linux, macOS and Windows!

time2backup wants to be as light as possible and needs only rsync installed.
Download it and run it!


## Why is it written in Bash?
To be useful on every computer or server, time2backup is written in bash,
without require any framework or specific language.

time2backup is powered by [libbash.sh](https://github.com/pruje/libbash.sh),
a library of functions for Bash scripts.


## Download and install
1. [Download time2backup here](https://time2backup.org)
2. Uncompress archive where you want
3. Run the `time2backup.sh` file in a terminal or just by clicking on it in your file explorer
4. Then follow the instructions.


## Documentation
For global usage, see the [user manual](docs/user_manual.md).


## Command usage
```bash
/path/to/time2backup.sh [GLOBAL_OPTIONS] [COMMAND] [OPTIONS]
```
For more usage, see the [command help](docs/command.md).


## Install from sources
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
git submodule update --init
```

To download the last updates, do:
```bash
git pull
git submodule update
```

## License
time2backup is licensed under the MIT License. See [LICENSE.md](LICENSE.md) for the full license text.


## Credits
Author: Jean Prunneaux https://jean.prunneaux.com

Website: https://time2backup.org

Source code: https://github.com/time2backup/time2backup
