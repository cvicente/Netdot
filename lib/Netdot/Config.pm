package Netdot::Config;

use Carp;
use File::Spec::Functions qw( catpath splitpath rel2abs );

my %config;

my $default_config_dir = "<<Make:PREFIX>>/etc";
my $alt_config_dir     = catpath( ( splitpath( rel2abs $0 ) )[ 0, 1 ], '' ) . "../etc";

#Be sure to return 1
1;

=head1 NAME

Netdot::Config 

=head1 SYNOPSIS

Manage Netdot Configuration info

=head1 METHODS

######################################################################

=head2 new - Class Constructor
    
    my $config = Netdot::Config->new(config_dir=>'/path/to/config_dir');
    
=cut

sub new {
    my ($proto, %argv) = @_;
    my $class = ref( $proto ) || $proto;
    my $self  = {};
    $self->{'_config_dir'} = $argv{config_dir};
    bless $self, $class;
    # Read config files
    %config = $self->_read_configs();
    
    wantarray ? ( $self, '' ) : $self;
}

######################################################################

=head2 get
    
    Get value of given configuration variable
    
=cut

sub get {
    my ($self, $key) = @_;
    croak "You need to specify the configuration item to retrieve" 
	unless $key;
    croak "Unknown configuration item: $key" 
	unless exists $config{$key};
    return $config{$key};
}

######################################################################
# We have two config files.  First one contains defaults
# and second one is site-specific (and optional)
######################################################################
sub _read_configs {
    my ($self) = @_;
    my %config;
    my @files;
    my $dir;
    if ( defined $self->{'_config_dir'} ){
	$dir = $self->{'_config_dir'};
    }elsif ( -d $default_config_dir ){
	$dir = $default_config_dir;
    }elsif ( -d $alt_config_dir ){
	$dir = $alt_config_dir;
    }else{
	croak "Netdot::Config: No suitable config directory found!\n";
    }
    push @files, $dir .'/Default.conf';
    push @files, $dir .'/Site.conf'
	if ( -e $dir .'/Site.conf' );
    foreach my $file ( @files ){
	my $config_href = do $file or croak "Can't read config file: $file: ", $@ || $!;
	foreach my $key ( %$config_href ) {
	    $config{$key} = $config_href->{$key};
	}
    }
    return %config;
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


