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

      - If zone key is not passed, name will be looked up assuming it might
        contain domain info.

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
    if ( (exists $argv{name}) && ($argv{name} =~ /\./)  && !exists $argv{zone} ){
	if ( my $zone = (Zone->search(name=>$argv{name}))[0] ){
	    my $name = $zone->name;
	    $argv{name} =~ s/\.$name//;
	    $argv{zone} = $zone->id;
	    return $class->SUPER::search(%argv);
	}else{
	    # Zone not found, just do normal search
	    return $class->SUPER::search(%argv);
	}
    }else{
	return $class->SUPER::search(%argv, $opts);
    }
    return;
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
    if ( (ref( $zone = $argv->{zone} ) =~ /Zone/)
	 || ( $zone = (Zone->search(id   =>$argv->{zone}))[0] )
	 || ( $zone = (Zone->search(name=>$argv->{zone}))[0] )
	){
    }else{
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
    delete $args{type};
    delete $args{name};
    delete $args{zone};
    delete $args{expiration};

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

=head1 INSTANCE METHODS
=cut

##################################################################
=head2 update

    Override base method to:
       - Add option to update related RRPTR if name changes
  Arguments:
    Hashref with key/value pairs, plus:
       update_ptr - (flag)
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
    my @cnames = RRCNAME->search(cname=>$self->get_label);

    my $update_ptr = 1; # On by default
    if ( defined $argv->{update_ptr} && $argv->{update_ptr} == 0 ){
	$update_ptr = 0;
	delete $argv->{update_ptr};
    }

    $self->_validate_args($argv);

    my @res = $self->SUPER::update($argv);

    if ( $update_ptr ){
	if ( my @arecords = $self->arecords ){
	    foreach my $rraddr ( @arecords ){
		my $ip = $rraddr->ipblock;
		next if ( scalar($ip->arecords) > 1 );
		if ( my $ptr = ($ip->ptr_records)[0] ){
		    $ptr->update({ptrdname=>$self->get_label})
			if ( $ptr->ptrdname ne $self->get_label );
		}
	    }
	}
    }

    # Update those CNAMEs if needed
    if ( $self->get_label ne $old_fqdn ){
	foreach my $cname ( @cnames ){
	    $cname->update({cname=>$self->get_label});
	}
    }

    return @res;
}

##################################################################
=head2 delete - Override delete method

    * Removes any matching CNAMEs

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
    my $class = ref($self);
    my @cnames = RRCNAME->search(cname=>$self->get_label);
    foreach my $cname ( @cnames ){
	$cname->rr->delete();
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
    Hash with following keys:
    address      (required) Ipblock id or object
    hostname     (required) RR name
    zone         (required) Zone id or object
    block        (required) subnet Ipblock object
    expiration   Expiration date for RR
    aliases      Array of strings for CNAMEs
    ethernet     MAC address string 
    cpu          cpu string for HINFO
    os           os string for HINFO
    text_records Array of strings for TXT records
  Returns:
    RR id
  Examples:
    print RR->add_host(%args);

=cut

sub add_host {
    my ($class, %argv) = @_;
    
    if (!($argv{address} && $argv{hostname} && $argv{zone} && $argv{block})) {
	$class->throw_fatal("Missing required arguments.");
    }
    
    # We want this to be atomic
    my $rr;
    Netdot::Model->do_transaction(
	sub{
	    my $rraddr = RR->insert({type       => 'A', # The RR class would do the right thing if it's v6
				     ipblock    => $argv{address}, 
				     name       => $argv{hostname}, 
				     zone       => $argv{zone},
				     expiration => $argv{expiration},
				     update_ptr => 1,
				    });
	    
	    $rr = $rraddr->rr;
	    
	    # CNAMES
	    if ( $argv{aliases} ){
		$logger->debug("RR::add_host: aliases passed");
		foreach my $alias ( @{$argv{aliases}} ){
		    $logger->debug("RR::add_host: Creating Alias $alias");
		    RR->insert({name  => $alias,
				zone  => $argv{zone},
				type  => 'CNAME',
				cname => $rr->get_label,
			       });
		}
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
		my $physaddr = PhysAddr->find_or_create({address=>$argv{ethernet}});
		
		# Create host scope
		my ($subnet, $global);
		unless ( $subnet = ($argv{block}->dhcp_scopes)[0] ){
		    $class->throw_user("Subnet ".$argv{block}->get_label." not dhcp-enabled (no Subnet scope found).");
		}
		$global = $subnet->get_global;
		my $host;
		if ( $host = DhcpScope->search(name=>$argv{address})->first ){
		    $class->throw_user("A DHCP scope for host $argv{address} already exists!");
		}else{
		    $host = DhcpScope->insert({type      => 'host',
					       ipblock   => $rraddr->ipblock,
					       physaddr  => $physaddr,
					       container => $global});
		}
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
	if ( $name =~ /$regex/ ){
	    $self->throw_user("Invalid name: $name. Name contains invalid characters");
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

    foreach my $m ( qw/arecords txt_records hinfo_records cnames ns_records 
                     mx_records ptr_records naptr_records srv_records ds_records/ ){
	push @records, $self->$m;
    }

    return @records;
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
	if ( !ref($argv->{zone}) ){
	    if ( $argv->{zone} =~ /\D+/ ){
		$zone = Zone->search(name=>$zone)->first;
	    }else{
		Zone->retrieve($argv->{zone});
	    }
	}
    }
    if ( defined $argv->{name} ){
	# Convert to lowercase
	my $name = lc($argv->{name});
	$argv->{name} = $name;

	# Remove whitespace
	$argv->{name} =~ s/\s+//g;
	
	# Remove trailing dots, if any
	$argv->{name} =~ s/\.$//;

	# Length restrictions
	unless ( length($name) >= 1 && length($name) < 64 ){
	    $self->throw_user("Invalid name: $name. Length must be between 1 and 63 characters");
	}

	# Valid characters
	if ( $name =~ /[^A-Za-z0-9\.\-_@]/ ){
	    $self->throw_user("Invalid name: $name. Contains invalid characters");
	}
	# Check that underscore only appear at beginning
	if ( $name =~ /.+_/ ){
	    $self->throw_user("Invalid name: $name. One underscore only allowed at beginning of string");
	}
	# Name must not start or end with a dash
	if ( $name =~ /^\-/ || $name =~ /\-$/ ){
	    $self->throw_user("Invalid name: $name. Name must not start or end with a dash");
	}
	if ( $zone ){
	    my $fqdn = $name.".".$zone->name;
	    if ( length($fqdn) > 255 ){
		$self->throw_user("Invalid FQDN: $fqdn. Length exceeds 255 characters");
	    }
	}
    }
    1;
}

=head1 AUTHOR

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

#Be sure to return 1
1;

