#!/usr/bin/perl -w

# Nathan Collins Wed May  4 22:38:22 PDT 2005

# "Enhanced" version of table-array.pl.  Adds support for
# accumulation.  Not sure how worthwhile this actually is generally,
# but saves a bit of time when it is needed.  Also, the code it
# generates is little prettier than v1 did.

# Probably braindead script to help convert tables into the list we
# pass to attribute_table.mhtml.  Generated code will still require
# some massaging but should be pretty close to what you're looking
# for.  


die "usage: $0 n m <file>\nto convert lines n..m of <file>\n" if ! (scalar(@ARGV) == 3);

my $html = `sed -ne '$ARGV[0],$ARGV[1]p' $ARGV[2]`;

print( "<%perl>\n",
       "my \@row = ();\n" 
       );


# Assume everything is in a table data element and that there is no
# nesting.  Might need to consider table headers and the like.
while ($html =~ m|<td[^>]*>(.*?)</td>|sg) {	
    #print $1,"\n";
    if (0) {
	print qq(push( \@field_headers, "$1" );\n);	# Assuming field headers are always simple.
    }else{
	my @lines = split(/\n/,$1);
	@lines = grep { $_ !~ /^\s*$/ } @lines;		# Delete empty lines.

	my $ac = "";
	if (@lines > 1) {
	    $ac = '$ac .= ';	# The string form of the accumulator code.
	}
	foreach (@lines) { 
	    if (/^%/) { 
		s/^%//;	# Un Mason escape embedded perl lines.
		s/^(\s*)printf/$1${ac}sprintf/;	# Accumulate prints.
	    }else{
		s/\'?<% (.*?) %>\'?/' . $1 . '/g;	# Un Mason escape variables/method calls.
		s/^(\s*)(.*)\s*$/$1$ac'$2';/;	# Trim whitespace, quote, and accumulate.
		s/''( *\.)?|(\. *)?''(;)/$3 if defined $3/eg;	# remove any extra quotes.
	    }
	    s/(\$ui->.*?\(.*)\)/$ac$1, returnAsVar=>1\)/;	# The returnAsVar argument needs to get added to all calls to $ui's methods.
	}

	
	my $code = join( "\n", @lines );	
        if (@lines > 1) {	# If there are multiple lines there are probably choices and/or accumulation.
	    $code = qq(\n&{sub{\n    my \$ac = "";\n).$code."\n    \$ac;\n}}";	# The anon sub will return $a.
	}else{
	    $code =~ s/^\s*(.*)\;$/$1/;	# A loan statement shouldn't have a trailing semicolon in a call to push, and doesn't need leading whitespace.
	}

	print( 'push( @row, ', 
	       $code,
	       " );\n"
	       );

    }
}

print( 'push( @rows, \@row );', "\n" );

print( "</%perl>\n",
       "\n",
       #'<& attribute_table.mhtml, field_headers=>\@field_headers, data=>\@cell_data &>'."\n"
       '<& data_table.mhtml, field_headers=>\@headers, data=>\@rows &>',
       "\n"
       );
	
