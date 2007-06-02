package Netdot::Config;

use Carp;

my %config;

my $default_config_dir = "<<Make:PREFIX>>/etc";

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
    $self->{'_config_dir'} = $argv{config_dir} || $default_config_dir;
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
    my ($self, $dir) = @_;
    my %config;
    my @files;
    push @files, $self->{'_config_dir'} .'/Default.conf';
    push @files, $self->{'_config_dir'} .'/Site.conf'
	if ( -e $self->{'_config_dir'}.'/Site.conf' );
    foreach my $file ( @files ){
	my $config_href = do $file or die "Can't read config file: $file: ", $@ || $!;
	foreach my $key ( %$config_href ) {
	    $config{$key} = $config_href->{$key};
	}
    }
    return %config;
}

