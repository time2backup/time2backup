#
#  time2backup help functions
#
#  This file is part of time2backup (https://time2backup.org)
#
#  MIT License
#  Copyright (c) 2017-2019 Jean Prunneaux
#

# Print help for users in console
# Usage: print_help [global]
print_help() {
	echo
	echo "Usage: time2backup [GLOBAL_OPTIONS] COMMAND [OPTIONS] [ARG...]"
	echo
	echo "Global options:"
	echo "  -c, --config CONFIG_DIR    Load and save config in the specified directory"
	echo "  -d, --destination PATH     Set a custom destination path (overrides configuration)"
	echo "  -u, --user USER            Set a custom user to run backup (useful if sudo)"
	echo "  -l, --log-level LEVEL      Set a verbose and log level (ERROR|WARNING|INFO|DEBUG)"
	echo "  -v, --verbose-level LEVEL  Set a verbose and log level (ERROR|WARNING|INFO|DEBUG)"
	echo "  -C, --console              Execute time2backup in console mode (no dialog windows)"
	echo "  -D, --debug                Run in debug mode (all messages printed and logged)"
	echo "  -V, --version              Print version and quit"
	echo "  -h, --help                 Print help"
	echo

	if [ "$1" == global ] ; then
		echo "Commands:"
		echo "   backup     Backup your files"
		echo "   restore    Restore a backup of a file/directory"
		echo "   history    Displays backup history of a file/directory"
		echo "   explore    Open the file browser at a date"
		echo "   config     Edit configuration"
		echo "   mv         Move/rename a backup file/directory"
		echo "   clean      Clean files in backups"
		echo "   rotate     Force rotate backups"
		echo "   status     Check if a backup is currently running"
		echo "   stop       Cancel a running backup"
		echo "   import     Import backups from another folder or host"
		echo "   export     Export backups to another folder or host"
		echo "   install    Install time2backup"
		echo "   uninstall  Uninstall time2backup"
		echo
		echo "Run 'time2backup COMMAND --help' for more information on a command."
		return 0
	fi

	case $command in
		backup)
			print_help_usage "[PATH...]"

			echo "Backup your files"

			print_help_options
			echo "  -p, --progress      Display backup progress for each file (overrides configuration)"
			echo "  -c, --comment TEXT  Add a comment in backup meta data (infofile)"
			echo "  --resume            Resume from the last backup (useful for hard links)"
			echo "  -u, --unmount       Unmount destination after backup (overrides configuration)"
			echo "  -s, --shutdown      Shutdown after backup (overrides configuration)"
			echo "  -r, --recurrent     Perform a recurrent backup (used in cron jobs)"
			echo "  -t, --test          Test mode; do not backup files"
			echo "  --force-unlock      Force to backup if a lock is stuck (use with caution)"
			echo "  -q, --quiet         Quiet mode; do not print transfer details"
			echo "  -h, --help          Print help"
			;;

		restore)
			print_help_usage "[PATH]"

			echo "Restore a file or directory"
			echo "Warning: This feature does not auto-detect renamed or moved files."
			echo "         To restore a moved/deleted file, please enter an absolute path."

			print_help_options
			echo "  -d, --date DATE  Restore file at backup DATE (use format YYYY-MM-DD-HHMMSS)"
			echo "  -l, --latest     Restore the last available backup"
			echo "  --delete-new     Delete newer files if exists for directories (restore exactly the same version)"
			echo "  -p, --progress   Display restore progress for each file (overrides configuration)"
			echo "  -t, --test       Test mode; do not restore files"
			echo "  -f, --force      Force restore; do not display confirmation"
			echo "  -q, --quiet      Quiet mode; do not print transfer details"
			echo "  -h, --help       Print help"
			;;

		history)
			print_help_usage PATH

			echo "Get backup history of a file or directory"
			echo "Warning: This feature does not detect old renamed/moved files yet."

			print_help_options
			echo "  -a, --all    Print all versions, including duplicates"
			echo "  -q, --quiet  Quiet mode; print only backup dates"
			echo "  -h, --help   Print help"
			;;

		explore)
			print_help_usage "[PATH]"

			echo "Open file browser to explore backed up files"
			echo "If no path is specified, it will open the root backup folder."
			echo "Warning: This feature does not detect old renamed/moved files yet."

			print_help_options
			echo "  -d, --date DATE  Explore file at backup DATE (use format YYYY-MM-DD-HHMMSS)"
			echo "  -l, --latest     Explore only latest version"
			echo "  -a, --all        Explore all versions"
			echo "  -h, --help       Print help"
			;;

		config)
			print_help_usage

			echo "Edit configuration"

			print_help_options
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

		mv)
			print_help_usage PATH DESTINATION

			echo "Move/rename a backup file/directory"

			print_help_options
			echo "  -l, --latest  Move only the latest backup version"
			echo "  -f, --force   Force move; do not display confirmation"
			echo "  -q, --quiet   Quiet mode"
			echo "  -h, --help    Print help"
			;;

		clean)
			print_help_usage PATH

			echo "Delete backup versions of files"

			print_help_options
			echo "  -l, --keep-latest  Keep the latest backup version of the file(s)"
			echo "  -k, --keep N       Keep the N latest backups of the file(s)"
			echo "  -f, --force        Force clean; do not display confirmation"
			echo "  -q, --quiet        Quiet mode"
			echo "  -h, --help         Print help"
			;;

		rotate)
			print_help_usage [LIMIT]

			echo "Force rotate backups"

			print_help_options
			echo "  -f, --force  Force clean; do not display confirmation"
			echo "  -q, --quiet  Quiet mode"
			echo "  -h, --help   Print help"
			;;

		status)
			print_help_usage

			echo "Check if a backup is currently running"

			print_help_options
			echo "  -q, --quiet  Quiet mode"
			echo "  -h, --help   Print help"
			;;

		stop)
			print_help_usage

			echo "Cancel a running backup"

			print_help_options
			echo "  -f, --force  Do not print confirmation before stop"
			echo "  -q, --quiet  Quiet mode"
			echo "  -h, --help   Print help"
			;;

		import)
			print_help_usage PATH [DATE...]

			echo "Import backups from another folder or host"

			print_help_options
			echo "  -l, --latest      Import only the latest backup"
			echo "  --limit N         Limit import to N latest backups"
			echo "  --reference DATE  Specify a backup date reference"
			echo "  -f, --force       Do not print confirmation"
			echo "  -h, --help        Print help"
			echo
			echo "DATE              Backup date to import"
			echo "                  (Useful if you cannot get information about existing backups)"
			;;

		export)
			print_help_usage PATH

			echo "Export backups to another folder or host"

			print_help_options
			echo "  -l, --latest      Export only the latest backup"
			echo "  --limit N         Limit export to N latest backups"
			echo "  --reference DATE  Specify a backup date reference"
			echo "  -f, --force       Do not print confirmation"
			echo "  -h, --help        Print help"
			;;

		install)
			print_help_usage

			echo "Install time2backup"

			print_help_options
			echo "  -h, --help  Print help"
			;;

		uninstall)
			print_help_usage

			echo "Uninstall time2backup"

			print_help_options
			echo "  -y, --yes           Do not prompt confirmation to uninstall"
			echo "  -x, --delete-files  Delete time2backup files"
			echo "  -h, --help          Print help"
			;;
	esac
}


# Print help usage
# Usage: print_help_usage [ARG...]
print_help_usage() {
	echo "Command usage: $command [OPTIONS] $*"
	echo
}


# Print options text
# Usage: print_help_options
print_help_options() {
	echo
	echo "Options:"
}
