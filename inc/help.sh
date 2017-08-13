#
# time2backup help functions
#
# This file is part of time2backup (https://time2backup.github.io)
#
# MIT License
# Copyright (c) 2017 Jean Prunneaux
#

# Print help for users in console
# Usage: print_help [COMMAND]
print_help() {
	echo -e "\nUsage: $lb_current_script_name [GLOBAL_OPTIONS] COMMAND [OPTIONS] [ARG...]"
	echo -e "\nGlobal options:"
	echo -e "  -C, --console              execute time2backup in console mode (no dialog windows)"
	echo -e "  -p, --portable             execute time2backup in a portable mode"
	echo -e "                             (no install, use local config files, meant to run from removable devices)"
	echo -e "  -l, --log-level LEVEL      set a verbose and log level (ERROR|WARNING|INFO|DEBUG)"
	echo -e "  -v, --verbose-level LEVEL  set a verbose and log level (ERROR|WARNING|INFO|DEBUG)"
	echo -e "  -d, --destination PATH     set a custom destination path (overrides configuration)"
	echo -e "  -c, --config CONFIG_DIR    load and save config in the specified directory"
	echo -e "  -D, --debug                run in debug mode (all messages printed and logged)"
	echo -e "  -V, --version              print version and quit"
	echo -e "  -h, --help                 print help \n"

	case $1 in
		backup)
			echo -e "Command usage: $1 [OPTIONS] [PATH...]"
			echo -e "\nBackup your files"
			echo -e "\nOptions:"
			echo -e "  -u, --unmount           unmount destination after backup (overrides configuration)"
			echo -e "  -s, --shutdown          shutdown after backup (overrides configuration)"
			echo -e "  -r, --recurrent         perform a recurrent backup (used in cron jobs, not available in portable mode)"
			echo -e "  -h, --help              print help"
			;;
		restore)
			echo -e "Command usage: $1 [OPTIONS] [PATH]"
			echo -e "\nRestore a file or directory"
			echo -e "Warning: This feature does not auto-detect renamed or moved files."
			echo -e "         To restore a moved/deleted file, ."
			echo -e "\nOptions:"
			echo -e "  -d, --date DATE    restore file at backup DATE (use format YYYY-MM-DD-HHMMSS)"
			echo -e "                     by default it restores the last available backup"
			echo -e "  --directory        path to restore is a directory (not necessary if path exists)"
			echo -e "                     If deleted or moved, indicate that the chosen path is a directory."
			echo -e "  --delete-new       delete newer files if exists for directories (restore exactly the same version)"
			echo -e "  -f, --force        force restore; do not display confirmation"
			echo -e "  -h, --help         print help"
			;;
		history)
			echo -e "Command usage: $1 [OPTIONS] PATH"
			echo -e "\nGet backup history of a file or directory"
			echo -e "Warning: This feature does not detect old renamed/moved files yet."
			echo -e "\nOptions:"
			echo -e "  -a, --all    print all versions, including duplicates"
			echo -e "  -q, --quiet  quiet mode; print only backup dates"
			echo -e "  -h, --help   print help"
			;;
		status)
			echo -e "Command usage: $1 [OPTIONS]"
			echo -e "\nCheck if a backup is currently running"
			echo -e "\nOptions:"
			echo -e "  -q, --quiet  quiet mode; print only backup dates"
			echo -e "  -h, --help   print help"
			;;
		config)
			echo -e "Command usage: $1 [OPTIONS]"
			echo -e "\nEdit configuration"
			echo -e "\nOptions:"
			echo -e "  -g, --general     edit general configuration"
			echo -e "  -s, --sources     edit sources file (sources to backup)"
			echo -e "  -x, --excludes    edit excludes file (patterns to ignore)"
			echo -e "  -i, --includes    edit includes file (patterns to include)"
			echo -e "  -l, --show        show configuration; do not edit"
			echo -e "                    display configuration without comments"
			echo -e "  -t, --test        test configuration; do not edit"
			echo -e "  -w, --wizard      display configuration wizard instead of edit"
			echo -e "  -r, --reset       reset configuration file"
			echo -e "  -e, --editor BIN  use specified editor (e.g. vim, nano, ...)"
			echo -e "  -h, --help        print help"
			;;
		install)
			echo -e "Command usage: $1 [OPTIONS]"
			echo -e "\nInstall time2backup"
			echo -e "\nOptions:"
			echo -e "  -r, --reset-config  reset configuration files to default"
			echo -e "  -h, --help          print help"
			;;
		uninstall)
			echo -e "Command usage: $1 [OPTIONS]"
			echo -e "\nUninstall time2backup"
			echo -e "\nOptions:"
			echo -e "  -c, --delete-config  delete configuration files"
			echo -e "  -x, --delete         delete time2backup files"
			echo -e "  -h, --help           print help"
			;;
		*)
			echo -e "Commands:"
			echo -e "    backup     backup your files"
			echo -e "    restore    restore a backup of a file or directory"
			echo -e "    history    displays backup history of a file or directory"
			echo -e "    status     check if a backup is currently running"
			echo -e "    config     edit configuration"
			echo -e "    install    install time2backup"
			echo -e "    uninstall  uninstall time2backup"
			echo -e "\nRun '$lb_current_script_name COMMAND --help' for more information on a command."
			;;
	esac
}
