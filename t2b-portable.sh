#!/bin/bash
#
#  time2backup portable
#  It's time to backup your files!
#
#  Website: https://time2backup.org
#  MIT License
#  Copyright (c) 2017-2020 Jean Prunneaux
#

# get real path of the script
if [ "$(uname)" = Darwin ] ; then
	# macOS which does not support readlink -f option
	current_script=$(perl -e 'use Cwd "abs_path";print abs_path(shift)' "$0")
else
	current_script=$(readlink -f "$0")
fi

# get directory of the current script
script_directory=$(dirname "$current_script")

# run time2backup with local config
"$script_directory"/time2backup.sh -c "$script_directory"/config "$@"
exit $?
