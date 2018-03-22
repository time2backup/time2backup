#
#  time2backup help functions
#
#  This file is part of time2backup (https://time2backup.org)
#
#  MIT License
#  Copyright (c) 2017-2018 Jean Prunneaux
#

# Print help for users in console
# Usage: print_help [global]
print_help() {
	echo
	echo "Usage: $lb_current_script_name [GLOBAL_OPTIONS] COMMAND [OPTIONS] [ARG...]"
	echo
	echo "Global options:"
	echo "  -C, --console              Execute time2backup in console mode (no dialog windows)"
	echo "  -l, --log-level LEVEL      Set a verbose and log level (ERROR|WARNING|INFO|DEBUG)"
	echo "  -v, --verbose-level LEVEL  Set a verbose and log level (ERROR|WARNING|INFO|DEBUG)"
	echo "  -d, --destination PATH     Set a custom destination path (overrides configuration)"
	echo "  -c, --config CONFIG_DIR    Load and save config in the specified directory"
	echo "  -D, --debug                Run in debug mode (all messages printed and logged)"
	echo "  -V, --version              Print version and quit"
	echo "  -h, --help                 Print help"
	echo

	if [ "$1" == global ] ; then
		echo "Commands:"
		echo "   backup     Backup your files"
		echo "   restore    Restore a backup of a file or directory"
		echo "   history    Displays backup history of a file or directory"
		echo "   explore    Open the file browser at a date"
		echo "   status     Check if a backup is currently running"
		echo "   stop       Cancel a running backup"
		echo "   clean      Clean files in backups"
		echo "   config     Edit configuration"
		echo "   install    Install time2backup"
		echo "   uninstall  Uninstall time2backup"
		echo
		echo "Run '$lb_current_script_name COMMAND --help' for more information on a command."
		return 0
	fi

	case $command in
		backup)
			echo "Command usage: $command [OPTIONS] [PATH...]"
			echo
			echo "Backup your files"
			echo
			echo "Options:"
			echo "  -p, --progress   Display backup progress for each file (overrides configuration)"
			echo "  -u, --unmount    Unmount destination after backup (overrides configuration)"
			echo "  -s, --shutdown   Shutdown after backup (overrides configuration)"
			echo "  -r, --recurrent  Perform a recurrent backup (used in cron jobs)"
			echo "  --force-unlock   Force to backup if a lock is stuck (use with caution)"
			echo "  -h, --help       Print help"
			;;
		restore)
			echo "Command usage: $command [OPTIONS] [PATH]"
			echo
			echo "Restore a file or directory"
			echo "Warning: This feature does not auto-detect renamed or moved files."
			echo "         To restore a moved/deleted file, please enter an absolute path."
			echo
			echo "Options:"
			echo "  -d, --date DATE  Restore file at backup DATE (use format YYYY-MM-DD-HHMMSS)"
			echo "                   by default it restores the last available backup"
			echo "  --delete-new     Delete newer files if exists for directories (restore exactly the same version)"
			echo "  -p, --progress   Display restore progress for each file (overrides configuration)"
			echo "  -f, --force      Force restore; do not display confirmation"
			echo "  -h, --help       Print help"
			;;
		history)
			echo "Command usage: $command [OPTIONS] PATH"
			echo
			echo "Get backup history of a file or directory"
			echo "Warning: This feature does not detect old renamed/moved files yet."
			echo
			echo "Options:"
			echo "  -a, --all    Print all versions, including duplicates"
			echo "  -q, --quiet  Quiet mode; print only backup dates"
			echo "  -h, --help   Print help"
			;;
		explore)
			echo "Command usage: $command [OPTIONS] [PATH]"
			echo
			echo "Open file browser to explore backuped files"
			echo "If no path is specified, it will open the root backup folder."
			echo "Warning: This feature does not detect old renamed/moved files yet."
			echo
			echo "Options:"
			echo "  -d, --date DATE  Explore file at backup DATE (use format YYYY-MM-DD-HHMMSS)"
			echo "  -a, --all        Explore all versions"
			echo "  -h, --help       Print help"
			;;
		status)
			echo "Command usage: $command [OPTIONS]"
			echo
			echo "Check if a backup is currently running"
			echo
			echo "Options:"
			echo "  -q, --quiet  Quiet mode"
			echo "  -h, --help   Print help"
			;;
		stop)
			echo "Command usage: $command [OPTIONS]"
			echo
			echo "Cancel a running backup"
			echo
			echo "Options:"
			echo "  -f, --force  Do not print confirmation before stop"
			echo "  -q, --quiet  Quiet mode"
			echo "  -h, --help   Print help"
			;;
		mv)
			echo "Command usage: $command [OPTIONS] PATH DESTINATION"
			echo
			echo "Move last backup file path"
			echo
			echo "Options:"
			echo "  -f, --force  Force move; do not display confirmation"
			echo "  -q, --quiet  Quiet mode"
			echo "  -h, --help   Print help"
			;;
		clean)
			echo "Command usage: $command [OPTIONS] PATH"
			echo
			echo "Clean files in backups"
			echo
			echo "Options:"
			echo "  -f, --force  Force clean; do not display confirmation"
			echo "  -q, --quiet  Quiet mode"
			echo "  -h, --help   Print help"
			;;
		config)
			echo "Command usage: $command [OPTIONS]"
			echo
			echo "Edit configuration"
			echo
			echo "Options:"
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
			echo "  -h, --help        Print help"
			;;
		install)
			echo "Command usage: $command [OPTIONS]"
			echo
			echo "Install time2backup"
			echo
			echo "Options:"
			echo "  -h, --help  Print help"
			;;
		uninstall)
			echo "Command usage: $command [OPTIONS]"
			echo
			echo "Uninstall time2backup"
			echo
			echo "Options:"
			echo "  -y, --yes           Do not prompt confirmation to uninstall"
			echo "  -x, --delete-files  Delete time2backup files"
			echo "  -h, --help          Print help"
			;;
	esac
}
