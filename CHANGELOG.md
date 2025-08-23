# Changelog

# 1.9.5 (2025-06-20)
## New features
- New deb & rpm packages automatic builder for GitHub

## Changes
- Update libbash.sh 1.22.9

# 1.9.1 (2022-10-07)
## Bugfixes
- Fixed a bug when testing backup size in other languages
- Minor changes in display messages

## Changes
- Upgrade libbash.sh to 1.21.0

# 1.9.0 (2021-03-19)
## Changes
- **WARNING:** if you upgrade time2backup from a version prior to 1.7.0, please upgrade to **1.8.7**
  before upgrade to **1.9.0**
- Upgrade libbash.sh to 1.20.0, adding native notifications on Windows
- Drop 32-bits support for Windows
- Minor code improvements

## Bugfixes
- Add missing SSH options when restoring remote sources

# 1.8.7 (2021-02-01)
## Changes
- Open time2backup in terminal

# 1.8.6 (2021-01-29)
## Bugfixes
- Fix regressive bug that prenvented restore ssh files
- Upgrade libbash.sh to 1.18.1, fixing a bug that prevented emails to be sent in some configurations

# 1.8.5 (2020-12-04)
## Bugfixes
- Fix false incomplete warning when restoring a relative path directory

## Changes
- Upgrade libbash.sh to 1.18.0
- Minor code improvements and cleaning

# 1.8.4 (2020-08-24)
## Bugfixes
- Fix bug that prevented debug mode to work
- Apply crontab changes only when running config wizard or config command

# 1.8.3 (2020-07-17)
## Changes
- Upgrade libbash.sh to 1.17.1, improving import config security
- Minor code improvements

# 1.8.2 (2020-07-06)
## Changes
- Import/export all now does a full rsync command

## Bugfixes
- Clean empty trash in trash mode
- Debug mode can now be set in config

# 1.8.1 (2020-04-22)
## Bugfixes
- Add support for multi-sources in clone mode

# 1.8.0 (2020-04-18)
## New features
- New clone mode: backup source to destination without versionning

## Changes
- Navigate in config windows do not quit time2backup when finished
- Upgrade libbash.sh to 1.16.1
- Improved documentation

## Bugfixes
- Fixed bug that prevented config migration to work on BSD/macOS since 1.6.0! (related to libbash.sh 1.14.2)
- Fixed crash when restoring to a non-existant directory

# 1.7.2 (2020-04-03)
## Bugfixes
- Fix bug when moving backed up files to a new path
- Minor code improvements

# 1.7.1 (2020-01-29)
## Changes
- Don't override excludes config file if it is empty
- Improve display for some commands
- Upgrade libbash.sh to 1.15.0

# 1.7.0 (2019-11-22)
## New features
- Remote destination support with [time2backup server](https://github.com/time2backup/server)
- New trash mode: put every old backup versions in the same directory, like a trashbin
- New sources selector in config wizard
- New `--all` option for `import` and `export` commands
- New `--test` option for `rotate` command

## Changes
- Removed compatibility for old subdirectories destinations (deprecated since 1.3.0)
- Removed compatibility for old restore `--force-lock` options (deprecated since 1.3.1)
- Config parameter `ssh_options` is now an array of values (old configs are upgraded automatically)
- Removed config parameter `remote_sudo` (old configs are upgraded automatically)
- `history` command displays folders without content
- Enhance security for config import
- Major code rewrites in backup procedure with simplifications
- Upgrade libbash.sh to 1.14.4

# 1.6.2 (2019-10-12)
## Bugfixes
- Improve import/export by using better references
- Upgrade libbash.sh to 1.14.3
- Minor code improvements

# 1.6.1 (2019-10-08)
## Bugfixes
- Fixed bug that prevent force unlock mode to delete the good lock
- Avoid backups on local disk if SMB destination was not unmounted correctly
- Fixed some bugs related to homepaths on Windows and BSD
- Various code improvements

# 1.6.0 (2019-09-23)
## New features
- New `import` command to copy backups from another folder/host
- New test mode for `backup` and `restore` commands
- New option to restore files in another path
- SMB destinations are now supported
- BSD systems are now supported
- Windows: new portable version (bat script)

## Changes
- Permit restore directories in trash mode
- Improvements in `export` command
- Improvements when cleaning empty backups
- Remove support for URLs like `file://`
- Configuration upgrade is now simplier and better
- Logs on Windows are formatted with good end of lines
- libbash.sh upgraded to version 1.14.2

## Bugfixes
- Fixed a bug that prevent calling remote rsync path when restoring remote source
- Fixed a bug for ssh when `ssh_options` rewrites ssh command
- Fixed bugs for config upgrades on Windows

# 1.5.1 (2019-06-03)
- Fix bug in trash mode when using relative backup destination path
- libbash.sh upgraded to version 1.12.2

# 1.5.0 (2019-05-06)
## New features
- New portable version available: run `./t2b-portable.sh`
- New `rotate` command to rotate backups manually
- New `export` command to copy backups to another folder/host
- New `--keep` option to `clean` command to keep the N latest backups
- The `keep_limit` config value can now be set as a period of minutes, hours or days
- New config entry to execute remote rsync with sudo

## Changes
- Improve status/stop commands with PID written in backup lock file
- Various messages display improvements
- libbash.sh upgraded to version 1.12.1
- Various code improvements for a better organization
- Improvements in documentation and help

## Bugfixes
- Fix a bug that could empty the log file
- Various bugfixes

# 1.4.0 (2018-09-12)
## New features
- New `--latest` option to `restore` command to restore the latest version of the path
- New `--latest` option to `mv` command to move only the latest version of the path
- New `--keep-latest` option to `clean` command to keep the latest version from deleting
- More context informations are stored in the info file
- More error details in email reports

## Changes
- Empty backup directories with nothing except info file are now deleted
- Restore directories are now allowed in trash mode, only from the latest backup
- Backup estimated time is more reliable
- Improvements in rotate and clean empty backups
- libbash.sh upgraded to version 1.9.2
- Various code improvements in performance and readability

## Bugfixes
- Prevent multiple cron tasks when using default and custom config paths
- macOS: fix bug when running in sudo
- macOS: open configuration with default text editor instead of random application

# 1.3.1 (2018-02-19)
- Fix bug when excluding destination folder to avoid recursive backups
- Fix line return bug for emails
- Fix "nothing was backed up" error if destination disappears before end
- New quit option in choose operation dialog
- Add lock details in console
- Hide explore command in console mode
- Add backup date in info file
- Change `--force-lock` option to `--force-unlock` (keep compatibility)
- Don't hold script when sending email reports

# 1.3.0 (2018-01-27)
- Backup resumes if the last one has failed or was canceled
- New `backup.info` file created for each backup to log durations and command status
- New option and config to show rsync files progress (disabled by default)
- New feature: restore remote files/directories
- New logfile if restore command failed
- Explore command is now available from the choose operation dialog
- Browse the global backup destination if no path specified in the explore command
- Warn user if trying to restore a partially backed up directory
- New quiet option to hide rsync output for backup and restore commands
- New procedure to restore a backup from another PC
- Print backup estimated time
- Print PID on status command
- New option to force backup when a lock is stuck
- Ask confirmation before stop command & add force option
- Added bash completion support
- Removed the install process at the first run
- Removed the subdirectories system and add migration code for older installs
- Improved cleanup for failed backups that didn't work in some cases
- Minor changes and improvements
- Upgrade to libbash.sh 1.8.0

# 1.2.2 (2017-11-17)
- Fix bug 'Cannot find homepath' on Windows install
- Fix bug that can crash uninstall command
- Release backup lock on Windows before displaying info dialogs to avoid locks stucked
- Remove the reset/delete config options in install/uninstall commands to avoid malicious uses
- Test config values before call them to avoid bugs, especially for boolean values
- Some improvements in source code

# 1.2.1 (2017-11-06)
- Fixed hard links bug for distant sources (previous backup were not found)
- Send email reports even if first tests fails (already running, not mounted, ...)
- Hard links compatibility is now tested from a list of known supported filesystems

# 1.2.0 (2017-10-30)
- New clean command to delete backup files
- New mv command to reorganize backup files
- Fixed bug that prevent Windows to backup on network shared folders
- New option to prevent user to execute custom commands
- Improve output of the history command
- Fixed quiet mode that printed some info
- libbash.sh upgraded to 1.6.2
- Various code improvements and optimizations

# 1.1.0 (2017-09-29)
- New explore command to open backups in the file manager
- New stop command to interrupt a running backup
- New debian package available
- Major improvements in config files
- Add option to override destination
- Rotate backups only when backup is done
- Add translations in email reports
- Improve install process
- Config files can be open and modified on Windows in the notepad
- Various improvements on Windows
- Fixed bad interpretation of sizes on macOS
- Fix email reports that were not sent

# 1.0.0 (2017-08-09)
- Changed `logs_save` to `keep_logs` with an enum (can broke your config, see config example file)

# 1.0.0 RC 8 (2017-08-01)
- Add popup dialogs on Windows when backup/restore finished
- Upgrade to libbash.sh 1.2.2
- New option: `email_subject_prefix` to set a prefix to email reports subjects
- Changed `email_report` config system (can broke your config, see config example file)
- Rename `consolemode` config value to `console_mode`
- Improve documentation and source code comments
- Various minor improvements

# 1.0.0 RC 7 (2017-06-16)
- New option to not test free space on destination before backup
- Test folders size before backup
- Many improvements in Windows support
- Upgrade to libbash.sh 1.1.1
- Various improvements and bugfixes
- Change in global options: `--config` needs now the config directory path

# 1.0.0 RC 6 (2017-05-17)
- Add support to backup multiple sources specified from the command line
- Apply configuration when running main commands (backup, restore, history)
- Major improvements in documentation
- Upgrade to libbash.sh 1.0
- Various bugfixes and improvements in source code

# 1.0.0 RC 5 (2017-04-12)
- Enable notifications in cron mode
- Delete cron jobs when uninstall
- Fix automount bugs
- Fix rotate bugs
- Prevent recurrent backups to run before user has finished to edit configuration
- Code optimizations

# 1.0.0 RC 4 (2017-03-21)
- Update libbash.sh to fix zenity notifications bug
- Add uninstall command

# 1.0.0 RC 3 (2017-03-15)
- Fix critical bugs for SSH sources
- Finished rewrite of exit codes

# 1.0.0 RC 2 (2017-03-13)
- Clean empty backup if cancelled
- Rewrite of exit codes
- Various improvements and bugfixes

# 1.0.0 RC 1 (2017-03-06)
- First release on Github
