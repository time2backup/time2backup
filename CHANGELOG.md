# Changelog

## 1.2.2 (2017-11-17)
- Fix bug 'Cannot find homepath' on Windows install
- Fix bug that can crash uninstall command
- Release backup lock on Windows before displaying info dialogs to avoid locks stucked
- Remove the reset/delete config options in install/uninstall commands to avoid malicious uses
- Test config values before call them to avoid bugs, especially for boolean values
- Some improvements in source code

## 1.2.1 (2017-11-06)
- Fixed hard links bug for distant sources (previous backup were not found)
- Send email reports even if first tests fails (already running, not mounted, ...)
- Hard links compatibility is now tested from a list of known supported filesystems

## 1.2.0 (2017-10-30)
- New clean command to delete backup files
- New mv command to reorganize backup files
- Fixed bug that prevent Windows to backup on network shared folders
- New option to prevent user to execute custom commands
- Improve output of the history command
- Fixed quiet mode that printed some info
- libbash.sh upgraded to 1.6.2
- Various code improvements and optimizations

## 1.1.0 (2017-09-29)
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

## 1.0.0 (2017-08-09)
- Changed `logs_save` to `keep_logs` with an enum (can broke your config, see config example file)

## 1.0.0 RC 8 (2017-08-01)
- Add popup dialogs on Windows when backup/restore finished
- Upgrade to libbash.sh 1.2.2
- New option: `email_subject_prefix` to set a prefix to email reports subjects
- Changed `email_report` config system (can broke your config, see config example file)
- Rename `consolemode` config value to `console_mode`
- Improve documentation and source code comments
- Various minor improvements

## 1.0.0 RC 7 (2017-06-16)
- New option to not test free space on destination before backup
- Test folders size before backup
- Many improvements in Windows support
- Upgrade to libbash.sh 1.1.1
- Various improvements and bugfixes
- Change in global options: `--config` needs now the config directory path

## 1.0.0 RC 6 (2017-05-17)
- Add support to backup multiple sources specified from the command line
- Apply configuration when running main commands (backup, restore, history)
- Major improvements in documentation
- Upgrade to libbash.sh 1.0
- Various bugfixes and improvements in source code

## 1.0.0 RC 5 (2017-04-12)
- Enable notifications in cron mode
- Delete cron jobs when uninstall
- Fix automount bugs
- Fix rotate bugs
- Prevent recurrent backups to run before user has finished to edit configuration
- Code optimizations

## 1.0.0 RC 4 (2017-03-21)
- Update libbash.sh to fix zenity notifications bug
- Add uninstall command

## 1.0.0 RC 3 (2017-03-15)
- Fix critical bugs for SSH sources
- Finished rewrite of exit codes

## 1.0.0 RC 2 (2017-03-13)
- Clean empty backup if cancelled
- Rewrite of exit codes
- Various improvements and bugfixes

## 1.0.0 RC 1 (2017-03-06)
- First release on Github

---------------------------------------------------------------

## License
time2backup is licensed under the MIT License. See [LICENSE.md](LICENSE.md) for the full license text.

## Credits
Author: Jean Prunneaux  http://jean.prunneaux.com

Website: https://time2backup.org
