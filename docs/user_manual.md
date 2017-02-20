# time2backup User Guide

## Table of contents
* [What is time2backup?](#whatisit)
* [What do I need to install time2backup?](#requirements)
* [How to install time2backup](#install)
* [Backup your files](#backup)
* [Restore your files](#restore)

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
Double-click on the time2backup.sh file or run it in a console with:
```bash
./time2backup.sh
```

Then follow the install wizard.

<a name="backup"></a>
## Backup your files
Once you have passed the installation wizard, all you have to do is to plug your
backup device (USB stick, external disk drive, ...).

If you have enabled recurrent backups, you just have to wait until backup is finished
(you will have a notification popup on your desktop).

If you haven't, just run time2backup and go into backup mode, or run the following command in a terminal:
```bash
./time2backup.sh backup
```
See [command documentation](command.md) for more information and options.


<a name="restore"></a>
## Restore your files
Run time2backup and go into restore mode, or run the following command in a terminal:
```bash
./time2backup.sh restore
```
See [command documentation](command.md) for more information and options.

You will have to choose the file or directory to restore, and the version date to restore.

Then you will get your file(s) exactly at backup state.
