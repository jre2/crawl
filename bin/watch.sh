#!/bin/sh

inotifywait -q -m -e CLOSE_WRITE,MOVED_TO --format %e/%f ../src |
	while IFS=/ read -r events file; do
		if [[ $file == *.odin ]]; then
			echo -e "\n***** File change detected, restarting *****\n"
			./run.sh
		fi
	done
