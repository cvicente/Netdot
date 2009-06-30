package Netdot::SectionAccessRule;

use Apache2::SiteControl::Rule;
@ISA = qw(Apache2::SiteControl::Rule);
use strict;
use Netdot::Model;

my $logger = Netdot->log->get_logger("Netdot::UI");

# This rule is going to be used in a system that automatically grants
# permission for everything (via the GrantAllRule). So this rule will
# only worry about what to deny, and the grants method can return whatever.

sub grants()
{
   return 0;
}

# Deny access to UI sections only available to Admins and Operators
sub denies(){
    my ($this, $user, $action, $resource) = @_;

    my $user_type = $user->getAttribute('USER_TYPE');
    my $username  = $user->getUsername();
    $resource ||= '(n/a)';
    $logger->debug("Netdot::SectionAccessRule::denies: Requesting $action $resource on behalf of $username ($user_type)");

    if ( $action eq "access_section" && ($user_type ne "Admin" && $user_type ne "Operator") ){
	$logger->debug("Netdot::SectionAccessRule::denies: Denying $action for $username ($user_type)");
	return 1;
    }
    
    return 0;
}

1;
