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
	lb_print "\nUsage: $lb_current_script_name [GLOBAL_OPTIONS] COMMAND [OPTIONS] [ARG...]"
	lb_print "\nGlobal options:"
	lb_print "  -C, --console              execute time2backup in console mode (no dialog windows)"
	lb_print "  -p, --portable             execute time2backup in a portable mode"
	lb_print "                             (no install, use local config files, meant to run from removable devices)"
	lb_print "  -l, --log-level LEVEL      set a verbose and log level (ERROR|WARNING|INFO|DEBUG)"
	lb_print "  -v, --verbose-level LEVEL  set a verbose and log level (ERROR|WARNING|INFO|DEBUG)"
	lb_print "  -c, --config CONFIG_FILE   overwrite configuration with specific file"
	lb_print "  -D, --debug                run in debug mode (all messages printed and logged)"
	lb_print "  -V, --version              print version and quit"
	lb_print "  -h, --help                 print help \n"

	case $1 in
		backup)
			lb_print "Command usage: $1 [OPTIONS] [PATH...]"
			lb_print "\nBackup your files"
			lb_print "\nOptions:"
			lb_print "  -u, --unmount    unmount destination after backup (overrides configuration)"
			lb_print "  -s, --shutdown   shutdown after backup (overrides configuration)"
			lb_print "  -r, --recurrent  perform a recurrent backup (used in cron jobs, not available in portable mode)"
			lb_print "  -h, --help       print help"
			;;
		restore)
			lb_print "Command usage: $1 [OPTIONS] [PATH]"
			lb_print "\nRestore a file or directory"
			lb_print "Warning: This feature does not auto-detect renamed or moved files."
			lb_print "         To restore a moved/deleted file, ."
			lb_print "\nOptions:"
			lb_print "  -d, --date DATE  restore file at backup DATE (use format YYYY-MM-DD-HHMMSS)"
			lb_print "                   by default it restores the last available backup"
			lb_print "  --directory      path to restore is a directory (not necessary if path exists)"
			lb_print "                   If deleted or moved, indicate that the chosen path is a directory."
			lb_print "  --delete-new     delete newer files if exists for directories (restore exactly the same version)"
			lb_print "  -f, --force      force restore; do not display confirmation"
			lb_print "  -h, --help       print help"
			;;
		history)
			lb_print "Command usage: $1 [OPTIONS] PATH"
			lb_print "\nGet backup history of a file or directory"
			lb_print "Warning: This feature does not detect old renamed/moved files yet."
			lb_print "\nOptions:"
			lb_print "  -a, --all    print all versions, including duplicates"
			lb_print "  -q, --quiet  quiet mode; print only backup dates"
			lb_print "  -h, --help   print help"
			;;
		config)
			lb_print "Command usage: $1 [OPTIONS]"
			lb_print "\nEdit configuration"
			lb_print "\nOptions:"
			lb_print "  -g, --general     edit general configuration"
			lb_print "  -s, --sources     edit sources file (sources to backup)"
			lb_print "  -x, --excludes    edit excludes file (patterns to ignore)"
			lb_print "  -i, --includes    edit includes file (patterns to include)"
			lb_print "  -l, --show        show configuration; do not edit"
			lb_print "                    display configuration without comments"
			lb_print "  -t, --test        test configuration; do not edit"
			lb_print "  -w, --wizard      display configuration wizard instead of edit"
			lb_print "  -e, --editor BIN  use specified editor (e.g. vim, nano, ...)"
			lb_print "  -h, --help        print help"
			;;
		install)
			lb_print "Command usage: $1 [OPTIONS]"
			lb_print "\nInstall time2backup"
			lb_print "\nOptions:"
			lb_print "  -r, --reset-config  reset configuration files to default"
			lb_print "  -h, --help          print help"
			;;
		uninstall)
			lb_print "Command usage: $1 [OPTIONS]"
			lb_print "\nUninstall time2backup"
			lb_print "\nOptions:"
			lb_print "  -c, --delete-config  delete configuration files"
			lb_print "  -x, --delete         delete time2backup files"
			lb_print "  -h, --help           print help"
			;;
		*)
			lb_print "Commands:"
			lb_print "    backup     backup your files"
			lb_print "    restore    restore a backup of a file or directory"
			lb_print "    history    displays backup history of a file or directory"
			lb_print "    config     edit configuration"
			lb_print "    install    install time2backup"
			lb_print "    uninstall  uninstall time2backup"
			lb_print "\nRun '$lb_current_script_name COMMAND --help' for more information on a command."
			;;
	esac
}
