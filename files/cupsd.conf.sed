# https://www.cups.org/doc/man-cupsd.conf.html
# Listen on all interfaces
s/^Listen localhost:631$/Listen *:631/
# Allow access from local subnets to / and /admin
/^<Location \/>$/a\  Allow @LOCAL
/^<Location \/admin>$/a\  Allow @LOCAL
