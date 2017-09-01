#
# time2backup help functions
#
# This file is part of time2backup (https://time2backup.github.io)
#
# MIT License
# Copyright (c) 2017 Jean Prunneaux
#

# Print help for users in console
# Usage: print_help [global]
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

	if [ "$1" == global ] ; then
		echo "Commands:"
		echo "    backup     backup your files"
		echo "    restore    restore a backup of a file or directory"
		echo "    history    displays backup history of a file or directory"
		echo "    status     check if a backup is currently running"
		echo "    config     edit configuration"
		echo "    install    install time2backup"
		echo "    uninstall  uninstall time2backup"
		echo -e "\nRun '$lb_current_script_name COMMAND --help' for more information on a command."
		return 0
	fi

	echo -n "Command usage: $command [OPTIONS] "

	case $command in
		backup)
			echo "[PATH...]"
			echo -e "\nBackup your files"
			echo -e "\nOptions:"
			echo "  -u, --unmount    Unmount destination after backup (overrides configuration)"
			echo "  -s, --shutdown   Shutdown after backup (overrides configuration)"
			echo "  -r, --recurrent  Perform a recurrent backup (used in cron jobs, not available in portable mode)"
			echo "  -h, --help       Print this help"
			;;
		restore)
			echo "[PATH]"
			echo -e "\nRestore a file or directory"
			echo -e "Warning: This feature does not auto-detect renamed or moved files."
			echo -e "         To restore a moved/deleted file, please enter an absolute path."
			echo -e "\nOptions:"
			echo "  -d, --date DATE  Restore file at backup DATE (use format YYYY-MM-DD-HHMMSS)"
			echo "                   by default it restores the last available backup"
			echo "  --directory      Path to restore is a directory (not necessary if path exists)"
			echo "                   If deleted or moved, indicate that the chosen path is a directory."
			echo "  --delete-new     Delete newer files if exists for directories (restore exactly the same version)"
			echo "  -f, --force      Force restore; do not display confirmation"
			echo "  -h, --help       Print this help"
			;;
		history)
			echo "PATH"
			echo -e "\nGet backup history of a file or directory"
			echo -e "Warning: This feature does not detect old renamed/moved files yet."
			echo -e "\nOptions:"
			echo "  -a, --all    Print all versions, including duplicates"
			echo "  -q, --quiet  Quiet mode; print only backup dates"
			echo "  -h, --help   Print this help"
			;;
		explore)
			echo "PATH"
			echo -e "\nExplore backups of a file or directory"
			echo -e "Warning: This feature does not detect old renamed/moved files yet."
			echo -e "\nOptions:"
			echo "  -d, --date DATE  Explore file at backup DATE (use format YYYY-MM-DD-HHMMSS)"
			echo "  -a, --all        Print all versions, including duplicates"
			echo "  -h, --help       Print this help"
			;;
		status)
			echo ""
			echo -e "\nCheck if a backup is currently running"
			echo -e "\nOptions:"
			echo "  -q, --quiet  Quiet mode; print only backup dates"
			echo "  -h, --help   Print this help"
			;;
		config)
			echo ""
			echo -e "\nEdit configuration"
			echo -e "\nOptions:"
			echo "  -g, --general     Edit general configuration"
			echo "  -s, --sources     Edit sources file (sources to backup)"
			echo "  -x, --excludes    Edit excludes file (patterns to ignore)"
			echo "  -i, --includes    Edit includes file (patterns to include)"
			echo "  -l, --show        Show configuration; do not edit"
			echo "                    display configuration without comments"
			echo "  -t, --test        Test configuration; do not edit"
			echo "  -w, --wizard      Display configuration wizard instead of edit"
			echo "  -r, --reset       Reset configuration file"
			echo "  -e, --editor BIN  Use specified editor (e.g. vim, nano, ...)"
			echo "  -h, --help        Print this help"
			;;
		install)
			echo ""
			echo -e "\nInstall time2backup"
			echo -e "\nOptions:"
			echo "  -r, --reset-config  Reset configuration files to default"
			echo "  -h, --help          Print this help"
			;;
		uninstall)
			echo ""
			echo -e "\nUninstall time2backup"
			echo -e "\nOptions:"
			echo "  -c, --delete-config  Delete configuration files"
			echo "  -x, --delete         Delete time2backup files"
			echo "  -h, --help           Print this help"
			;;
	esac
}
