#!<<Make:PERL>>

use lib "<<Make:LIB>>";
use Getopt::Long qw(:config no_ignore_case bundling);
use strict;
use Netdot::UI;

my $usage = <<EOF;
 usage: $0  -n|--name | -e|--entity |  -d|--dependencies | -s|--site

    
    -e, --entity                   report devices with no entity
    -d, --dependencies             report devices with no dependencies
    -s, --site                     report devices with no site
    -h, --help                     print help (this message)
    -m, --send_mail                                    
    
EOF
    
my $HELP    = 0;
my $ENTITY  = 0;
my $DEPS    = 0;
my $SITE    = 0;
my $DEBUG   = 0;
my $EMAIL   = 0;

# handle cmdline args
my $result = GetOptions( "e|entity"       => \$ENTITY,
			 "d|dependencies" => \$DEPS,
			 "s|site"         => \$SITE,
			 "h|help"         => \$HELP,
			 "m|send_mail"    => \$EMAIL,
			 );

if( ! $result ) {
    print $usage;
    die "Error: Problem with cmdline args\n";
}
if( $HELP ) {
    print $usage;
    exit;
}
unless ( $ENTITY || $DEPS || $SITE ){
    print $usage;
    die "Error: Must specify either -e, -d or -s\n";
}

# This will be reflected in the history tables
$ENV{REMOTE_USER} = "netdot";

my (@nameless, @lost, @orphans, @homeless, $output);

my $ui = Netdot::UI->new();

my $it = Device->retrieve_all;

while ( my $dev = $it->next ){

    unless ( $dev->name && $dev->name->name ){
	push @nameless, $dev;
	next;
    }
    if ( $ENTITY ){
	push @lost, $dev unless ( $dev->used_by  && $dev->used_by->id );
    }
    if ( $SITE ){
	push @homeless, $dev unless ( $dev->site && $dev->site->id );
    }
    if ( $DEPS ){
	my $found = 0;
	foreach my $int ( $dev->interfaces ){
	    if ($int->parents || $int->children) { $found = 1; last }
	}
	push @orphans, $dev unless $found;
    }
}



if ( @nameless ){
    $output .= sprintf("\nThe following devices have no name defined:\n");
    map { $output.= sprintf(" ID: %s\n", $_->id) } @nameless;
}

if ( @lost ){
    @lost = sort { $a->name->name cmp $b->name->name } @lost;
    $output .= sprintf("\nThe following devices have no Entity defined:\n");
    map { $output .= sprintf("  %s\n", $_->name->name) } @lost;
}

if ( @homeless ){
    @homeless = sort { $a->name->name cmp $b->name->name } @homeless;
    $output .= sprintf("\nThe following devices have no Site defined:\n");
    map { $output .= sprintf("  %s\n", $_->name->name) } @homeless;
}

if ( @orphans ){
    @orphans = sort { $a->name->name cmp $b->name->name } @orphans;
    $output .= sprintf("\nThe following devices have no dependencies defined:\n");
    map { $output .= sprintf(" %s\n", $_->name->name) } @orphans;
}

if ( $EMAIL && $output ){
    if ( ! $ui->send_mail(subject=>"Netdot Device Validation", body=>$output) ){
	die "Problem sending mail: ", $ui->error;
    }
}else{
    print STDOUT $output;
}
