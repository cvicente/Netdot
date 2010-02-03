package Netdot::Model::Person;

use base 'Netdot::Model';
use Digest::SHA qw(sha256_base64);
use warnings;
use strict;

=head1 NAME

Netdot::Model::Person - Manipulate Person objects

=head1 SYNOPSIS
    
    $person->verify_passwd($pass);
    
=cut

my $logger = Netdot->log->get_logger('Netdot::Model');

=head1 CLASS METHODS
=cut


############################################################################
=head2 insert - Insert new Person object

    We override the base method to:
      - Set some defaults
  Arguments:
    Hashref with key/value pairs
  Returns:
    Person object
  Example:
    my $person = Person->insert(\%args)

=cut
sub insert {
    my($class, $argv) = @_;
    $class->isa_class_method('insert');
    
    $class->throw_fatal('Missing required arguments')
	unless ( $argv->{lastname} );
    
    unless ( defined $argv->{user_type} && $argv->{user_type} ne '0' ){
	if ( my $t = UserType->search(name=>'User')->first ){
	    $argv->{user_type} = $t;
	}
    }
    return $class->SUPER::insert($argv);
}

=head1 INSTANCE METHODS
=cut

##################################################################
=head2 delete - Delete Person object

    We make sure the last admin is not deletable.
    
  Arguments: 
    none
   Returns:
    True if successful
  Examples:
    $person->delete();

=cut
sub delete {
    my ($self, %args) = @_;
    $self->isa_object_method('delete');

    if ( $self->user_type && $self->user_type->name eq 'Admin' ) {
	my $admin_type = UserType->search(name=>"Admin")->first 
	    || $self->throw_fatal("Can't retrieve Admin type");
	my @no_of_admins = $self->search(user_type=>$admin_type);
	if ( scalar @no_of_admins > 1 ) {
	    return $self->SUPER::delete();
	} else {
	    $self->throw_user("You cannot delete the last Admin user!");
	}
    } else {
	# not an admin
	return $self->SUPER::delete();
    }
}

##################################################################
=head2 verify_passwd - Verify password for this person

  Arguments:
    Plaintext password
  Returns:
    True or False
  Example:
    if ( $person->verify_passwd($plaintext) ){
    ...

=cut
sub verify_passwd {
    my ($self, $plaintext) = @_;

    return 1 if ( sha256_base64($plaintext) eq $self->password );
    return 0;
}

##################################################################
=head2 get_allowed_objects

    'Allowed' objects are objects for which this Person, or a group
    to which this Person belongs, has access rights to

  Arguments:
    None
  Returns:
    Hashref
  Example:
    my $hashref = $person->get_allowed_objects();

=cut
sub get_allowed_objects {
    my ($self, %argv) = @_;
    
    my %results;
    my $authorization_method = Netdot->config->get('AUTHORIZATION_METHOD');
    
    if (  $authorization_method =~ /^LOCAL$/i ){
	my $id  = $self->id;
	my $dbh = $self->db_Main();
	
	# Get access rights from contactlists this person belongs to
	my $gq  = "SELECT  accessright.object_class, accessright.object_id, accessright.access
                   FROM    contact, contactlist, accessright, groupright
                   WHERE   contact.person=$id
                       AND contact.contactlist=contactlist.id
                       AND groupright.contactlist=contactlist.id
                       AND groupright.accessright=accessright.id";
	my $gqr = $dbh->selectall_arrayref($gq);
	
	# Get access rights from person
	my $uq = "SELECT    accessright.object_class, accessright.object_id, accessright.access
                  FROM      accessright, userright 
                  WHERE     userright.person=$id 
                     AND    userright.accessright=accessright.id";
	my $uqr = $dbh->selectall_arrayref($uq);

	# Assign rights from contact lists
	my %group_rights;
	foreach my $row ( @$gqr ){
	    my ($oclass, $oid, $access) = @$row;
	    $group_rights{$oclass}{$oid}{$access} = 1;
	}

	# Assign person rights 
	my %person_rights;
	foreach my $row ( @$uqr ){
	    my ($oclass, $oid, $access) = @$row;
	    $person_rights{$oclass}{$oid}{$access} = 1;
	}

	# Person rights on an object override group rights
	foreach my $oclass ( keys %group_rights ){
	    foreach my $oid ( keys %{$group_rights{$oclass}} ){
		$results{$oclass}{$oid} = $group_rights{$oclass}{$oid};
	    }
	}
	foreach my $oclass ( keys %person_rights ){
	    foreach my $oid ( keys %{$person_rights{$oclass}} ){
		$results{$oclass}{$oid} = $person_rights{$oclass}{$oid};
	    }
	}

	# Remove all rights on objects where 'none' is found
	foreach my $oclass ( keys %results ){
	    foreach my $oid ( keys %{$results{$oclass}} ){
		delete $results{$oclass}{$oid} if exists $results{$oclass}{$oid}{'none'};
	    }
	    delete $results{$oclass} unless keys %{$results{$oclass}};
	}

    }elsif ( $authorization_method =~ /^LDAP$/i ){
	    $self->throw_user("LDAP authorization not supported yet!");
    }
    elsif ($authorization_method =~ /^RADIUS$/i ){
        $self->throw_user("RADIUS authorization not supported yet!");
    }

    return \%results;
}

##################################################################
=head2 get_user_type

    This attribute can be loaded from the Netdot
    database or from external sources such as LDAP.  This behavior
    is controlled by the 'AUTHORIZATION_METHOD' configuration item.

  Arguments:
    None
  Returns:
    String
  Example:
    my $user_type = $person->get_user_type();

=cut
sub get_user_type {
    my ($self, $r) = @_;

    my $user_type;
    my $authorization_method = Netdot->config->get('AUTHORIZATION_METHOD');
    
    if (  $authorization_method =~ /^LOCAL$/i ){
	if ( defined $self->user_type ) {
	    $user_type = $self->user_type->name;
	}else{
	    $self->throw_user($self->get_label." user_type is not set");
	}
	
    }elsif ( $authorization_method =~ /^LDAP$/i ){
        $self->throw_user("LDAP NOT SUPPORTED!");
    }
    elsif ( $authorization_method =~ /^RADIUS/i ){
        $self->throw_user("RADIUS NOT SUPPORTED!");
    }
}
##################################################################
# PRIVATE METHODS
##################################################################

##################################################################
# Stores a SHA-256 base64-encoded digest of given password 
#
sub _encrypt_passwd { 
    my ($self) = @_;
    my $plaintext = ($self->_attrs('password'))[0];
    my $digest = sha256_base64($plaintext);
    $self->_attribute_store(password=>$digest);  
    return 1;
}

__PACKAGE__->add_trigger( deflate_for_create => \&_encrypt_passwd );
__PACKAGE__->add_trigger( deflate_for_update => \&_encrypt_passwd );


=head1 AUTHORS

Carlos Vicente, C<< <cvicente at ns.uoregon.edu> >> 

=head1 COPYRIGHT & LICENSE

Copyright 2009 University of Oregon, all rights reserved.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTIBILITY
or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software Foundation,
Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

=cut

# Make sure to return 1
1;
