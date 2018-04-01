package Netdot::Model::DhcpScope;

use base 'Netdot::Model';
use warnings;
use strict;

my $logger = Netdot->log->get_logger('Netdot::Model::DHCP');

=head1 NAME

Netdot::Model::DhcpScope - DHCP scope Class

=head1 CLASS METHODS
=cut

############################################################################

=head2 search

  Argsuments: 
    Hash with search criteria
  Returns: 
    Array of DhcpScope objects or iterator (See Class::DBI)
  Examples:
    DhcpScope->search(key=>"value");
=cut

sub search {
    my ($class, @args) = @_;
    $class->isa_class_method('search');

    # Class::DBI::search() might include an extra 'options' hash ref
    # at the end.  In that case, we want to extract the 
    # field/value hash first.
    my $opts = @args % 2 ? pop @args : {}; 
    my %args = @args;

    if ( defined $args{type} ){
	if ( $args{type} =~ /\w+/ ){
	    if ( my $type = DhcpScopeType->search(name=>$args{type})->first ){
		$args{type} = $type->id;
	    }
	}
    }
    return $class->SUPER::search(%args, $opts);
}

############################################################################

=head2 insert - Insert new Scope

    Override base method to:
      - Objectify some arguments
      - Validate arguments
      - Assign name based on arguments
      - Inherit failover properties from global scope if inserting subnet scope
      - Insert given attributes
      - Assign default version on global scopes
      - Assign contained subnets to shared-network
 Argsuments: 
    Hashref with following keys (in addition to DhcpScope fields):
      active      - Whether the scope should be exported or not
      type        - DhcpScopeType name, id or object
      attributes  - A hash ref with attribute key/value pairs
      subnets     - Arrayref of Ipblock objects
  Returns: 
    DhcpScope object
  Examples:
    my $host = DhcpScope->insert({type      => 'host',
                                  ipblock   => $ip,
                                  physaddr  => $mac,
				  });
=cut

sub insert {
    my ($class, $argv) = @_;
    $class->isa_class_method('insert');
    $class->throw_fatal('DhcpScope::insert: Missing required parameters')
	unless ( defined $argv->{type} );

    # Make it active unless told otherwise
    $argv->{active} = 1 unless exists $argv->{active};

    my @shared_subnets = @{$argv->{subnets}} if $argv->{subnets};

    $class->_objectify_args($argv);
    $class->_assign_name($argv) unless $argv->{name};
    $class->_validate_args($argv);

    my $attributes = {};
    $attributes = delete $argv->{attributes} if exists $argv->{attributes};

    my $scope;
    if ( $scope = $class->search(name=>$argv->{name})->first ){
	$class->throw_user("DHCP scope ".$argv->{name}." already exists!");
    }else{
	$scope = $class->SUPER::insert($argv);
    }

    if ( $scope->type->name eq 'subnet' ){
	if ( $scope->container->version == 4 ){ 
	    # Add standard attributes
	    $attributes->{'option broadcast-address'} = $argv->{ipblock}->netaddr->broadcast->addr();
	    $attributes->{'option subnet-mask'}       = $argv->{ipblock}->netaddr->mask;

	    if ( $scope->container->enable_failover ){
		my $failover_peer = $scope->container->failover_peer || 'dhcp-peer';
		$scope->SUPER::update({enable_failover=>1, failover_peer=> $failover_peer});
	    }
	}
	if ( my $zone = $argv->{ipblock}->forward_zone ){
	    # Add the domain-name attribute
	    $attributes->{'option domain-name'} = $zone->name;
	}
    }elsif ( $scope->type->name eq 'shared-network' ){
	# Shared subnets need to point to the new shared-network scope 
	my $failoverstatus = 0;
	foreach my $s ( @shared_subnets ){
	    my $subnet_scope = $s->dhcp_scopes->first;
	    $subnet_scope->update({container=>$scope, 
				   ipblock=>$s});
	    if ( $subnet_scope->enable_failover == 1 ) {
		$failoverstatus = 1;
	    }
	}
	if ( $failoverstatus ){
	    my $failover_peer = $scope->container->failover_peer || 'dhcp-peer';
	    $scope->SUPER::update({enable_failover => 1, 
				   failover_peer   => $failover_peer});
	}
    }
    $scope->_update_attributes($attributes) if $attributes;
    return $scope;
}


############################################################################

=head2 get_containers

    This method returns all scopes which can contain other scopes.  
    Scope types that can contain other scopes are:
      global
      group
      pool
      shared-network

  Arguments:
    None
  Returns:
    Array of DhcpScope objects
  Example:
    DhcpScope->get_containers();

=cut

sub get_containers {
    my ($class) = @_;
    $class->isa_class_method('get_containers');

    my @res;

    my $q = "SELECT  dhcpscope.id
             FROM    dhcpscopetype, dhcpscope
             WHERE   dhcpscopetype.id=dhcpscope.type
                AND  (dhcpscopetype.name='global' OR
                     dhcpscopetype.name='group' OR
                     dhcpscopetype.name='pool' OR
                     dhcpscopetype.name='shared-network')
       ";

    my $dbh  = $class->db_Main();
    my $rows = $dbh->selectall_arrayref($q);

    foreach my $r ( @$rows ){
	my $id = $r->[0];
	if ( my $obj = DhcpScope->retrieve($id) ){
	    push @res, $obj;
	}
    }
    return @res;
}

=head1 INSTANCE METHODS
=cut

############################################################################

=head2 update 
    
    Override parent method to:
    - Objectify some arguments
    - Validate arguments
    - Deal with attributes

  Args: 
    Hashref
  Returns: 
    See Class::DBI
  Examples:
    $dhcp_scope->update(\%args);
=cut

sub update{
    my ($self, $argv) = @_;

    $self->_objectify_args($argv);
    $self->_validate_args($argv);

    my $attributes = delete $argv->{attributes} if defined $argv->{attributes};
    my @res = $self->SUPER::update($argv);

    $self->_update_attributes($attributes) if $attributes;

    return @res;
}

############################################################################

=head2 delete 
    
    Override parent method to:
    
    - Remove shared-network scope when deleting its last subnet
    
  Arguments: 
    None
  Returns: 
    True if successful
  Examples:
    $dhcp_scope->delete();

=cut

sub delete{
    my ($self, $argv) = @_;
    $self->isa_object_method('delete');
    my $class = ref($self);
    
    my $type = $self->type;
    my $shared_network;
    if ( $type && $type->name eq 'subnet' ){
	if ( my $container = $self->container ){
	    if ( $container->type && 
		 $container->type->name eq 'shared-network' ){
		$shared_network = $container;
	    }
	}
    }
    my @ret = $self->SUPER::delete();
    if ( $shared_network ){
	if ( scalar($shared_network->contained_scopes) == 0 ){
	    $shared_network->delete();
	}
    }

    return @ret;
}

############################################################################

=head2 print_to_file -  Print the config file as text (ISC DHCPD format)

  Args: 
    Hash with following keys:
    filename - (Optional)
  Returns: 
    True
  Examples:
    $scope->print_to_file();

=cut

sub print_to_file{
    my ($self, %argv) = @_;
    $self->isa_object_method('print_to_file');
    my $class = ref($self);
    my $filename;

    unless ( $self->active ){
	$logger->info(sprintf("DhcpScope::print_to_file: Scope %s is marked ".
			      "as not active. Aborting", $self->get_label));
	return;
    }
    
    my $start = time;
    my $dir = Netdot->config->get('DHCPD_EXPORT_DIR') 
	|| $self->throw_user('DHCPD_EXPORT_DIR not defined in config file!');
    
    unless ( $filename = $argv{filename} ){
	$filename = $self->export_file;
	unless ( $filename ){
	    $logger->warn('Export filename not defined for this global scope: '. $self->name.' Using scope name.');
	    $filename = $self->name;
	}
    }
    my $path = "$dir/$filename";
    my $fh = Netdot::Exporter->open_and_lock($path);
    
    my $data = $class->_get_all_data();

    if ( !exists $data->{$self->id} ){
	$self->throw_fatal("DHCPScope::print_to_file:: Scope id". $self->id. " not found!");
    }

    print $fh "###############################################################\n";
    print $fh "# Generated by Netdot (http://netdot.uoregon.edu)\n";
    print $fh "###############################################################\n\n";

    $class->_print($fh, $self->id, $data);

    print $fh "\n#### EOF ####\n";
    close($fh);

    my $end = time;
    $logger->info(sprintf("DHCPD Scope %s exported to %s, in %s", 
			  $self->name, $path, $class->sec2dhms($end-$start) ));

}


############################################################################

=head2 import_hosts
    
  Args: 
    text
    overwrite
  Returns: 
    Nothing
  Examples:
    $dhcp_scope->import_hosts(text=>$data);
=cut

sub import_hosts{
    my ($self, %argv) = @_;
    $self->isa_object_method('import_hosts');

    $self->throw_fatal("Missing required argument: text")
	unless $argv{text};
    
    my @lines = split $/, $argv{text};

    foreach my $line ( @lines ){
	my ($mac, $ip) = split /\s+/, $line;
	$mac =~ s/\s+//g;
	$ip  =~ s/\s+//g;
	$self->throw_user("Invalid line: $line")
	    unless ($mac && $ip);
	
	if ( $argv{overwrite} ){
	    if ( my $phys = PhysAddr->search(address=>$mac)->first ){
		foreach my $scope ( $phys->dhcp_hosts ){
		    $scope->delete();
		}
	    } 
	    if ( my $ipb = Ipblock->search(address=>$ip)->first ){
		foreach my $scope ( $ipb->dhcp_scopes ){
		    $scope->delete();
		}
	    } 
	}
    	DhcpScope->insert({
	    type      => 'host',
	    ipblock   => $ip,
	    physaddr  => $mac,
	    container => $self,
			  });
    }
}

############################################################################

=head2 get_global - Return the global scope where this scope belongs
    
  Args: 
    None
  Returns: 
    DhcpScope object
  Examples:
    $dhcp_scope->get_global();
=cut

sub get_global {
    my ($self, %argv) = @_;
    $self->isa_object_method('get_global');
    
    my $container = $self->container;

    # This does not guarantee that the result is of type "global"
    # but it's fast
    if ( !defined($container) ){
	return $self;
    }elsif ( ref($container) ){
	# Go recursive
	return $container->get_global();
    }elsif ( $container = DhcpScope->retrieve($container) ){
	# Why is this happening?
	$logger->debug("DhcpScope::get_global: Scope ".$self->get_label. " had to objectify container: ".$container);
	return $container->get_global();
    }else{
	$self->throw_fatal("DhcpScope::get_global: Scope ".$self->get_label. " has invalid container: ".$container);
    }
}

############################################################################
# Private methods
############################################################################

############################################################################

=head2 _objectify_args

    Convert following arguments into objects:
    - type
    - physaddr
    - ipblock
    
  Args: 
    hashref
  Returns: 
    True
  Examples:
    $class->_objectify_args($argv);

=cut

sub _objectify_args {
    my ($self, $argv) = @_;

    if ( $argv->{type} && !ref($argv->{type}) ){
	if ( $argv->{type} =~ /\D+/ ){
	    my $type = DhcpScopeType->search(name=>$argv->{type})->first;
	    $self->throw_user("DhcpScope::objectify_args: Unknown type: ".$argv->{type})
		unless $type;
	    $argv->{type} = $type;
	}elsif ( my $type = DhcpScopeType->retrieve($argv->{type}) ){
	    $argv->{type} = $type;
	}else{
	    $self->throw_user("Invalid type argument ".$argv->{type});
	}
    }
    
    if ( $argv->{physaddr} && !ref($argv->{physaddr}) ){
	# Could be an ID or an actual address
	my $phys;
	if ( $argv->{physaddr} !~ /\D/ ){
	    # It's all digits, so it must be an ID
	    $phys = PhysAddr->retrieve($argv->{physaddr});
	}else{
	    $phys = PhysAddr->find_or_create({address=>$argv->{physaddr}});
	}
	if ( $phys ){
	    $argv->{physaddr} = $phys;
	}else{
	    $self->throw_user("Could not find or create physical address".
			      " for given argument: ".$argv->{physaddr});
	}
    }

    if ( $argv->{container} && !ref($argv->{container}) ){
	my $container;
	if ( $argv->{container} =~ /\D+/ ){
	    if ( $container = DhcpScope->search(name=>$argv->{container})->first ){
		$argv->{container} = $container;
	    }
	}elsif ( $container = DhcpScope->retrieve($argv->{container}) ){
	    $argv->{container} = $container;
	}else{
	    $self->throw_user("Invalid container argument ".$argv->{container});
	}
    }

    if ( $argv->{ipblock} && !ref($argv->{ipblock}) ){
	if ( $argv->{ipblock} =~ /\D+/ ){
	    my $ipblock;
	    unless ( $ipblock = Ipblock->search(address=>$argv->{ipblock})->first ){
		$ipblock = Ipblock->insert({address=>$argv->{ipblock}});
		if ( $ipblock->is_address ){
		    $ipblock->update({status=>'Static'});
		}else{
		    $ipblock->update({status=>'Subnet'});
		}
	    }
	    $argv->{ipblock} = $ipblock;
	}elsif ( my $ipb = Ipblock->retrieve($argv->{ipblock}) ){
		$argv->{ipblock} = $ipb;
	}else{
	    $self->throw_user("Invalid ipblock argument ".$argv->{ipblock});
	}
    }
    1;
}

############################################################################

=head2 _validate_args

  Args: 
    hashref
  Returns: 
    True, or throws exception if validation fails
  Examples:
    $class->_validate_args($argv);

=cut

sub _validate_args {
    my ($self, $argv) = @_;
    
    my %fields;
    foreach my $field ( qw(name type version physaddr duid ipblock container) ){
	if ( ref($self) ){
	    $fields{$field} = $self->$field if $self->$field;
	}
	# Overrides current value with given argument
	$fields{$field} = $argv->{$field} if exists $argv->{$field};
    }

    my $name = $fields{name} || $self->throw_user("A scope name is required");

    $self->throw_user("$name: A scope type is required") unless $fields{type};
    my $type = $fields{type}->name;

    $self->throw_user("$name: Version field only applies to global scopes") 
	if ( $fields{version} && $type ne 'global' );

    if ( $fields{physaddr} && $fields{duid} ){
	    $self->throw_user("$name: Cannot use both physaddr and duid");
    }
    if ( $fields{physaddr} && $type ne 'host' ){
	$self->throw_user("$name: Cannot assign physical address ($fields{physaddr}) to a non-host scope");
    }
    if ( my $duid = $fields{duid} ){
	if ( $type ne 'host' ){
	    $self->throw_user("$name: Cannot assign DUID ($fields{duid}) to a non-host scope");
	}
	if ( $duid =~ /[^A-Fa-f0-9:]/ ){
	    $self->throw_user("$name: DUID should only contain hexadecimal digits and colons: $duid");
	}
	my $hexonly = $duid;
	$hexonly =~ s/://g; # Remove colons
	if ( length($hexonly) < 1 ){
	    $self->throw_user("$name: Invalid DUID (too short): '$duid'\n");
	}
	if ( length($hexonly) > 255 ){
	    $self->throw_user("$name: Invalid DUID (too long): '$duid'\n");
	}
    }
    if ( $fields{ipblock} ){
	my $ip_status = $fields{ipblock}->status->name;
	if ( ($ip_status eq 'Subnet') && $type ne 'subnet' ){
	    $self->throw_user("$name: Cannot assign a subnet to a non-subnet scope");
	}elsif ( ($ip_status eq 'Static') && $type ne 'host'  ){
	    $self->throw_user("$name: Cannot assign an IP address to a non-host scope");
	}
	if ( $type eq 'host' && $ip_status ne 'Static' ){
	    $self->throw_user("$name: IP in host declaration can only be Static");
	}
    }
    if ( $type eq 'host' ){
	if ( $fields{ipblock} ){
	    if ( $fields{ipblock}->version == 4 && !$fields{physaddr} ){
		$self->throw_user("$name: an IPv4 host scope requires an ethernet address");
	    }
	    if ( $fields{ipblock}->version == 6 && !$fields{duid} && !$fields{physaddr} ){
		$self->throw_user("$name: an IPv6 host scope requires a DUID or ethernet address");
	    }
	    # Is Subnet scope defined?
	    my $subnet = $fields{ipblock}->parent || 
		$self->throw_user("$name: $fields{ipblock} not within subnet");
	    my $subnet_scope;
	    unless ( $subnet_scope = ($subnet->dhcp_scopes)[0] ){
		$self->throw_user("$name: Subnet ".$subnet->get_label." not dhcp-enabled.");
	    }
	    # Make sure we assign to the correct global container if none passed
	    $argv->{container} = $subnet_scope->get_global 
		unless defined $argv->{container};
	    $fields{container} = $argv->{container};

	    # Check for mismatched versions
	    if ( $fields{container}->type eq 'global' && 
		 $fields{ipblock}->version != $fields{container}->version ){
		$self->throw_user("$name: IP version in host scope does not match version in global scope");
	    }
	}

	if ( $fields{physaddr} ){
	    if ( my @scopes = DhcpScope->search(physaddr=>$fields{physaddr}) ){
		if ( my $subnet = $fields{ipblock}->parent ){
		    foreach my $s ( @scopes ){
			next if ( ref($self) && $s->id == $self->id );
			if ( $s->ipblock && (my $osubnet = $s->ipblock->parent) ){
			    if ( $osubnet->id == $subnet->id ){
				$self->throw_user("$name: Duplicate MAC address in this subnet: ".
						  $fields{physaddr}->address);
			    }
			}
		    }
		}
	    }
	}
	if ( $fields{duid} ){
	    if ( my @scopes = DhcpScope->search(duid=>$fields{duid}) ){
		if ( my $subnet = $fields{ipblock}->parent ){
		    foreach my $s ( @scopes ){
			next if ( ref($self) && $s->id == $self->id );
			if ( $s->ipblock && (my $osubnet = $s->ipblock->parent) ){
			    if ( $osubnet->id == $subnet->id ){
				$self->throw_user("$name: Duplicate DUID in this subnet: ".
						  $fields{duid});
			    }
			}
		    }
		}
	    }
	}

    }elsif ( $type eq 'subnet' ){

	$self->throw_user("$name: Subnet IP block not defined")
	    unless $fields{ipblock};

	$self->throw_user("$name: Subnet scopes require a container") 
	    unless $fields{container};

	if ( $fields{container}->type->name eq 'global' && 
	     $fields{ipblock}->version != $fields{container}->version ){
	    $self->throw_user("$name: IP version in subnet scope does not match IP version in container");
	}
    }elsif ( $type eq 'global' ){
	$argv->{version} = $fields{version} || 4;
	if ( $argv->{version} != 4 && $argv->{version} != 6 ){
	    $self->throw_user("$name: Invalid IP version: $fields{version}");
	}
    }
    if ( $fields{container} ){
	my $ctype = $fields{container}->type->name;
	$self->throw_user("$name: container scope type not defined")
	    unless defined $ctype;

	if ( $type eq 'global' ){
	    $self->throw_user("$name: a global scope cannot exist within another scope");
	}
	if ( $type eq 'host' && !($ctype eq 'global' || $ctype eq 'group') ){
	    $self->throw_user("$name: a host scope can only exist within a global or group scope");
	}
	if ( $type eq 'group' && $ctype ne 'global' ){
	    $self->throw_user("$name: a group scope can only exist within a global scope");
	}
	if ( $type eq 'subnet' && !($ctype eq 'global' || $ctype eq 'shared-network') ){
	    $self->throw_user("$name: a subnet scope can only exist within a global or shared-network scope");
	}
	if ( $type eq 'shared-network' && $ctype ne 'global' ){
	    $self->throw_user("$name: a shared-network scope can only exist within a global scope");
	}
	if ( $type eq 'pool' && !($ctype eq 'subnet' || $ctype eq 'shared-network') ){
	    $self->throw_user("$name: a pool scope can only exist within a subnet or shared-network scope");
	}
	if ( ($type eq 'class' || $type eq 'subclass') && $ctype ne 'global' ){
	    $self->throw_user("$name: a class or subclass scope can only exist within a global scope");
	}
    }elsif ( $type ne 'global' && $type ne 'template' ){
	$self->throw_user("$name: A container scope is required except for global and template scopes");
    }

    1;
}

############################################################################
# _print - Generate text file with scope definitions
#
# Arguments: 
#   fh     - File handle
#   id     - Scope id
#   data   - Data hash from get_all_data method
#   indent - Indent space
#
sub _print {
    my ($class, $fh, $id, $data, $indent) = @_;
    
    $indent ||= "";
    my $pindent = $indent;

    if ( !defined $fh ){
	$class->throw_fatal("Missing file handle");
    }

    if ( !defined $id ){
	$class->throw_fatal("Scope id missing");
    }

    if ( !defined $data || ref($data) ne 'HASH' ){
	$class->throw_fatal("Data missing or invalid");
    }

    unless ( $data->{$id}->{active} ){
	$logger->debug(sprintf("DhcpScope::print_to_file: Scope %d is marked ".
                               "as not active. Aborting", $id));
	return;
    }

    my $type;
    unless ( $type = $data->{$id}->{type} ){
	$class->throw_fatal("Scope id $id missing type");
    }

    if ( $type ne 'global' && $type ne 'template' ){
	my $st   = $data->{$id}->{statement};
	my $name = $data->{$id}->{name};
	if ( $type eq 'class' ){
	    # DHCPD requires double quotes
	    $name = "\"$name\"" unless $name =~ /"/;
	}
	print $fh $indent."$st $name {\n";
	$indent .= " " x 4;
    }
    
    # Print free-form text
    if ( $data->{$id}->{text} ){
 	chomp (my $text = $data->{$id}->{text});
 	$text =~ s/\n/\n$indent/g  ;
 	print $fh $indent.$text, "\n" ;
    }
    
    # Print attributes
    my %quoted_attrs = (
	'filename' => 1,
	'domain-name' => 1,
	);
    foreach my $attr_id ( sort { $data->{$id}->{attrs}->{$a}->{name} cmp 
				     $data->{$id}->{attrs}->{$b}->{name} }
			  keys %{$data->{$id}->{attrs}} ){

	my $name   = $data->{$id}->{attrs}->{$attr_id}->{name};
	my $code   = $data->{$id}->{attrs}->{$attr_id}->{code};
	my $format = $data->{$id}->{attrs}->{$attr_id}->{format};
	my $value  = $data->{$id}->{attrs}->{$attr_id}->{value};
	print $fh $indent.$name;
	if ( defined $value ) {
	    if ( (defined $format && ($format eq 'text' || $format eq 'string')) ||
		exists($quoted_attrs{$name}) ){
		# DHCPD requires double quotes for these
		$value = "\"$value\"" unless $value =~ /"/;
	    }
	    print $fh " $value";
	}
	elsif ( $type eq 'global' && 
		defined $code && defined $format ){
	    # Assume that user is trying to define a new option
	    print $fh " code $code = $format";
	}
	print $fh ";\n";
    }
    # Print "inherited" attributes from used templates
    if ( defined $data->{$id}->{templates} ){
	foreach my $template_id ( @{$data->{$id}->{templates}} ){
	    $class->_print($fh, $template_id, $data, $indent);
	}
    }

    # Create pools for subnets with dynamic addresses
    if ( $type eq 'subnet' ){
	my $s   = DhcpScope->retrieve($id);

	my $failover_enabled = ($s->enable_failover && 
				$s->container->enable_failover)? 1 : 0;
	my $failover_peer = $s->failover_peer || 
	    $s->container->failover_peer;

	my $ipb = $s->ipblock;
	my @ranges = $ipb->get_dynamic_ranges();

	if ( @ranges ){
	    if ( $failover_enabled && $failover_peer ne ""){
		print $fh $indent."pool {\n";
		my $nindent = $indent . " " x 4;
		# This is a requirement of ISC DHCPD:
		print $fh $nindent."deny dynamic bootp clients;\n";
		print $fh $nindent."failover peer \"$failover_peer\";\n";
		foreach my $range ( @ranges ){
		    print $fh $nindent."range $range;\n";
		}
		print $fh $indent."}\n";
	    }else{
		foreach my $range ( @ranges ){
		    my $st = ( $ipb->version == 6 )? 'range6' : 'range';
		    print $fh $indent."$st $range;\n";
		}
	    }
	}
    }
    
    # Recurse for each child scope
    if ( defined $data->{$id}->{children} ){
	foreach my $child_id ( sort { $data->{$a}->{type} cmp $data->{$b}->{type} 
				      ||
				      $data->{$a}->{name} cmp $data->{$b}->{name} }
			       @{$data->{$id}->{children}} ){
	    next if $data->{$child_id}->{type} eq 'template';
	    $class->_print($fh, $child_id, $data, $indent);
	}
    }
    
    # Close scope definition
    if ( $type ne 'global' && $type ne 'template' ){
	$indent = $pindent;
	print $fh $indent."}\n";
    }
    
}

############################################################################
# _get_all_data - Build a hash with all necessary information to build DHCPD config
# 
# Arguments:
#   None
# Returns:
#   Hash ref
# Example:
#   DhcpScope->_get_all_data();
#
sub _get_all_data {
    my ($class) = @_;

    my %data;

    $logger->debug("DhcpScope::_get_all_data: Querying database");

    my $q = "SELECT          dhcpscope.id, dhcpscope.name, dhcpscope.active, dhcpscope.text, 
                             dhcpscopetype.name, dhcpscope.container,
                             dhcpattr.id, dhcpattrname.name, dhcpattr.value, dhcpattrname.code, dhcpattrname.format,
                             physaddr.address, ipblock.address, ipblock.version, dhcpscope.duid, dhcpscope.version
             FROM            dhcpscopetype, dhcpscope
             LEFT OUTER JOIN physaddr ON dhcpscope.physaddr=physaddr.id
             LEFT OUTER JOIN ipblock  ON dhcpscope.ipblock=ipblock.id
             LEFT OUTER JOIN (dhcpattr CROSS JOIN dhcpattrname) ON 
                             dhcpattr.scope=dhcpscope.id AND dhcpattr.name=dhcpattrname.id
             WHERE           dhcpscopetype.id=dhcpscope.type
       ";

    my $dbh  = $class->db_Main();
    my $rows = $dbh->selectall_arrayref($q);

    $logger->debug("DhcpScope::_get_all_data: Building data structure");

    foreach my $r ( @$rows ){
	my ($scope_id, $scope_name, $scope_active, $scope_text, 
	    $scope_type, $scope_container, 
	    $attr_id, $attr_name, $attr_value, $attr_code, $attr_format,
	    $mac, $ip, $ipversion, $scope_duid, $scope_version) = @$r;
	$data{$scope_id}{name}      = $scope_name;
	$data{$scope_id}{type}      = $scope_type;
	$data{$scope_id}{active}    = $scope_active;
	$data{$scope_id}{container} = $scope_container;
	$data{$scope_id}{text}      = $scope_text;
	$data{$scope_id}{duid}      = $scope_duid;
	$data{$scope_id}{version}   = $scope_version;
	if ( $scope_type eq 'subnet' && $ipversion == 6 ){
	    $data{$scope_id}{statement} = 'subnet6';
	}else{
	    $data{$scope_id}{statement} = $scope_type;
	}
	if ( $attr_id ){
	    $data{$scope_id}{attrs}{$attr_id}{name}   = $attr_name;
	    $data{$scope_id}{attrs}{$attr_id}{code}   = $attr_code   if $attr_code;
	    $data{$scope_id}{attrs}{$attr_id}{format} = $attr_format if $attr_format;
	    $data{$scope_id}{attrs}{$attr_id}{value}  = $attr_value  if $attr_value;
	}
	if ( $scope_type eq 'host' ){
	    if ( $scope_duid ){
		$data{$scope_id}{attrs}{'client-id'}{name}  = 'host-identifier option dhcp6.client-id';
		$data{$scope_id}{attrs}{'client-id'}{value} = $scope_duid;
	    }elsif ( $mac ){
		$data{$scope_id}{attrs}{'hardware ethernet'}{name}  = 'hardware ethernet';
		$data{$scope_id}{attrs}{'hardware ethernet'}{value} = PhysAddr->dhcpd_address($mac);
	    }else{
		# Without DUID or MAC, this would be invalid
		next;
	    }
	    if ( $ip ){
		if ( $ipversion == 6 ){
		    my $addr = Ipblock->int2ip($ip, $ipversion);
		    $data{$scope_id}{attrs}{'fixed-address6'}{name}  = 'fixed-address6';
		    $data{$scope_id}{attrs}{'fixed-address6'}{value} = $addr;
		    my $addr_full = NetAddr::IP->new6($addr)->full();
		    $addr_full =~ s/\:+/-/g;
		    $data{$scope_id}{name} = $addr_full;
		}else{
		    $data{$scope_id}{attrs}{'fixed-address'}{name}  = 'fixed-address';
		    $data{$scope_id}{attrs}{'fixed-address'}{value} = Ipblock->int2ip($ip, $ipversion);
		}
	    }
	}
    }

    # Make children lists
    foreach my $id ( keys %data ){
	if ( my $parent = $data{$id}{container} ){
	    push @{$data{$parent}{children}}, $id if defined $data{$parent} ;
	}
    }

    # add  templates
    my $q2 = "SELECT scope, template FROM dhcpscopeuse";
    my $rows2  = $dbh->selectall_arrayref($q2);

    foreach my $r2 ( @$rows2 ){
	my ($id, $template) = @$r2;
	push @{$data{$id}{templates}}, $template if defined $data{$template};
    }

    return \%data;
}

############################################################################
# Assign scope name based on type and other values
sub _assign_name {
    my ($class, $argv) = @_;
    $class->isa_class_method('_assign_name');

    unless ( $argv->{type} ){
	$class->throw_fatal("DhcpScope::_assign_name: Missing required argument: type")
    }

    my $name;
    if ( $argv->{type}->name eq 'host' ){
	# Try to find a unique name for this scope
	if ( $argv->{ipblock} ){
	    $name = $argv->{ipblock}->full_address;
	}elsif ( $argv->{physaddr} ){
	    $name = $argv->{physaddr}->address;
	}elsif ( $argv->{duid} ){
	    $name = $argv->{duid};
	}
	$name =~ s/:/-/g; 

    }elsif ( $argv->{type}->name eq 'subnet' ){
	$class->throw_fatal("DhcpScope::_assign_name: Missing ipblock object")
	    unless $argv->{ipblock};
	if ( $argv->{ipblock}->version == 6 ){
	    $name = $argv->{ipblock}->cidr;
	}else{
	    $name = $argv->{ipblock}->address." netmask ".$argv->{ipblock}->netaddr->mask;
	}

    }elsif ( $argv->{type}->name eq 'shared-network' ){
	$class->throw_fatal("DhcpScope::_assign_name: Missing subnet list")
	    unless $argv->{subnets};
	my $subnets = delete $argv->{subnets};
	$name = join('_', (map { $_->address } sort { $a->address_numeric <=> $b->address_numeric } @$subnets));

    }else{
	$class->throw_fatal("DhcpScope::_assign_name: Don't know how to assign name for type: ".
			   $argv->{type}->name);
    }
    $argv->{name} = $name;
}

############################################################################
# Insert or update attributes
sub _update_attributes {
    my ($self, $attributes) = @_;
    while ( my($key, $val) = each %$attributes ){
	my $attr;
	my %args = (name=>$key, scope=>$self->id);
	my $str = $key;
	$str .= ": $val" if $val;
	if ( $attr = DhcpAttr->search(%args)->first ){
	    $logger->debug("DhcpScope::_update_attributes: ".$self->get_label.": Updating DhcpAttr $str");
	    $args{value} = $val;
	    $attr->update(\%args);
	}else{
	    $logger->debug("DhcpScope::_update_attributes: ".$self->get_label.": Inserting DhcpAttr $str");
	    $args{value} = $val;
	    DhcpAttr->insert(\%args);
	}
    }
    1;
}

=head1 AUTHOR

Carlos Vicente, C<< <cvicente at ns.uoregon.edu> >>

=head1 COPYRIGHT & LICENSE

Copyright 2012 University of Oregon, all rights reserved.

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

