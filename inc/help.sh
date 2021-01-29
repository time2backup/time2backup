#
#  time2backup help functions
#
#  This file is part of time2backup (https://time2backup.org)
#
#  MIT License
#  Copyright (c) 2017-2021 Jean Prunneaux
#

# Print help for users in console
# Usage: print_help [global]
print_help() {
	echo "
Usage: time2backup [GLOBAL_OPTIONS] COMMAND [OPTIONS] [ARG...]

Global options:
   -c, --config CONFIG_DIR    Load and save config in the specified directory
   -d, --destination PATH     Set a custom destination path (overrides configuration)
   -u, --user USER            Set a custom user to run backup (useful if sudo)
   -l, --log-level LEVEL      Set a verbose and log level (ERROR|WARNING|INFO|DEBUG)
   -v, --verbose-level LEVEL  Set a verbose and log level (ERROR|WARNING|INFO|DEBUG)
   -C, --console              Execute time2backup in console mode (no dialog windows)
   -D, --debug                Run in debug mode (all messages printed and logged)
   -V, --version              Print version and quit
   -h, --help                 Print help
"

	if [ "$1" = global ] ; then
		echo "Commands:" #help_global
		echo "   backup     Backup your files
   restore    Restore a backup of a file/directory
   history    Displays backup history of a file/directory
   explore    Open the file browser at a date
   config     Edit configuration
   mv         Move/rename a backup file/directory
   clean      Clean files in backups
   rotate     Force rotate backups
   status     Check if a backup is currently running
   stop       Cancel a running backup
   import     Import backups from another folder or host
   export     Export backups to another folder or host

   install    Install time2backup
   uninstall  Uninstall time2backup

   Run 'time2backup COMMAND --help' for more information on a command."
		return 0
	fi

	case $command in
		backup)
			print_help_usage "[PATH...]"

			echo "Backup your files"

			print_help_options #backup
			echo "   -p, --progress      Display backup progress for each file (overrides configuration)
   -c, --comment TEXT  Add a comment in backup meta data (infofile)
   --resume            Resume from the last backup (useful for hard links)
   -u, --unmount       Unmount destination after backup (overrides configuration)
   -s, --shutdown      Shutdown after backup (overrides configuration)
   -r, --recurrent     Perform a recurrent backup (used in cron jobs)
   -t, --test          Test mode; do not backup files
   --force-unlock      Force to backup if a lock is stuck (use with caution)
   -q, --quiet         Quiet mode; do not print transfer details
   -h, --help          Print help
"
			;;

		restore)
			print_help_usage "[PATH] [DESTINATION]"

			echo "Restore a file or directory"
			echo "Warning: This feature does not auto-detect renamed or moved files."
			echo "         To restore a moved/deleted file, please enter an absolute path."

			print_help_options #restore
			echo "   -d, --date DATE  Restore file at backup DATE (use format YYYY-MM-DD-HHMMSS)
   -l, --latest     Restore the last available backup
   --delete-new     Delete newer files if exists for directories (restore exactly the same version)
   -p, --progress   Display restore progress for each file (overrides configuration)
   -t, --test       Test mode; do not restore files
   --no-lock        Do not create a lock when restoring
   -f, --force      Force restore; do not display confirmation
   -q, --quiet      Quiet mode; do not print transfer details
   -h, --help       Print help

   PATH             Path to restore (if not specified, ask in interactive)
   DESTINATION      Destination for restored files
"
			;;

		history)
			print_help_usage PATH

			echo "Get backup history of a file or directory"
			echo "Warning: This feature does not detect old renamed/moved files yet."

			print_help_options #history
			echo "   -a, --all    Print all versions, including duplicates
   -q, --quiet  Quiet mode; print only backup dates
   -h, --help   Print help
"
			;;

		explore)
			print_help_usage "[PATH]"

			echo "Open file browser to explore backed up files"
			echo "If no path is specified, it will open the root backup folder."
			echo "Warning: This feature does not detect old renamed/moved files yet."

			print_help_options #explore
			echo "   -d, --date DATE  Explore file at backup DATE (use format YYYY-MM-DD-HHMMSS)
   -l, --latest     Explore only latest version
   -a, --all        Explore all versions
   -h, --help       Print help
"
			;;

		config)
			print_help_usage

			echo "Edit configuration"

			print_help_options #config
			echo "   -g, --general     Edit general configuration
   -s, --sources     Edit sources file (sources to backup)
   -x, --excludes    Edit excludes file (patterns to ignore)
   -i, --includes    Edit includes file (patterns to include)
   -l, --show        Show configuration; do not edit
                     display configuration without comments
   -t, --test        Test configuration; do not edit
   -w, --wizard      Display configuration wizard instead of edit
   -r, --reset       Reset configuration file
   -e, --editor BIN  Use specified editor (e.g. vim, nano, ...)
   -h, --help        Print help
"
			;;

		mv)
			print_help_usage PATH DESTINATION

			echo "Move/rename a backup file/directory"

			print_help_options #mv
			echo "   -l, --latest  Move only the latest backup version
   -f, --force   Force move; do not display confirmation
   -q, --quiet   Quiet mode
   -h, --help    Print help
"
			;;

		clean)
			print_help_usage PATH

			echo "Delete backup versions of files"

			print_help_options #clean
			echo "   -l, --keep-latest  Keep the latest backup version of the file(s)
   -k, --keep N       Keep the N latest backups of the file(s)
   -f, --force        Force clean; do not display confirmation
   -q, --quiet        Quiet mode
   -h, --help         Print help
"
			;;

		rotate)
			print_help_usage "[LIMIT]"

			echo "Force rotate backups"

			print_help_options #rotate
			echo "   -t, --test   Test mode; do not delete backups
   -f, --force  Force clean; do not display confirmation
   -q, --quiet  Quiet mode
   -h, --help   Print help
"
			;;

		status)
			print_help_usage

			echo "Check if a backup is currently running"

			print_help_options #status
			echo "   -q, --quiet  Quiet mode
   -h, --help   Print help
"
			;;

		stop)
			print_help_usage

			echo "Cancel a running backup"

			print_help_options #stop
			echo "   -f, --force  Do not print confirmation before stop
   -q, --quiet  Quiet mode
   -h, --help   Print help
"
			;;

		import)
			print_help_usage PATH "[DATE...]"

			echo "Import backups from another folder or host"

			print_help_options #import
			echo "   -l, --latest          Import only the latest backup
   --limit N             Limit import to N latest backups
   -r, --reference DATE  Specify a backup date reference
   -a, --all             Import all backups, even already existing ones
   -f, --force           Do not print confirmation
   -h, --help            Print help

   DATE                    Backup date to import
                           (Useful if you cannot get information about existing backups)
"
			;;

		export)
			print_help_usage PATH

			echo "Export backups to another folder or host"

			print_help_options #export
			echo "   -l, --latest          Export only the latest backup
   --limit N             Limit export to N latest backups
   -r, --reference DATE  Specify a backup date reference
   -a, --all             Export all backups, even already existing ones
   -f, --force           Do not print confirmation
   -h, --help            Print help
"
			;;

		install)
			print_help_usage

			echo "Install time2backup"

			print_help_options #install
			echo "   -h, --help  Print help
"
			;;

		uninstall)
			print_help_usage

			echo "Uninstall time2backup"

			print_help_options #uninstall
			echo "   -y, --yes           Do not prompt confirmation to uninstall
   -x, --delete-files  Delete time2backup files
   -h, --help          Print help
"
			;;
	esac
}


# Print help usage
# Usage: print_help_usage [ARG...]
print_help_usage() {
	echo "Command usage: $command [OPTIONS] $*
"
}


# Print options text
# Usage: print_help_options
print_help_options() {
	echo "
Options:"
}
