package Netdot::NetdotPermissionFactory;

use Apache2::SiteControl::PermissionManager;
use Apache2::SiteControl::GrantAllRule;
use Netdot::SectionAccessRule;
use Netdot::ObjectAccessRule;

our $manager;

sub getPermissionManager
{
   return $manager if defined($manager);

   $manager = new Apache2::SiteControl::PermissionManager;
   $manager->addRule(new Apache2::SiteControl::GrantAllRule);
   $manager->addRule(new Netdot::SectionAccessRule);
   $manager->addRule(new Netdot::ObjectAccessRule);

   return $manager;
}

1;
