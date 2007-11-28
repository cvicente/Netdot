#!/usr/bin/perl -w

# $Id: make_dev_matrix.pl,v 1.7 2007/11/27 02:59:18 jeneric Exp $

$DevMatrix = '../DeviceMatrix.txt';
$DevHTML   = 'DeviceMatrix.html';
$DevPNG    = 'DeviceMatrix.png';
$Attributes= {};

# Parse Data File
$matrix = parse_data($DevMatrix);

# Graph it for fun
eval "use GraphViz::Data::Structure;";
if ($@) {
    print "GraphViz::Data::Structure not installed. $@\n";
} else {
    my %graph = ();
    foreach my $vendor (sort sort_nocase keys %$matrix){
        $graph{$vendor} = {};
        foreach my $family  (sort sort_nocase keys %{$matrix->{$vendor}->{families}} ){
            my @models;
            foreach my $mod (keys %{$matrix->{$vendor}->{families}->{$family}->{models}}){
                push(@models,split(/\s*,\s*/,$mod));
            }
            if (scalar @models){
                $graph{$vendor}->{$family}=\@models;
            } else {
                $graph{$vendor}->{$family}=[];
            }
            
        }
    }
    my $now = scalar localtime;
    my $gvds = GraphViz::Data::Structure->new(\%graph,Orientation=>'vertical',
        Colors=> 'Deep',
        graph => {label=>"SNMP::Info and Netdisco Supported Devices \n $now",'fontpath'=>'/usr/local/netdisco','fontname'=>'lucon',concentrate=>'true','overlap'=>'false',spline=>'true',bgcolor=>'wheat'},
        node  => {fontname=>'lucon'},
        );
    $gvds->graph()->as_png($DevPNG);
}

open (HTML, "> $DevHTML") or die "Can't open $DevHTML. $!\n";
$old_fh = select(HTML);
&html_head;
print_vendors($matrix);
foreach my $vendor (sort sort_nocase keys %$matrix){
    print "<A NAME=\"$vendor\"><SPAN CLASS=\"vendor\"><B>$vendor</B></SPAN></A>\n";
    print "<DL>\n";

    my $vendor_defaults = $matrix->{$vendor}->{defaults};
    print_notes($vendor_defaults,1);

    my $families = $matrix->{$vendor}->{families};
    foreach my $family (sort sort_nocase keys %$families ) {
        print "<DT>$family Family\n";

        my $family_defaults = $families->{$family}->{defaults};
        print_notes($family_defaults,2);

        my $models = $families->{$family}->{models};
        foreach my $model (sort sort_nocase keys %$models ){
            my $model_defaults = $models->{$model}->{defaults};
            print "<DD>$model\n";
            print "<DL>\n";
            print_notes($model_defaults,3);

            print "<DT><DD><TABLE BORDER=1>\n";
            print_headers();
            print "<TR>\n";
            foreach my $a (sort sort_nocase keys %$Attributes) {
                my $val;
                next if $a eq 'note';
                $val = ['-'];
                $class = 'none';
                if (defined $model_defaults->{$a}) {
                    $val = $model_defaults->{$a};
                    $class = 'model';
                } elsif (defined $family_defaults->{$a}){
                    $val = $family_defaults->{$a};
                    $class = 'family';
                } elsif (defined $vendor_defaults->{$a}){
                    $val = $vendor_defaults->{$a};
                    $class = 'vendor';
                } 
                print "  <TD CLASS='$class'>",join("<BR>\n",@$val),"</TD>\n";
            }
            print "</TR></TABLE>\n";
            print "</DL>\n";
        }
    }
    print "</DL>\n";
}


&html_tail;

select ($old_fh);
close (HTML) or die "Can't write $DevHTML. $!\n";

# Data Structures

# Matrix =
#   ( vendor => { families  => { family => family_hash },
#                  defaults => { cmd    => [values]    },
#               }
#   )

# Family Hash
#   ( models   => { model => model_hash },
#     defaults => { cmd   => [values]   }
#   )

# Model Hash
#   ( defaults => { cmd => [values] } )
sub parse_data {
    my $file = shift;
    my %ignore = map { $_ => 1  }  @_;
    my $Matrix;

    my @Lines;
    open (DM, "< $file") or die "Can't open $file. $!\n";
    {
        @Lines = <DM>;
    }
    close (DM);

    my ($device,$family,$vendor,$class);
    foreach my $line (@Lines){
        chomp($line);
        # Comments
        $line =~ s/#.*//;

        # Blank Lines
        next if $line =~ /^\s*$/;

        # Trim whitespace
        $line =~ s/^\s+//;
        $line =~ s/\s+$//;

        my ($cmd,$value);
        if ($line =~ /^([a-z-_]+)\s*:\s*(.*)$/) {
            $cmd = $1;  $value = $2; 
        } else {
            print "What do i do with this line : $line \n";
            next;
        }

        if (exists $ignore{$cmd}){
            print "Ignoring $cmd\n";
        }
        # Set Class {vendor,family,device}
        if ($cmd eq 'device-vendor'){
            $vendor = $value;
            $family = $model = undef;
            $Matrix->{$vendor} = {} unless defined $Matrix->{$vendor};
            $class = $Matrix->{$vendor};
            $class->{defaults}->{type}='vendor';
            next;
        }

        if ($cmd eq 'device-family'){
            $family = $value;
            $model = undef;
            print "$family has no vendor.\n" unless defined $vendor;
            $Matrix->{$vendor}->{families}->{$family} = {} 
                unless defined $Matrix->{$vendor}->{families}->{$family};
            $class = $Matrix->{$vendor}->{families}->{$family};
            $class->{defaults}->{type}='family';
            next;
        }   

        if ($cmd eq 'device') {
            $model = $value;
            print "$model has no family.\n" unless defined $family;
            print "$model has no vendor.\n" unless defined $vendor;
            $Matrix->{$vendor}->{families}->{$family}->{models}->{$model} = {} 
                unless defined $Matrix->{$vendor}->{families}->{$family}->{models}->{$model};
            $class = $Matrix->{$vendor}->{families}->{$family}->{models}->{$model};
            $class->{defaults}->{type}='device';
            next;
        }

        # Store attribute
        push (@{$class->{defaults}->{$cmd}} , $value);
        $Attributes->{$cmd}++;
    }

    return $Matrix;
}

sub sort_nocase {
    return lc($a) cmp lc($b);
}

sub print_notes {
    my $defaults = shift;
    my $level    = shift;
    my $notes    = $defaults->{note} || [];
    foreach my $note (@$notes){
        if ($note =~ s/^!//){
            $note = '<SPAN CLASS="note">' . $note . '</SPAN>';
        }
    }
    if (scalar @$notes){
        print "<DT>\n";
        my $print_note = join("\n<LI>",@$notes);
        print "<UL TYPE='square'><LI>$print_note</UL>\n";
    }
}

sub print_vendors {
    my $matrix=shift;
    print "<h1>Device Vendors</h1>\n";
    foreach my $vendor (sort sort_nocase keys %$matrix){
        print "[<A HREF=\"#$vendor\">$vendor</A>]\n";
    }
    print "<HR>\n";
}

sub html_head {
    print <<"end_head";
<HTML>
<HEAD>
<TITLE>SNMP::Info - Device Compatibility Matrix</TITLE>
<STYLE TYPE="text/css" MEDIA="screen">
<!--
    BODY    { font-family:arial,helvetica,sans-serif; font-size:12pt; }
    TD      { font-family:arial,helvetica,sans-serif; font-size:10pt; }
    TH      { font-family:arial,helvetica,sans-serif; font-size:10pt; background:#F0F0F0; }
    H1      { font-family:arial,helvetica,sans-serif; font-size:14pt; }
    .vendor { font-size:12pt; color:#777777; }
    .family { font-size:12pt; color:blue; }
    .model  { font-size:12pt; color:red; }
    .note   { color:red; } 
//-->
</STYLE>
</HEAD>
<BODY>
<h1>SNMP::Info - Device Compatibility Matrix</h1>
<P>
end_head
}

sub html_tail {
    print <<'end_tail';
<HR>
<h1>Color Key</h1>
[<SPAN CLASS="model">Model Attribute</SPAN>]
[<SPAN CLASS="family">Family Attribute</SPAN>]
[<SPAN CLASS="vendor">Vendor Attribute</SPAN>]
<h1>Attribute Key</h1>
A value of <B>-</B> signifies the information is not specified and can
be assumed working.
<TABLE BORDER=1>
<TR>
    <TD>Arpnip</TD>
    <TD>Ability to collect ARP tables for MAC to IP translation.</TD>
</TR>
<TR>
    <TD>CDP</TD>
    <TD>Cisco Discovery Protocol usable.
        <UL>
            <LI><tt>Yes</tt> - Has CDP information through CISCO-CDP-MIB
            <LI><tt>Proprietary</tt> means the device has its own L2 Discovery Protocol.
        </UL>
    </TD>
</TR>
<TR>
    <TD>Class</TD>
    <TD>SNMP::Info Class the the device currently uses.  Devices using more generic
        interfaces like <tt>Layer2</tt> or <tt>Layer3</tt> may eventually get their
        own subclass.
    </TD>
</TR>
<TR>
    <TD>Duplex</TD>
    <TD>Ability to cull duplex settings from device.<BR>
        <UL>
            <LI><tt>no</tt> - Can't recover current or admin setting.
            <LI><tt>link</tt> - Can get current setting only.
            <LI><tt>both</tt> - Can get admin and link setting.
            <LI><tt>write</tt> - Can get admin and link setting and perform sets.
        </UL>
    </TD>
</TR>
<TR>
    <TD>Macsuck</TD>
    <TD>Ability to get CAM tables for MAC to switch port mapping.<BR>
        <UL>
            <LI><TT>no</TT> - Have not found an SNMP method to get data yet.
            <LI><TT>yes</TT> - Can get through normal SWITCH-MIB method.
            <LI><TT>vlan</TT> - Have to re-connect to each VLAN and then fetch with normal
        method.
        </UL>
    </TD>
</TR>
<TR>
    <TD>Modules</TD>
    <TD>Ability to gather hardware module information.</TD>
</TR>
<TR>
    <TD>Portmac</TD>
    <TD>Whether the device will list the MAC address of the switch port on each
        switch port when doing a Macsuck.
    </TD>
</TR>
<TR>
    <TD>Ver</TD>
    <TD>SNMP Protocol Version the device has to use.</TD>
</TR>
<TR>
    <TD>Vlan</TD>
    <TD>Ability to get VLAN port assignments.<BR>
        <UL>
            <LI><TT>no</TT> - Have not found an SNMP method to get data yet.
            <LI><TT>yes</TT> - Can read information.
            <LI><TT>write</TT> - Can read and write (set).
        </UL>
    </TD>
</TR>
</TABLE>
</BODY>
</HTML>
end_tail
    
}

sub print_headers {
    print "<TR>\n";
    foreach my $a (sort sort_nocase keys %$Attributes) {
        next if $a eq 'note';
        print "  <TH>$a</TH>\n";
    }
    print "</TR>\n";
}
