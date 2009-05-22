package Netdot::Model::DhcpScope;

use base 'Netdot::Model';
use warnings;
use strict;

my $logger = Netdot->log->get_logger('Netdot::Model');

=head1 NAME

Netdot::Model::DhcpScope - DHCP scope Class

=head1 SYNOPSIS


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
      - Assign DhcpScopeType based on given text or id
      - Inherit failover properties from global scope if inserting subnet scope
      - Insert given attributes

 Argsuments: 
    Hashref with following keys:
      name
      type        - DhcpScopeType name, id or object
      attributes  - A hash ref with attribute key/value pairs
  Returns: 
    DhcpScope object
  Examples:
    
=cut

sub insert {
    my ($class, $argv) = @_;
    $class->isa_class_method('insert');
    $class->throw_fatal('DhcpScope::insert: Missing required parameters')
	unless ( defined $argv->{name} && defined $argv->{type} );

    if ( $argv->{type} =~ /\D+/ ){
	my $type = DhcpScopeType->search(name=>$argv->{type})->first;
	$class->throw_user("DhcpScope::insert: Unknown type: $argv->{type}")
	    unless $type;
	$argv->{type} = $type;
    }
    my $attributes = delete $argv->{attributes} if defined $argv->{attributes};

    my $scope = $class->SUPER::insert($argv);

    if ( $scope->type->name eq 'subnet' ){
	if ( int($scope->container) && $scope->container->enable_failover ){
	    my $failover_peer = $scope->container->failover_peer || 'dhcp-peer';
	    $scope->update({enable_failover=>1, failover_peer=>'failover-peer'});
	}
    }
    
    if ( $attributes ){
	while ( my($key, $val) = each %$attributes ){
	    my $attr;
	    if ( !($attr = DhcpAttr->search(name=>$key, value=>$val, scope=>$scope->id)->first) ){
		$logger->debug("DhcpScope::insert: ".$scope->get_label.": Inserting DhcpAttr $key: $val");
		DhcpAttr->find_or_create({name=>$key, value=>$val, scope=>$scope->id});
	    }
	}
    }

    return $scope;
}

=head1 INSTANCE METHODS
=cut


############################################################################
=head2 print_to_file -  Print the config file as text

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

    $class->_print($fh, $self->id, $data);

    close($fh);

    my $end = time;
    $logger->info(sprintf("DHCPD Scope %s exported in %s", 
			  $self->name, $class->sec2dhms($end-$start) ));
}



############################################################################
# Private methods
############################################################################

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
    
    $indent ||= " ";
    my $pindent = $indent;

    if ( !defined $fh ){
	$class->throw_fatal("Missing file handle");
    }

    if ( !defined $id ){
	$class->throw_fatal("Scope id missing");
    }

    if ( !defined $data->{$id}->{type} ){
	$class->throw_fatal("Scope id $id missing type");
    }

    if ( $data->{$id}->{type} ne 'global' && $data->{$id}->{type} ne 'template' ){
	print $fh $indent.$data->{$id}->{type}." ".$data->{$id}->{name}." {\n";
	$indent .= " " x 4;
    }
    
    # Print free-form text
    print $fh $indent.$data->{$id}->{text}, "\n" if $data->{$id}->{text};
    
    # Print attributes
    foreach my $attr_id ( sort { $data->{$id}->{attrs}->{$a}->{name} cmp 
				     $data->{$id}->{attrs}->{$b}->{name} }
			  keys %{$data->{$id}->{attrs}} ){
	if ( $attr_id eq 'hardware ethernet' ){
	    my $addr = $data->{$id}->{attrs}->{$attr_id}->{value};
	    print $fh $indent."$attr_id ".PhysAddr->colon_address($addr).";\n";
	}elsif ( $attr_id eq 'fixed-address' ){
	    my $addr = $data->{$id}->{attrs}->{$attr_id}->{value};
	    print $fh $indent."$attr_id $addr;\n";
	}else{
	    my $name   = $data->{$id}->{attrs}->{$attr_id}->{name};
	    my $code   = $data->{$id}->{attrs}->{$attr_id}->{code};
	    my $format = $data->{$id}->{attrs}->{$attr_id}->{format};
	    my $value  = $data->{$id}->{attrs}->{$attr_id}->{value};
	    print $fh $indent.$name;
	    if ( defined $code && defined $format ){
		print $fh " $code = $format";
	    }elsif ( defined $value ) {
		print $fh " $value";
	    }
	    print $fh ";\n";
	}
    }
    
    # Print "inherited" attributes from used templates
    if ( defined $data->{$id}->{templates} ){
	foreach my $template_id ( @{$data->{$id}->{templates}} ){
	    $class->_print($fh, $template_id, $data, $indent);
	}
    }

    # Create pools for subnets with dynamic addresses
    if ( $data->{$id}->{type} eq 'subnet' ){
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
		    print $fh $indent."range $range;\n";
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
    if ( $data->{$id}->{type} ne 'global' && $data->{$id}->{type} ne 'template' ){
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

    my $q = "SELECT          dhcpscope.id, dhcpscope.name, dhcpscope.text, dhcpscopetype.name, dhcpscope.container,
                             dhcpattr.id, dhcpattrname.name, dhcpattr.value, dhcpattrname.code, dhcpattrname.format,
                             physaddr.address, ipblock.address, ipblock.version
             FROM            dhcpscopetype, dhcpscope
             LEFT OUTER JOIN physaddr ON dhcpscope.physaddr=physaddr.id
             LEFT OUTER JOIN ipblock  ON dhcpscope.ipblock=ipblock.id
             LEFT OUTER JOIN (dhcpattr, dhcpattrname) ON 
                             dhcpattr.scope=dhcpscope.id AND dhcpattr.name=dhcpattrname.id
             WHERE           dhcpscopetype.id=dhcpscope.type
       ";

    my $dbh  = $class->db_Main();
    my $rows = $dbh->selectall_arrayref($q);

    $logger->debug("DhcpScope::_get_all_data: Building data structure");

    foreach my $r ( @$rows ){
	my ($scope_id, $scope_name, $scope_text, $scope_type, $scope_container, 
	    $attr_id, $attr_name, $attr_value, $attr_code, $attr_format,
	    $mac, $ip, $ipversion) = @$r;
	$data{$scope_id}{name}      = $scope_name;
	$data{$scope_id}{type}      = $scope_type;
	$data{$scope_id}{container} = $scope_container;
	$data{$scope_id}{text}      = $scope_text;
	if ( $attr_id ){
	    $data{$scope_id}{attrs}{$attr_id}{name}      = $attr_name;
	    $data{$scope_id}{attrs}{$attr_id}{code}      = $attr_code   if $attr_code;
	    $data{$scope_id}{attrs}{$attr_id}{format}    = $attr_format if $attr_format;
	    $data{$scope_id}{attrs}{$attr_id}{value}     = $attr_value  if $attr_value;
	}
	if ( $scope_type eq 'host' ){
	    $data{$scope_id}{attrs}{'hardware ethernet'}{name}  = 'hardware ethernet';
	    $data{$scope_id}{attrs}{'hardware ethernet'}{value} = $mac if $mac;
	    $data{$scope_id}{attrs}{'fixed-address'}{name}      = 'fixed-address';
	    $data{$scope_id}{attrs}{'fixed-address'}{value}     = Ipblock->int2ip($ip, $ipversion) if $ip;
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

