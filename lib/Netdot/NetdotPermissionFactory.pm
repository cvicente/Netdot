package Netdot::NetdotPermissionFactory;

use SiteControl::PermissionManager;
use SiteControl::GrantAllRule;
#use Netdot::EditControlRule;

our $manager;

sub getPermissionManager
{
   return $manager if defined($manager);

   $manager = new SiteControl::PermissionManager;
   $manager->addRule(new SiteControl::GrantAllRule);
   #$manager->addRule(new Netdot::EditControlRule);

   return $manager;
}

1;
