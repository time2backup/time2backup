# time2backup User Guide

## Table of contents
* [What is time2backup?](#whatisit)
* [What do I need to install time2backup?](#requirements)
* [How to install time2backup](#install)
* [Backup your files](#backup)
* [Restore your files](#restore)
* [Upgrading time2backup](#upgrade)
* [Uninstall time2backup](#uninstall)
* [Troubleshootting](#troubleshootting)

---------------------------------------------------------------

<a name="whatisit"></a>
## What is time2backup?
time2backup is a program to easy backup and restore your files.
It wants to be as simple as Time Machine on macOS.

<a name="requirements"></a>
## What do I need to install time2backup?
Nothing but rsync program, which is installed on most popular systems like Ubuntu,
Linux Mint, Debian, openSuse, Mageia, macOS, ...

<a name="install"></a>
## How to install time2backup
1. [Download time2backup here](https://time2backup.github.io)
2. Uncompress archive where you want
3. Run the `time2backup.sh` file in a terminal or just by clicking on it in your file explorer
4. Then follow the instructions.

<a name="backup"></a>
## Backup your files
Once you have passed the installation wizard, all you have to do is to plug your
backup device (USB stick, external disk drive, ...).

If you have enabled recurrent backups, you just have to wait until backup is finished
(you will have a notification popup on your desktop).

If you haven't, just run time2backup and go into backup mode, or run the following command in a terminal:
```bash
/path/to/time2backup.sh backup [OPTIONS] [PATH]
```
See [command documentation](command.md) for more information and options.


<a name="restore"></a>
## Restore your files
Run time2backup and go into restore mode, or run the following command in a terminal:
```bash
/path/to/time2backup.sh restore [OPTIONS] [PATH]
```
See [command documentation](command.md) for more information and options.

You will have to choose the file or directory to restore, and the version date to restore.

Then you will get your file(s) exactly at backup state.


<a name="upgrade"></a>
## Upgrading time2backup
To upgrade time2backup, download the last version here and just uncompress archive into the same folder.
If your system is asking, choose to overwrite files.


<a name="uninstall"></a>
## Uninstall time2backup
To uninstall time2backup, run the following command in a terminal:
```bash
/path/to/time2backup.sh uninstall [OPTIONS]
```
See [command documentation](command.md) for more information and options.

<a name="troubleshootting"></a>
## Troubleshootting
Some common bugs or issues are reported here.

In any case of problem, please report any bug here: https://github.com/time2backup/time2backup/issues

### time2backup is stuck with message "a backup is already running"
Sometimes, if time2backup was killed by force, a lock file may stay.
If you are sure that no backup is currently running, you can delete the lock files named `path/to/backups/.lock_*`
