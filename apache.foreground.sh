#!/bin/bash

read pid cmd state ppid pgrp session tty_nr tpgid rest < /proc/self/stat
trap "kill -TERM -$pgrp; exit" EXIT TERM KILL SIGKILL SIGTERM SIGQUIT


source /etc/apache2/envvars

mkdir -p /var/run/apache2
chown ${APACHE_RUN_USER}:${APACHE_RUN_GROUP} /var/run/apache2

apache2 -D FOREGROUND
