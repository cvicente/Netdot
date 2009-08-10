package Netdot::Model::UserRight;

use base 'Netdot::Model';
use warnings;
use strict;

=head1 NAME

Netdot::Model::UserRight - Manipulate UserRight objects

=head1 SYNOPSIS
    
    
=cut

my $logger = Netdot->log->get_logger('Netdot::Model');

=head1 CLASS METHODS
=cut


#########################################################################
=head2 insert - Insert a new UserRight object

    We override the insert method for extra functionality
    - Ignore duplicates
    - Check if 'none' exists for given object and complain.
    - If adding 'none' remove all other rights


  Args: 
    userright table fields
  Returns: 
    UserRight object
  Examples:
    UserRight->insert({person=>$person_id, accessright=>$ar_id });

=cut
sub insert {
    my ($class, $argv) = @_;
    $class->throw_fatal("Model::UserRight::insert: Missing required arguments")
	unless ( $argv->{person} && $argv->{accessright} );

    my $accessright = AccessRight->retrieve(int($argv->{accessright}));
    my $person      = Person->retrieve(int($argv->{person}));
    
    foreach my $r ( $person->access_rights ){
	my $ar = $r->accessright;
	if ( $ar->object_class eq $accessright->object_class &&
	     $ar->object_id eq $accessright->object_id ){
	    # same object
	    if ( $accessright->access eq $ar->access ){
		# Do not try to insert rights if they exist
		return $r;
	    }
	    if ( $accessright->access ne 'none' && $ar->access eq 'none' ){
		$class->throw_user("Cannot add other rights while 'none' right exists");

	    }elsif ( $accessright->access eq 'none' && $ar->access ne 'none' ){
		$logger->debug("UserRight::insert: Removing ".$ar->access." access on ".$ar->object_class." id ".$ar->object_id);
		$ar->delete();
	    }
	}
    }
    return $class->SUPER::insert($argv);
}

