# time2backup User Guide

## Table of contents
* [What is time2backup?](#whatisit)
* [What do I need to install time2backup?](#requirements)
* [How to install time2backup](#install)
* [Backup your files](#backup)
* [Restore your files](#restore)
* [Upgrading time2backup](#upgrade)
* [Uninstall time2backup](#uninstall)
* [Frequently Asked Questions](#faq)

---------------------------------------------------------------

<a name="whatisit"></a>
## What is time2backup?
time2backup is a program to easy backup and restore your files.

<a name="requirements"></a>
## What do I need to install time2backup?
Nothing else but the rsync program, which is installed on most popular systems like Ubuntu,
Linux Mint, Debian, openSuse, Mageia, macOS, ...

<a name="install"></a>
## How to install time2backup
### Debian/Ubuntu
1. Download time2backup [deb package here](https://time2backup.org/download/time2backup/stable)
2. Install package: `dpkg -i time2backup-X.X.X.deb`

### Windows
[Read instructions here](https://github.com/time2backup/windows/tree/master/package).

### macOS
1. Download time2backup [macOS app package here](https://time2backup.org/download/time2backup/stable)
2. Unzip file and drag/drop the `time2backup.app` file in your `Applications` folder

### Manual install
1. Download time2backup [zip or tar.gz archive here](https://time2backup.org/download/time2backup/stable)
2. Uncompress archive where you want
3. Run the `time2backup.sh` file in a terminal or just by clicking on it in your file explorer
4. (optionnal) To install time2backup globally (having a link in the terminal), run the following command:
```bash
/path/to/time2backup.sh install [OPTIONS]
```
See [command documentation](command.md#install) for more information and options.

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
See [command documentation](command.md#backup) for more information and options.

<a name="restore"></a>
## Restore your files
Run time2backup and go into restore mode, or run the following command in a terminal:
```bash
/path/to/time2backup.sh restore [OPTIONS] [PATH]
```
See [command documentation](command.md#restore) for more information and options.

You will have to choose the file or directory to restore, and the version date to restore.

Then you will get your file(s) exactly at backup state.

<a name="upgrade"></a>
## Upgrading time2backup
To upgrade time2backup, download the last version on the [official website](https://time2backup.org)
and reinstall it (see [instructions above](#install)).

<a name="uninstall"></a>
## Uninstall time2backup
### Debian/Ubuntu
Run `apt remove time2backup`.

### Windows
[Read instructions here](https://github.com/time2backup/windows/tree/master/package).

### macOS
Put `time2backup.app` in trashbin.

### Manual install
Run the following command in a terminal:
```bash
/path/to/time2backup.sh uninstall [OPTIONS]
```
See [command documentation](command.md#uninstall) for more information about options.

<a name="faq"></a>
## Frequently Asked Questions

If you don't find answer to your question, please [open an issue here](https://github.com/time2backup/time2backup/issues)

### time2backup is stuck with message "a backup is already running"
Sometimes, if time2backup was killed by force, a lock file may stay.
To fix this, run the backup command with `--force-unlock` option.

### How do I set up excludes in a multi-sources setup?
If you backup multiple sources, excluded files are applying globally.
But if you want to set custom excludes for a directory, create a file named `.rsyncingnore` at the root of your source directory
and fill it with common exclude syntax.

Note: This will not work for remote sources.

Remember that you can also create multiple time2backup configs and call them with `time2backup -c path/to/config`.
