# time2backup command help

## Table of contents
* [Global command](#global)
* [backup](#backup)
* [restore](#restore)
* [history](#history)
* [config](#config)
* [install](#install)
* [uninstall](#uninstall)

---------------------------------------------------------------

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
-c, --config CONFIG_DIR    load and save config in the specified directory
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
<a name="backup"></a>
## backup
Backup your files

### Usage
```bash
time2backup [GLOBAL_OPTIONS] backup [OPTIONS] [PATH...]
```

### Options
```
-u, --unmount    unmount destination after backup (overrides configuration)
-s, --shutdown   shutdown after backup (overrides configuration)
-r, --recurrent  perform a recurrent backup (used in cron jobs, not available in portable mode)
-h, --help       print help
```

### Exit codes
- 0: Backup successfully completed
- 1: Usage error
- 3: Config error
- 4: No sources to backup
- 5: Before script failed
- 6: Backup device is not reachable
- 7: Backup destination is not writable
- 8: A backup is already running
- 9: Cannot write logs
- 10: One or more source(s) does not exists
- 11: Cannot exclude directory backup from itself
- 12: rsync test failed
- 13: Not enough space for backup
- 14: rsync failed (critical error)
- 15: Warnings in backup (some files may not be transfered)
- 16: After script failed
- 17: Backup was cancelled
- 18: Error while unmount destination backup
- 19: Shutdown error
- 20: Recurrent backups disabled
- 21: Recurrent backups: cannot get/save last backup timestamp

---------------------------------------------------------------
<a name="restore"></a>
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
- 0: File(s) restored
- 1: Usage error
- 3: Config error
- 4: Backup device is not reachable
- 5: No backups available at this path
- 6: No backups of this file
- 7: No backup found at this date
- 8: Cannot exclude destination
- 9: Error while restore
- 10: rsync minor error: some files were not restored
- 11: Restore was cancelled
- 12: Operation is not supported

---------------------------------------------------------------
<a name="history"></a>
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
- 3: Config error
- 4: Backup device not reachable
- 5: No backup found for the path

---------------------------------------------------------------
<a name="config"></a>
## config
Configure time2backup.

### Usage
```bash
time2backup [GLOBAL_OPTIONS] config [OPTIONS]
```

### Options
```
-g, --general     edit general configuration
-s, --sources     edit sources file (sources to backup)
-x, --excludes    edit excludes file (patterns to ignore)
-i, --includes    edit includes file (patterns to include)
-l, --show        show configuration; do not edit
                  display configuration without comments
-t, --test        test configuration; do not edit
-w, --wizard      display configuration wizard instead of edit
-e, --editor BIN  use specified editor (e.g. vim, nano, ...)
-h, --help        print help
```

### Exit codes
- 0: Config OK
- 1: Usage error
- 3: Configuration errors
- 4: Error when apply config
- 5: Failed to open/save configuration
- 6: No editor found to open configuration file
- 7: Unknown error

---------------------------------------------------------------
<a name="install"></a>
## install
Install time2backup:
- create a `.desktop` file and tries to put it into `/usr/share/applications/`
- creates a link into `/usr/bin/`

### Usage
```bash
time2backup [GLOBAL_OPTIONS] install [OPTIONS]
```

### Options
```
-r, --reset-config  reset configuration files
-h, --help          print help
```

### Exit codes
- 0: Install OK
- 1: Usage error
- 3: Configuration errors
- 4: Error while creating application shortcuts
- 5: Error in reset configuration

---------------------------------------------------------------
<a name="uninstall"></a>
## uninstall
Uninstall time2backup:
- removes crontab entry
- deletes desktop file
- deletes command link

### Usage
```bash
time2backup [GLOBAL_OPTIONS] uninstall [OPTIONS]
```

### Options
```
-c, --delete-config  delete configuration files
-x, --delete-files   delete time2backup files
-h, --help           print help
```

### Exit codes
- 0: OK
- 1: Usage error
- 3: Cannot remove cron jobs
- 4: Cannot delete application link
- 5: Cannot delete command alias
- 6: Cannot delete configuration files
- 7: Cannot delete time2backup files
