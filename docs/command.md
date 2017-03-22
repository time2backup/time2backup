# time2backup command help

## Global command

### Usage
```bash
time2backup [GLOBAL_OPTIONS] COMMAND [OPTIONS] [ARG...]
```

### Global options
```
-C, --console              execute time2backup in console mode (no dialog windows)
-p, --portable             execute time2backup in a portable mode
                           (no install, use local config files, meant to run from removable devices)
-l, --log-level LEVEL      set a verbose and log level (ERROR|WARNING|INFO|DEBUG)
-v, --verbose-level LEVEL  set a verbose and log level (ERROR|WARNING|INFO|DEBUG)
-c, --config CONFIG_FILE   overwrite configuration with specific file
-D, --debug                run in debug mode (all messages printed and logged)
-V, --version              print version and quit
-h, --help                 print help
```

### Commands
```
backup     backup your files
restore    restore a backup of a file or directory
history    displays backup history of a file or directory
config     edit configuration
install    install time2backup
uninstall  uninstall time2backup
```

---------------------------------------------------------------
## backup
Backup your files

### Usage
```bash
time2backup [GLOBAL_OPTIONS] backup [OPTIONS] [PATH]
```

### Options
```
-u, --unmount    unmount destination after backup (overrides configuration)
-s, --shutdown   shutdown after backup (overrides configuration)
-r, --recurrent  perform a recurrent backup (used in cron jobs, not available in portable mode)
-h, --help       print help
```

### Exit codes
- 0: Everthing is OK
- 1: Usage error
- 2: Config error
- 3: No sources to backup
- 4: Destination backup not plugged in
- 10: A backup is already running
- 11: Backup was cancelled by user

---------------------------------------------------------------
## restore
Restore a backup of a file or directory

### Usage
```bash
time2backup [GLOBAL_OPTIONS] restore [OPTIONS] [PATH]
```

### Options
```
-d, --date DATE  restore file at backup DATE (use format YYYY-MM-DD-HHMMSS)
                 by default it restores the last available backup
--directory      path to restore is a directory (not necessary if path exists)
                 If deleted or moved, indicate that the chosen path is a directory.
--delete-new     delete newer files if exists for directories (restore exactly the same version)
-f, --force      force restore; do not display confirmation
-h, --help       print help
```

### Exit codes
- 0: File has been restored
- 1: Usage error
- 2: Config error
- 3: No backups available
- 4: Backup device not reachable
- 5: Restore failed
- 6: Operation not permitted

---------------------------------------------------------------
## history
Displays backup history of a file or directory

### Usage
```bash
time2backup [GLOBAL_OPTIONS] history [OPTIONS] PATH
```

### Options
```
-a, --all    print all versions, including duplicates
-q, --quiet  quiet mode; print only backup dates
-h, --help   print help
```

### Exit codes
- 0: History printed
- 1: Usage error
- 2: Config error
- 3: No backup found for the file
- 4: Backup device not reachable
