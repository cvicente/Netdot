package Netdot::SiteConfig;

use base qw( Netdot::DefaultConfig );

# Be sure to return true.
1;

######################################################################
# Copy any relevant variables from lib/Netdot/DefaultConfig.pm
# and paste them here.  Change their values to match
# your environment
######################################################################

# The name of the machine or virtual host where Netdot is located
use constant NETDOTNAME => "netdot";

# The Domain Name of the 
use constant DOMAIN => "mydomain.com";

# Email of the Netdot administrator
use constant ADMINEMAIL => "root";

# Email of the group that receives Netdot's informational messages
use constant NOCEMAIL => "noc@mydomain.com";


