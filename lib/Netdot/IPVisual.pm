package Netdot::IPVisual;

use base 'Netdot';
use bigint;
use warnings;
use strict;
use Data::Dumper;

=head1 NAME

    Netdot::IPVisual

##########################################################################################

=head2 create_tree

=cut 

sub create_tree{
	my ($class, $input_ids_ref, $C, $GD, $CC, $Chunk_Value, $n_addr_bits, $parent_addr_id, $return_lnk) = @_;
	$class->isa_class_method('create_tree');
	
	#The following variables are defined as "local" so that perl will use dynamic scoping
	#this way, functions called by create_tree will be able to see them
	local $create_tree::CHUNKSIZE = $C;
	local $create_tree::CURRENT_CHUNK = $CC;
	local $create_tree::CHUNK_VALUE = $Chunk_Value;
	local $create_tree::NUMBER_ADDR_BITS = $n_addr_bits; #needed because an address might not require 128 bits to express
	local $create_tree::PARENT_ADDR_ID = $parent_addr_id; #who is the father of this region!
	local $create_tree::GRAPHDIM = $GD;
	local @create_tree::input_ids = @$input_ids_ref;
	local @create_tree::input_addr = ();
	local @create_tree::input_sub = ();
	local @create_tree::ta = ();
	local @create_tree::sub = ();
	local $create_tree::RETURN_LINK = $return_lnk;
	
	foreach my $ip (@create_tree::input_ids){
        	push(@create_tree::input_sub, $ip->prefix);
        	push(@create_tree::input_addr, $ip->address_numeric);
	}

	#we need to fetch the sections of the address we are interested in.  This bit of code gets the 16 bit 
	#section of address, plus a value indicating how many of those 16 bits are signifigant (say we're looking
	#at a /20 subnet, but we're already "zoomed in" 18 bits, only 2 bits of that address would be signifgant
	for (my $i = 0; $i < scalar @create_tree::input_addr; $i++){
		my ($t, $s) = $class->ipv6_to_bin_and_sub($create_tree::input_addr[$i], $create_tree::input_sub[$i], $CC);
		if($s <= 0){
			return "Error: cannot display zero bits"; #there is a problem with the data, this shouldn't happen
		}
		push(@create_tree::ta, $t);
		push(@create_tree::sub, $s); 
	}
	#the tree is built recursively with calls to build_tree.  Each of these calls makes subsequent calls until
	#the desired depth (8) is reached.
	my @tree = (	$class->build_tree(0, 0, 8), 
			$class->build_tree(1, 0, 8),
			$class->build_tree(2, 0, 8),
			$class->build_tree(3, 0, 8));

	#once the tree structure is constructed, the HTML is computed.  For debugging, I suggest using the 
	#Data::Dumper library to print out @tree, it might give you some idea of where a problem is
	my $graphHTML = $class->build_graph(\@tree, 0, 0, 0);
	
	return $graphHTML;
}

##########################################################################################

=head2 build_tree

    Designed to build a quad tree of a specified depth, comparing 
    portions of addresses equal in bit length to that depth

=cut

sub build_tree{
	my ($class, $sector,$cdepth, $depth) = @_;
	$class->isa_class_method('build_tree');
	my @rtnvalues = ();
	my $c = 0;

	#here we check the address list and the bits included list.  See if we have any addresses that 
	#fit the current sector right now and add them to the return values
	for(my $i = 0; $i < scalar @create_tree::ta; $i++){
		if(($cdepth+1)*2 == $create_tree::sub[$i]-1 
		|| ($cdepth+1)*2 == $create_tree::sub[$i]){ #needed since it might be inbetween
			
			if (($create_tree::ta[$i] == $sector) 
			|| ($create_tree::sub[$i] % 2 == 0 
			&& ($create_tree::ta[$i]>>($create_tree::CHUNKSIZE - $create_tree::sub[$i]) == $sector))){
				
				#I'm putting the +0 here to make sure perl treats it as an integer
				push(@rtnvalues, $create_tree::input_ids[$i]->id + 0);
			}
		}
        }
	
	#If there is anything in the current sector that has been added to return values, we can return it
	#right now, everything below this sector will be included in the next graph when you click on it
	if(@rtnvalues){
		return \@rtnvalues;
	}

	#if we're still here, we have more sections to check.  That means more recursive calls to build_tree
	for(my $i=0; $i < scalar @create_tree::ta; $i++){

		#first we get the section of the address we are interested in
		my $b = $create_tree::ta[$i] >> ($create_tree::CHUNKSIZE - ($cdepth*2)-2);
 
               	if(($sector == $b)){
			$c = 1;
                        last;
		}
	}

	if($c){
		my $s0 = ($sector << 2) | 0;
		my $s1 = ($sector << 2) | 1;
		my $s2 = ($sector << 2) | 2;
		my $s3 = ($sector << 2) | 3;
       		@rtnvalues = ($class->build_tree($s0, $cdepth+1, $depth), 
			$class->build_tree($s1, $cdepth+1, $depth),
			$class->build_tree($s2, $cdepth+1, $depth),
			$class->build_tree($s3, $cdepth+1, $depth));
	}

	return \@rtnvalues;
}


##########################################################################################

=head2 build_graph

    takes a quad tree built with buildTree and creates the HTML to render it

=cut

sub build_graph{

	#$s is an array reference to the 4 sectors that will make up the current level
	#$cdepth is the current level depth
	my($class, $s, $cdepth, $prefix, $number_bits_prefix) = @_;
	$class->isa_class_method('build_graph');
	my @s = @{$s};

	#I was having a lot of trouble getting the divs to line up correctly.  They were overlapping
	#in a strange manner and it caused gaps in the sections of the graph (where the background
	#color of the table would show through, it was highly annoying).  Until I can figure out
	#why the div sections are not cascading correctly, I have the recursive calls return their
	#background color, so that it can be set in the table cell where they are to be placed.
	my @background_color = ("#FFFFFF","#FFFFFF","#FFFFFF","#FFFFFF");

	
	#I have different values for width and height because I was playing with different values
	#based on section number, again to try and fix the div cascading problem, they are set 
	#to the same value now.  This makes sense, as every section should be a square.
	my ($width, $height);
	$width = ($create_tree::GRAPHDIM/(2.0**($cdepth)));
	$height = ($create_tree::GRAPHDIM/(2.0**($cdepth)));


	#if there is nothing in @s, that means we have reached a leaf in the tree
	#and we can create a cell in the quad tree.
        if(scalar @s == 0){

		#first we need to know how many bits are required to exress the prefix address
		#so we'll know how much to shift by.
		my $addr_prefix_length = $create_tree::NUMBER_ADDR_BITS;
		my $chunk_val = $create_tree::CHUNK_VALUE;
		my $ipnumeric = $chunk_val | ($prefix << (128 - $create_tree::CURRENT_CHUNK - $number_bits_prefix));
	

		#with the hard work out of the way, we can now translate this block's address into something
		#more human readable, for nerdy values of "human"
		my $ipaddr = Ipblock->int2ip($ipnumeric, 6);
		my $bin_numeric = $ipnumeric->as_bin();
		my $len = length($bin_numeric)-2;
		my $total_prefix = $number_bits_prefix + $create_tree::CURRENT_CHUNK;
		my $CIDR_val = "$ipaddr/$total_prefix";
                
		#putting the DIV definition and code that should be run when the area is clicked in a string
		#to make it a bit more readable
		my $link_code = "
			<DIV style='{   width:$width; 
                                        height:$height; 
                                        overflow:hidden; 
                                        border-collapse:collapse; 
					background-color:#bbddbb;
					}'
					title=\"Zoom into $CIDR_val\"; 
					onclick=\"location.href='$create_tree::RETURN_LINK?new_addr=$ipaddr&new_prefix=$total_prefix&new_parent=$create_tree::PARENT_ADDR_ID';\"'
			";

                #now we need to return the background color for avaliable address space, and the html for the div
		#IF YOU WANT TO CHANGE THE COLOR OF THE AVALIABLE ADDRESS CELL (CURRENTLY GREEN) DO IT HERE
		return ("#bbddbb", $link_code);

        }
	
	#we need to iterate over all of the values @s
	#and see if they are arrayrefs (this means the sector we are currently looking at has subsectors)
	#or numbers (this means they are subnets)
	#I wrote this code awhile ago.  In reality we would never mix arrayrefs and numbers, but 
	#I finally got this library working and I don't feel like breaking anything

	my $is_container = 0;
	for(my $i = 0; $i< scalar @s; $i++){
		#If this is true then the sector we are looking at contains sub sections.  We must 
		#recursively call build_graph
		if(ref($s[$i]) eq 'ARRAY'){
			my $new_prefix = ($prefix << 2) | $i;
			($background_color[$i], $s[$i]) = $class->build_graph($s[$i], $cdepth+1, $new_prefix, $number_bits_prefix+2, $i);
		}
		
		#If this is true, then there is 1 or more address in  this section.
		elsif($s[$i]->isa('Math::BigInt') || $s[$i]->isa('INTEGER')){
			my @titles = ();
			my $return_link = $create_tree::RETURN_LINK."?input_addrs=@s";
			foreach my $t (@s){
				for(my $i = 0; $i < scalar @create_tree::ta; $i++){
					my $i6addr = Ipblock->int2ip($create_tree::input_addr[$i], 6);
					$i6addr .= "/".$create_tree::input_sub[$i];
					if($create_tree::input_ids[$i]->id + 0 == $t && (! grep($_ eq $i6addr, @titles))){
						push(@titles, $i6addr);
						if(Ipblock->retrieve(id=>$t) && 
						Ipblock->retrieve(id=>$t)->status){
							#this means its a container
							$is_container = 1;	
						}
					}
				}
			}
			my $color;
			my $title_action = "";
			if(scalar @s > 1){
				$color = "#ffcbff";
				#we also need to update the return_link to specify a chunk position
				$return_link .= "&prefix=".($create_tree::CURRENT_CHUNK + 16);
				$title_action = "Zoom in to view"; 
			}
			elsif($is_container){
				$color = "#ffee77";
				$title_action = "View children of";
			}
			else{
				$color = "#ff6666";
			}
			$s[$i] = $s[$i] = "<DIV style='{width:$width; height:$height; 
				overflow:hidden; border-collapse:collapse; background-color:$color;}' 
				onclick=\"location.href='$return_link';\" title='$title_action @titles'>&nbsp;</DIV>";
			
			return ($color, $s[$i]);
		}
	}

	#now we have values for each item in @s we can construct the table and return to the calling function
	my $o = qq[
	
	<table border=1 style="border-collapse:collapse; border-width:1px; border-spacing:0px; background-color: #FFFFFF" cellspacing=0 cellpadding=0>
	<tr>
        	<td cellpadding=0 style="background-color:$background_color[0]"> $s[0]</td>
       		<td cellpadding=0 style="background-color:$background_color[1]"> $s[1]</td>
	</tr>
        
	<tr>
		<td cellpadding=0 style="background-color:$background_color[2]">$s[2]</td>
		<td cellpadding=0 style="background-color:$background_color[3]">$s[3]</td>
	</tr>

        </table>
	
	];
	return ("#FFFFFF", $o);
}

##########################################################################################

=head2 ipv6_to_bin_and_sub

=cut

sub ipv6_to_bin_and_sub{
        #address and current chunk of the address we're interested in
	my ($class, $addr, $prefix, $addr_prefix) = @_;
	$class->isa_class_method('ipv6_to_bin_and_sub');
	
	my $mask = 2 ** (128 - ($addr_prefix))-1;
	my $a_shift_left = $addr & $mask;
	my $a = $a_shift_left >> (128-($addr_prefix + 16));
	my $s = $prefix-$addr_prefix;

        if ($s > 16){
                $s = 16;
        }
	my $bin_a = $a->as_bin();
        return ($a, $s);
}

##########################################################################################

=head2 num_bits

=cut

sub num_bits{
        my ($num) = @_;
        my $b = 0;
        while($num > (2 ** $b)){
                $b++;
        }
        return $b;
}

=head1 AUTHORS

Author: Clayton Parker Coleman
July 8th, 2010

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

1;
