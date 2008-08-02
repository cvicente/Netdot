package Netdot::Config;

use Carp;
use File::Spec::Functions qw( catpath splitpath rel2abs );

my %config;

my $default_config_dir = "<<Make:PREFIX>>/etc";
my $alt_config_dir     = catpath( ( splitpath( rel2abs $0 ) )[ 0, 1 ] ) . "../etc";

#Be sure to return 1
1;


=head1 NAME

Netdot::Config 

=head1 SYNOPSIS

Manage Netdot Configuration info

=head1 METHODS

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
	croak "No suitable config directory found!\n";
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

