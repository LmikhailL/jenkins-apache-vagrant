#!/bin/sh
# Intentionally broken: exits without sending HTTP headers -> 500
echo "this is not a valid CGI header" >&2
exit 1
