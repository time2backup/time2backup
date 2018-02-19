# time2backup command help

## Table of contents
* [Global command](#global)
* [backup](#backup)
* [restore](#restore)
* [history](#history)
* [explore](#explore)
* [status](#status)
* [stop](#stop)
* [mv](#mv)
* [clean](#clean)
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
-C, --console              Execute time2backup in console mode (no dialog windows)
-l, --log-level LEVEL      Set a verbose and log level (ERROR|WARNING|INFO|DEBUG)
-v, --verbose-level LEVEL  Set a verbose and log level (ERROR|WARNING|INFO|DEBUG)
-d, --destination PATH     Set a custom destination path (overrides configuration)
-c, --config CONFIG_DIR    Load and save config in the specified directory
-D, --debug                Run in debug mode (all messages printed and logged)
-V, --version              Print version and quit
-h, --help                 Print help
```

### Commands
```
backup     Backup your files
restore    Restore a backup of a file or directory
history    Displays backup history of a file or directory
explore    Open the file browser at a date
status     Check if a backup is currently running
stop       Cancel a running backup
config     Edit configuration
install    Install time2backup
uninstall  Uninstall time2backup
```

---------------------------------------------------------------
<a name="backup"></a>
## backup
Perform a backup.

### Usage
```bash
time2backup [GLOBAL_OPTIONS] backup [OPTIONS] [PATH...]
```

### Options
```
-p, --progress   Display backup progress for each file (overrides configuration)
-u, --unmount    Unmount destination after backup (overrides configuration)
-s, --shutdown   Shutdown after backup (overrides configuration)
-r, --recurrent  Perform a recurrent backup (used in cron jobs)
--force-unlock   Force to backup if a lock is stuck (use with caution)
-h, --help       Print help
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
- 14: rsync failed with a critical error
- 15: Warnings in backup (some files may not be transferred)
- 16: After script failed
- 17: Backup was cancelled
- 18: Error while unmount destination backup
- 19: Shutdown error
- 20: Recurrent backups disabled
- 21: Recurrent backups: cannot get/save last backup timestamp

---------------------------------------------------------------
<a name="restore"></a>
## restore
Restore a file or directory

Be careful when restoring a deleted/moved directory, don't forget to put a "/" at the end of the path
if you are specify path via the command line.

### Usage
```bash
time2backup [GLOBAL_OPTIONS] restore [OPTIONS] [PATH]
```

### Options
```
-d, --date DATE  Restore file at backup DATE (use format YYYY-MM-DD-HHMMSS)
                 by default it restores the last available backup
--delete-new     Delete newer files if exists for directories (restore exactly the same version)
-p, --progress   Display restore progress for each file (overrides configuration)
-f, --force      Force restore; do not display confirmation
-h, --help       Print help
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
-a, --all    Print all versions, including duplicates
-q, --quiet  Quiet mode; print only backup dates
-h, --help   Print help
```

### Exit codes
- 0: History printed
- 1: Usage error
- 3: Config error
- 4: Backup device is not reachable
- 5: No backup found for the path

---------------------------------------------------------------
<a name="explore"></a>
## explore
Open file browser to explore backuped files

### Usage
```bash
time2backup [GLOBAL_OPTIONS] explore [OPTIONS] [PATH]
```
Note: If no path is specified, it will open the root backup folder.

### Options
```
-d, --date DATE  Explore file at backup DATE (use format YYYY-MM-DD-HHMMSS)
-a, --all        Explore all versions"
-h, --help       Print help
```

### Exit codes
- 0: File browser opened
- 1: Usage error
- 3: Config error
- 4: Backup device is not reachable
- 5: No backups available at this path
- 6: No backups of this file
- 7: No backup found at this date
- 8: Unknown error of the file browser

---------------------------------------------------------------
<a name="status"></a>
## status
Check if a backup is currently running

### Usage
```bash
time2backup [GLOBAL_OPTIONS] status [OPTIONS]
```

### Options
```
-q, --quiet  Quiet mode
-h, --help   Print help
```

### Exit codes
- 0: No backup currently running
- 1: Usage error
- 3: Config error
- 4: Backup device not reachable
- 5: A backup is currently running
- 6: A backup lock exists, but no time2backup instance is running

---------------------------------------------------------------
<a name="stop"></a>
## stop
Cancel a running backup.

### Usage
```bash
time2backup [GLOBAL_OPTIONS] stop [OPTIONS]
```

### Options
```
-f, --force  Do not print confirmation before stop
-q, --quiet  Quiet mode
-h, --help   Print help
```

### Exit codes
- 0: Backup stopped
- 1: Usage error
- 3: Config error
- 4: Backup device not reachable
- 5: Failed to stop process
- 6: Cannot get status of backup
- 7: No rsync process found

---------------------------------------------------------------
<a name="mv"></a>
## mv
Move or rename backuped files.

Use this command if you want to rename/move a huge file/directory and avoid
time2backup to consider it as deleted and retransfer the file/directory.

### Usage
```bash
time2backup [GLOBAL_OPTIONS] mv [OPTIONS] PATH DESTINATION
```

### Options
```
-f, --force  Force move; do not display confirmation"
-q, --quiet  Quiet mode"
-h, --help   Print help
```

### Exit codes
- 0: File(s) moved
- 1: Usage error
- 3: Config error
- 4: Backup device is not reachable
- 5: No backup found for the path
- 6: Cannot determine the backup path of source path or destination
- 7: mv command error

---------------------------------------------------------------
<a name="clean"></a>
## clean
Clean some backup files.

### Usage
```bash
time2backup [GLOBAL_OPTIONS] clean [OPTIONS] PATH
```

### Options
```
-f, --force  Force clean; do not display confirmation
-q, --quiet  Quiet mode
-h, --help   Print help
```

### Exit codes
- 0: Files cleaned
- 1: Usage error
- 3: Config error
- 4: Backup device is not reachable
- 5: No backup found for the path
- 6: Some error occured while deleting files

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
-g, --general     Edit general configuration
-s, --sources     Edit sources file (sources to backup)
-x, --excludes    Edit excludes file (patterns to ignore)
-i, --includes    Edit includes file (patterns to include)
-l, --show        Show configuration; do not edit
                  display configuration without comments
-t, --test        Test configuration; do not edit
-w, --wizard      Display configuration wizard instead of edit
-r, --reset       Reset configuration file
-e, --editor BIN  Use specified editor (e.g. vim, nano, ...)
-h, --help        Print help
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
- creates a `.desktop` file and tries to put it into `/usr/share/applications/` (on Linux only)
- creates a link into `/usr/bin/` (on Linux and macOS)

### Usage
```bash
time2backup [GLOBAL_OPTIONS] install [OPTIONS]
```

### Options
```
-h, --help  Print help
```

### Exit codes
- 0: Install OK
- 1: Usage error
- 3: Configuration errors
- 4: Error while creating application shortcuts
- 5: Error while creating bash completion file

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
-y, --yes           Do not prompt confirmation to uninstall
-x, --delete-files  Delete time2backup files
-h, --help          Print help
```

### Exit codes
- 0: OK
- 1: Usage error
- 3: Cannot remove cron jobs
- 4: Cannot delete application link
- 5: Cannot delete command alias
- 6: Cannot delete time2backup files
- 7: Cannot delete bash completion file
