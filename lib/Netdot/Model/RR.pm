package Netdot::Model::RR;

use base 'Netdot::Model';
use warnings;
use strict;

my $logger = Netdot->log->get_logger('Netdot::Model::DNS');

=head1 NAME

Netdot::Model::RR - DNS Resource Record Class

=head1 SYNOPSIS

    Objects of this class do not contain actual DNS records.
    Each record type has its own table that references
    this base record.

    RR->search(name=>"some.domain.name")

=head1 CLASS METHODS
=cut

############################################################################

=head2 search - Search Resource Records

    We override the base class to extend functionality:

      - If zone arg is not passed, try to find zone based on FQDN

  Arguments: 
    Hash with column/value pairs.  
    'name' can be either FQDN or host part of the name
  Returns: 
    RR object or undef
  Examples:
    RR->search(name=>'foo.bar')

=cut

sub search {
    my ($class, @args) = @_;
    $class->isa_class_method('search');

    @args = %{ $args[0] } if ref $args[0] eq "HASH";
    my $opts = @args % 2 ? pop @args : {}; 
    my %argv = @args;

    my ($rr, @sections);
    if ( exists $argv{zone} ){
	if ( !ref($argv{zone}) && $argv{zone} =~ /\D/o ){
	    # Looks like a zone name. Look it up.
	    if ( my $zone = (Zone->search(name=>$argv{zone}))[0] ){
		$argv{zone} = $zone->id;
	    }
	}
    }else{
	if ( exists $argv{name} && $argv{name} =~ /\./o ){
	    # Name string potentially contains existing zone
	    if ( my $zone = (Zone->search(name=>$argv{name}))[0] ){
		my $zname = $zone->name;
		$argv{name} =~ s/\.$zname//; # Remove part from RR
		$argv{zone} = $zone->id;
	    }
	}
    }
    return $class->SUPER::search(%argv, $opts);
}

############################################################################

=head2 search_like - Search Resource Records with wildcards

    We override the base class to extend functionality:

      - If zone key is not passed, name will be looked up assuming it might
        contain domain info.

  Arguments: 
    Hash with column/value pairs.  
    'name' can be either FQDN or host part of the name
  Returns: 
    RR object or undef
  Examples:
    RR->search_like(name=>"foo*.bar")

=cut

sub search_like {
    my ($class, %argv) = @_;
    $class->isa_class_method('search_like');
    $class->throw_fatal('Model::RR::search_like: Missing required arguments')
	unless %argv;

    my ($rr, @sections);
    if ( (exists $argv{name}) && ($argv{name} =~ /\./)  && !exists $argv{zone} ){
	if ( my $zone = (Zone->search(name=>$argv{name}))[0] ){
	    my $name = $zone->name;
	    if ($argv{name} eq $name) {
		$name =~ s/^.*?\.//;
		my $alt_name = $name;
		if ( my $alt_zone = (Zone->search(name=>$alt_name))[0] ) {
		    $alt_name = $alt_zone->name;
		    $argv{name} =~ s/\.$alt_name//;
		    $argv{zone} = $alt_zone->id;
		    return $class->SUPER::search_like(%argv);
		} else {
		    #alternative zone not found, search normally
		    return $class->SUPER::search_like(%argv);
		}
	    } else {
		$argv{name} =~ s/\.$name//;
		$argv{zone} = $zone->id;
		return $class->SUPER::search(%argv);
	    }
	}else{
	    # Zone not found, just do normal search
	    return $class->SUPER::search_like(%argv);
	}
    }else{
	return $class->SUPER::search_like(%argv);
    }
    return;
}


############################################################################

=head2 insert - Insert new RR

    We override the common insert method for extra functionality

 Argsuments: 
    name        Unique record identifier (AKA "owner")
    zone        Zone object, id or name. If not defined, will assume 
                'DEFAULT_DNSDOMAIN' from config file
                If defined, will create if necessary.
    expiration  Expiration date
    info        Comments
    type        <A|AAAA|TXT|HINFO|CNAME|NS|MX|NAPTR|SRV|PTR|LOC> 
                Create records for these types 
                (need to pass their specific arguments)
    rr          Owner RR (if already created)
    update_ptr  If Creating a A/AAAA, automatically insert corresponding PTR
    
  Returns: 
    New RR object, or RRADDR, RRTXT, etc. if type is specified.

  Examples:
    my $newrr = RR->insert( { name=> $name } );

=cut

sub insert {
    my ($class, $argv) = @_;
    $class->isa_class_method('insert');
    $class->throw_fatal('Model::RR::insert: Missing required parameters: name or rr')
	unless ( defined $argv->{name} || defined $argv->{rr} );

    # Set default zone if needed
    if ( defined($argv->{type}) && $argv->{type} eq 'CNAME' && 
    	 defined($argv->{name}) && $argv->{name} =~ /\.$/ ){
    	# In this particular case, the user specified a dot at the end, which indicates
    	# that the label should not get the zone name appended
    	if ( my $z = (Zone->search(name=>$argv->{name}))[0] ){
    	    $argv->{zone} = $z;
    	}
    }else{
    	$argv->{zone} = $class->config->get('DEFAULT_DNSDOMAIN') || 'localdomain'
    	    unless ($argv->{zone});
    }
    
    # Insert zone if necessary;
    my $zone;
    unless ( $zone = Zone->objectify($argv->{zone}) ){
	$logger->debug(sub{ sprintf("Zone not found: \"%s\".  Inserting.", $argv->{zone}) });
	$zone = Zone->insert({ name => $argv->{zone} });
	$logger->info(sprintf("Inserted new Zone: %s", $zone->get_label));
    }
    
    # If the RR name contains the zone name, let's assume that it was a mistake
    # and remove it
    my $domain = $zone->name;
    if ( $argv->{name} =~ /\.$domain\.?$/i ){
	$argv->{name} =~ s/\.$domain\.?$//i;
    }

    my $rr;

    if ( $argv->{rr} ){
	$rr = (ref($argv->{rr}))? $argv->{rr} : RR->retrieve($argv->{rr});
    }elsif ( $rr = $class->search(name=>$argv->{name}, zone=>$zone)->first ){
	if ( !defined $argv->{type} ){
	    $class->throw_user(sprintf("RR::Insert: %s.%s already exists!", $rr->name, $rr->zone->name));
	}
    }else{
	# Set some defaults
	my $auto_update = defined($argv->{auto_update})? 
	    $argv->{auto_update} : Netdot->config->get('DEVICE_IP_NAME_AUTO_UPDATE_DEFAULT');
	
	my %state = (name        => $argv->{name},
		     zone        => $zone->id,
		     created     => $class->timestamp,
		     modified    => $class->timestamp,
		     active      => defined($argv->{active})? $argv->{active} : 1,
		     auto_update => $auto_update,
		     expiration  => $argv->{expiration},
		     info        => $argv->{info},
	    );

	$class->_validate_args(\%state);
	
	$rr = $class->SUPER::insert(\%state);
	
	if ( !defined $argv->{type} ){
	    return $rr;
	}
    }
    
    # Pass our arguments to the more specific record type
    my %args = %$argv;
    $args{rr} = $rr;

    # Remove arguments specific to RR
    foreach my $arg (qw/type name zone expiration info/){
	delete $args{$arg};
    }

    if ( exists $argv->{type} ){
	if ( $argv->{type} eq 'A' || $argv->{type} eq 'AAAA' ){
	    return RRADDR->insert(\%args);
	    
	}elsif ( $argv->{type} eq 'CNAME' ){
	    return RRCNAME->insert(\%args);
	    
	}elsif ( $argv->{type} eq 'DS' ){
	    return RRDS->insert(\%args);
	    
	}elsif ( $argv->{type} eq 'HINFO' ){
	    return RRHINFO->insert(\%args);
	    
	}elsif ( $argv->{type} eq 'LOC' ){
	    return RRLOC->insert(\%args);    
	    
	}elsif ( $argv->{type} eq 'MX' ){
	    return RRMX->insert(\%args);
	    
	}elsif ( $argv->{type} eq 'NAPTR' ){
	    return RRNAPTR->insert(\%args);    
	    
	}elsif ( $argv->{type} eq 'NS' ){
	    return RRNS->insert(\%args);
	    
	}elsif ( $argv->{type} eq 'PTR' ){
	    return RRPTR->insert(\%args);
	    
	}elsif ( $argv->{type} eq 'SRV' ){
	    return RRSRV->insert(\%args);    
	    
	}elsif ( $argv->{type} eq 'TXT' ){
	    return RRTXT->insert(\%args);
	    
	}else{
	    $class->throw_user("Unrecognized type: ".$argv->{type});
	}
    }
}

=head1 INSTANCE METHODS
=cut

##################################################################

=head2 aliases - Get list of aliases pointing to this record

    NOTE: Not to be confused with $rr->cnames, which
    gets the RRCNAME records associated with an RR that
    is the alias name.

  Arguments:
    None
  Returns:
    Array of RRCNAME objects
  Examples:
    @list = $rr->aliases()

=cut

sub aliases {
    my $self = shift;
    return RRCNAME->search(cname=>$self->get_label);
}

##################################################################

=head2 update

    Override base method to:
    - Update existing CNAMES
    - Add option to update related RRPTR if name changes
  Arguments:
    Hashref with key/value pairs, plus:
       update_ptr - 0 or 1
  Returns:
    See Netdot::Model::update
  Examples:
    $rr->update(\%args)

=cut

sub update {
    my ($self, $argv) = @_;
    $self->isa_object_method('update');

    # Get CNAMEs that point to me
    my $old_fqdn = $self->get_label;
    my @cnames = $self->aliases();

    my $update_ptr = 1; # On by default
    if ( defined $argv->{update_ptr} && $argv->{update_ptr} == 0 ){
	$update_ptr = 0;
	delete $argv->{update_ptr};
    }

    $self->_validate_args($argv);

    my @res = $self->SUPER::update($argv);

    $self->update_ptr() if ( $update_ptr );

    # Update those CNAMEs if needed
    if ( $self->get_label ne $old_fqdn ){
	foreach my $cname ( @cnames ){
	    $cname->update({cname=>$self->get_label});
	}
    }

    return @res;
}

##################################################################

=head2 update_ptr - Update corresponding PTR record

  Arguments:
    None
  Returns:
    True
  Examples:
    $rr->update_ptr()

=cut

sub update_ptr {
    my ($self) = @_;
    $self->isa_object_method('update_ptr');
    
    if ( my @a_records = $self->a_records ){
	foreach my $rraddr ( @a_records ){
	    my $ip = $rraddr->ipblock;
	    next if ( scalar($ip->a_records) > 1 );
	    if ( my $ptr = ($ip->ptr_records)[0] ){
		$ptr->update({ptrdname=>$self->get_label})
		    if ( $ptr->ptrdname ne $self->get_label );
	    }
	}
    }
    1;
}

##################################################################

=head2 delete - Override delete method

    * Removes any matching CNAMEs and MX records

  Arguments:
    None
  Returns:
    See parent class
  Examples:
    $rr->delete();

=cut

sub delete {
    my $self = shift;
    $self->isa_object_method('delete');
    my @cnames = RRCNAME->search(cname=>$self->get_label);
    my @mxs = RRMX->search(exchange=>$self->get_label);
    foreach my $o ( @cnames, @mxs ){
	$o->delete();
    }
    return $self->SUPER::delete();
}

##################################################################

=head2 get_label - Override get_label method

    Returns the full Resource Record name

  Arguments:
    None
  Returns:
    string
  Examples:
    print $rr->get_label();

=cut

sub get_label {
    my $self = shift;
    $self->isa_object_method('get_label');
    my $name = ($self->name eq '@')? "" : $self->name;
    if ( $self->zone && ref($self->zone) ){
	if ( $name ){
	    return sprintf("%s.%s", $name, $self->zone->name);
	}else{
	    return $self->zone->name;
	}
    }else{
	return $name;
    }
}

##################################################################

=head2 as_text

    Returns text representation of this RR (owner) and all its 
    related records

  Arguments:
    None
  Returns:
    string
  Examples:
    print $rr->as_text();

=cut

sub as_text {
    my $self = shift;
    $self->isa_object_method('as_text');
    my $text = "";
    my @records;

    foreach my $record ( $self->sub_records ){
	$text .= $record->as_text;
	$text .= "\n";
    }

    return $text;
}

##################################################################

=head2 add_host - Add hostname and several other things
    
    Combine RR, RRADDR, RRCNAME, RRHINFO and DHCP scope creation

  Arguments:
    Hash with following keys:  (O=optional, R=required)
    name         (R) RR name
    zone         (R) Zone id, object or name
    subnet       (O) Ipblock id, object or address. Necessary if no address.
    address      (O) Ipblock id, object or address. Will get next 
                     available if not specified
    expiration   (O) Expiration date for RR
    aliases      (O) Comma-separated list of strings for CNAMEs
    ethernet     (O) MAC address string for DHCP host
    duid         (O) DUID for DHCPv6 host
    cpu          (O) CPU string for HINFO
    os           (O) OS string for HINFO
    text_records (O) Arrayref of strings for TXT records
    info         (O) Informational text
  Returns:
    RR object
  Examples:
    my $rr = RR->add_host(%args);

=cut

sub add_host {
    my ($class, %argv) = @_;

    foreach my $arg ( qw/name zone/ ){
	$class->throw_fatal("Missing required argument: $arg")
	    unless $argv{$arg};
    }

    my $subnet;
    if ( $argv{subnet} ){
	$subnet = Ipblock->objectify($argv{subnet});    
	$class->throw_user("Invalid subnet: $argv{subnet}") 
	    unless $subnet;
	$class->throw_user("$argv{subnet} is not a subnet!")
	    unless ( $subnet->status->name eq 'Subnet' );

	if ( $argv{address} ){
	    my $address = $argv{address};
	    my $prefix;
	    if ( Ipblock->matches_v4($address) ){
		$prefix = 32;
	    }elsif ( Ipblock->matches_v6($address) ){
		$prefix = 128;
	    }else{
		$class->throw_user("Address $address appears to be invalid");
	    }
	    if ( my $ipb = Ipblock->search(address=>$address, 
					   prefix=>$prefix)->first ){
		if ( $ipb->status->name ne 'Available' ){
		    if ($ipb->status->name eq 'Discovered') {
			my $discovered_overwrite = Netdot->config->get("USER_DISCOVERED_OVERWRITE");
			$class->throw_user("Address $address is not available")
			    unless ($discovered_overwrite);
		    } else {
			$class->throw_user("Address $address is not available");
		    }
		}
	    }

	    # make sure that the address is within
	    my $sip = $subnet->netaddr;
	    my $nip = Ipblock->netaddr(address=>$argv{address});
	    unless ( $nip->within($sip) ){
		$class->throw_user(sprintf("Invalid IP: %s for Subnet: %s", 
					   $argv{address}, $subnet->get_label));
	    }
	}else{
	    # Obtain next available address
	    my $ip_strategy = Netdot->config->get("IP_ALLOCATION_STRATEGY");
	    $argv{address} = $subnet->get_next_free(strategy=>$ip_strategy);
	}
    }

    if ( !$argv{address} && !$subnet ){
	$class->throw_user("Adding a host requires either a subnet or an IP address") 
    }
  
    # Convert to object if needed
    my $zone = Zone->objectify($argv{zone});
    $class->throw_user("Invalid zone: $argv{zone}") 
	unless $zone;
    
    if ( my $h = RR->search(name=>$argv{name}, zone=>$zone)->first ){
	my $v4version = 0;
	my $v6version = 0;
	foreach my $ar ( $h->a_records ) {
	    if ( $ar->ipblock->version == 4 ) {
		$v4version = 1;
	    }elsif ( $ar->ipblock->version == 6 ) {
		$v6version = 1;
	    }
	}
	if ( $v4version && $v6version ) {
	    $class->throw_user($h->get_label." is already taken");
	}    
    }

    # We want this to be atomic
    my $rr;
    Netdot::Model->do_transaction(
	sub{
	    my $rraddr = RR->insert({type       => 'A', # The RR class would do the right thing if it's v6
				     ipblock    => $argv{address}, # RRADDR will convert to object 
				     name       => $argv{name}, 
				     zone       => $zone,
				     expiration => $argv{expiration},
				     update_ptr => 1,
				     info       => $argv{info},
				    });
	    
	    $rr = $rraddr->rr;
	    
	    
	    # CNAMES
	    if ( $argv{aliases} ){
		my @aliases = split(/\s*,\s*/, $argv{aliases});
		map { $rr->add_alias($_) } @aliases;
	    }

	    # HINFO
	    if ( $argv{cpu} && $argv{os} ){
		my %hinfo = (rr  => $rr, 
			     type=> 'HINFO',
			     cpu => $argv{cpu},
			     os  => $argv{os});
		RR->insert(\%hinfo);
	    }

	    # RRTXT
	    if ( exists $argv{text_records} && ref($argv{text_records}) eq 'ARRAY' ){
		foreach my $txtdata ( @{$argv{text_records}} ){
		    RR->insert({rr      => $rr, 
				type    =>'TXT',
				txtdata => $txtdata,
			       });
		}
	    }

	    # DHCP
	    if ( $argv{ethernet} ){
		# Create host scope
		DhcpScope->insert({type      => 'host',
				   ipblock   => $rraddr->ipblock,
				   physaddr  => $argv{ethernet},
				  });
	    }elsif ( $argv{duid} ){
		# Create host scope
		DhcpScope->insert({type      => 'host',
				   ipblock   => $rraddr->ipblock,
				   duid      => $argv{duid},
				  });
	    }
	});
    return $rr;
}

############################################################################

=head2 validate_name - Name validation for unprivileged users
    
    This method is called from specific UI components that take
    RR name input from unpriviledged users.  The regular expression
    is a configuration item.
    
  Args: 
    RR name string
  Returns: 
    True, or throws exception if validation fails
  Examples:
    RR->validate_name($name);

=cut

sub validate_name {
    my ($self, $name) = @_;
    
    if ( my $regex = Netdot->config->get('DNS_NAME_USER_INPUT_REGEX') ){
	if ( $name eq '@' ){
	    # The zone apex is OK
	    return 1;
	}
	if ( $name =~ /$regex/ ){
	    $self->throw_user("Name $name contains characters not allowed in this context");
	}
    }
    1;
}


############################################################################

=head2 sub_records - Returns all subrecords pointing to this RR
    
  Args: 
    None
  Returns: 
    Array of subrecord objects
  Examples:
    my @subrecs = $rr->sub_records()

=cut

sub sub_records {
    my ($self) = @_;

    my @records;

    foreach my $m ( qw/a_records txt_records hinfo_records cnames ns_records 
                     mx_records ptr_records naptr_records srv_records ds_records/ ){
	push @records, $self->$m;
    }

    return @records;
}

############################################################################

=head2 add_alias - Add CNAME record pointing to this one
    
  Args: 
    String
  Returns: 
    new RRCNAME object
  Examples:
    $rr->add_alias('my_alias');

=cut

sub add_alias {
    my ($self, $alias) = @_;

    $logger->debug(sprintf("RR::add_alias(): alias: %s", $alias));

    # In case they included the domain part in the alias
    my $domain = $self->zone->name;
    $alias =~ s/\.$domain$//;
    if ( my $h = RR->search(name=>$alias, zone=>$self->zone)->first ){
	$self->throw_user("CNAME record: ".$h->get_label." already exists");
    }
    RR->insert({name  => $alias,
		zone  => $self->zone,
		type  => 'CNAME',
		cname => $self->get_label,
	       });
}


############################################################################
# PRIVATE METHODS
############################################################################


############################################################################
# _validate_args - Validate arguments to insert and update
#
#  Args: 
#    hashref
#  Returns: 
#    True, or throws exception if validation fails
#  Examples:
#    $class->_validate_args($argv);
#
sub _validate_args {
    my ($self, $argv) = @_;
    
    my $zone;
    if (ref($self)){
	$zone = $self->zone;
    }
    if ( defined $argv->{zone} ){
	if ( ref($argv->{zone}) ){
	    # We're being passed an object
	    $zone = $argv->{zone}
	}else{
	    if ( $argv->{zone} =~ /\D+/ ){
		$zone = Zone->search(name=>$argv->{zone})->first;
	    }else{
		$zone = Zone->retrieve($argv->{zone});
	    }
	}
    }
    if ( defined $argv->{name} ){
	# Convert to lowercase
	my $name = lc($argv->{name});

	# Remove whitespace
	$name =~ s/\s+//g;
	
	# Remove trailing dots, if any
	$name =~ s/\.$//;

	# Remove commas
	$name =~ s/,//;

	# Valid characters
	if ( $name =~ /[^A-Za-z0-9\.\-_@\*]/ ){
	    $self->throw_user("Invalid name: $name. Contains invalid characters");
	}

        if ( $self->config->get('ALLOW_UNDERSCORES_IN_DEVICE_NAMES') eq '0' ){
	    # Underscore only allowed at beginning of string or dotted section
	    if ( $name =~ /[^^.]_/ || $name =~ /_$/ ){
		$self->throw_user("Invalid name: $name. Invalid underscores");
	    }
	}

	# Name must not start or end with a dash
	if ( $name =~ /^\-/ || $name =~ /\-$/ ){
	    $self->throw_user("Invalid name: $name. Name must not start or end with a dash");
	}

	# Length restrictions (RFC 1035)
	my $fqdn = $name.".".$zone->name;
	if ( length($fqdn) > 255 ){
	    $self->throw_user("Invalid FQDN: $fqdn. Length exceeds 255 characters");
	}
	# labels (sections between dots) must not exceed 63 chars
	foreach my $label ( split(/\./, $fqdn) ){
	    unless ( length($label) >= 1 && length($label) < 64 ){
		$self->throw_user(sprintf("RR::validate_args(): '%s' has Invalid label: '%s'. ".
					  "Each label must be between 1 and 63 characters long", 
					  $fqdn, $label));
	    }
	}
	$argv->{name} = $name;
    }
    1;
}

=head1 AUTHOR

Carlos Vicente, C<< <cvicente at ns.uoregon.edu> >>

=head1 COPYRIGHT & LICENSE

Copyright 2015 University of Oregon, all rights reserved.

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

#Be sure to return 1
1;

