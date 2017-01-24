# time2backup Developer Guide

Command guide.

## Global command

### Usage
```bash
time2backup [GLOBAL_OPTIONS] COMMAND [OPTIONS] [ARG...]
```

### Global options
```
-C, --console              execute time2backup in console mode (no dialog windows)
-l, --log-level LEVEL      set a verbose and log level (ERROR|WARNING|INFO|DEBUG)
-v, --verbose-level LEVEL  set a verbose and log level (ERROR|WARNING|INFO|DEBUG)
-c, --config CONFIG_FILE   overwrite configuration with specific file
-D, --debug                run in debug mode (all messages printed and logged)
-V, --version              print version and quit
-h, --help                 print help
```

### Commands
```
backup     perform a backup (default)
restore    restore a backup of a file or directory
history    displays backup history of a file or directory
config     edit configuration
install    install time2backup
```

---------------------------------------------------------------
## backup
Perform a backup.

### Usage
```bash
time2backup [GLOBAL_OPTIONS] backup [OPTIONS]
```

### Options
```
-h, --help  Print help
```

### Exit codes
- 0: Everthing is OK
- 1: Usage error

---------------------------------------------------------------
## restore
Restore files/directories.

### Usage
```bash
time2backup [GLOBAL_OPTIONS] restore [OPTIONS]
```

### Options
```
-h, --help  Print help
```

### Exit codes
- 0: Everthing is OK
- 1: Usage error
