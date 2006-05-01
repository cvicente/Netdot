package Netdot::Operations;

use Netdot;
use Data::Dumper;

my $ui = Netdot::UI->new;

# Helper methods for the operations page

# Given a list of contacts find those that have availability != never
# for one of notify_voice, notify_page, or notify_email.

# Returns array ref of (<contact>, <field>, [<field>, [<field>]])
# array refs where the fields grouped with contact are those suchthat
# contact->field != Never.

sub contactable_contacts {
    my @contacts = @_;
    
    my @fields = qw/notify_voice notify_pager notify_email/;

    my @sets = map { 
	$contact = $_; 
	# Anon hash
	{ 'contact' => $contact, 
	  'availabilities' => [grep { length($contact->$_->name) > 0 
					  and $contact->$_->name ne "Never"
				      } @fields
			       ], 
      }
    } @contacts;

    _debug(@sets);

    my @available = grep { scalar @{ $_->{availabilities} } > 0 } @sets;
    
    _debug(@available);

    return @available;
}

# Circuits are pretty rare: Use the generic search to find one for
# testing.  The cisco-ts* devices seem to have them.
;{
    package Device;
    sub all_circuits {
	my ($device) = @_;
        return map { ($_->nearcircuits, $_->farcircuits) } $device->interfaces;
    }
}

;{
    package Entity;
    sub all_circuits {
	my ($entity) = @_;
        return map {$_->circuits} $entity->connections;
    }
}

sub _debug {
    #print "<pre>" . Dumper(@_) . "</pre>";
}

;{
    package Netdot::DBI;
    # Default view page for all Netdot::DBI subclasses.
    # Override this in subclasses with special view pages
    sub _viewing_page { "view.html" }
    
    # This is a helper so you can ask an object for its label
    # directly.  The label is defined in the metatable (see
    # bin/insert-metadata).
    sub label {
	my $self = shift;
	return $ui->getobjlabel($self, ", ");
    }
    
    # Make a canonical link: one with text the name of the object
    # pointing to the view.html page for that object.
    sub view_link {
	my $self = shift;
	# Optional second arg gives viewing page, otherwise class
	# default is used.
	my $page = shift || $self->_viewing_page;

	return "<a href=\"${page}?table=@{[ $self->table ]}&id=@{[ $self->id ]}\"> @{[ $self->label ]} </a>";
    }
}

;{
    package Device;
    # Device has a custom view page.
    sub _viewing_page { "device.html" }
}

# This is braindead
1;

# sub get_object {
#     my ($obj, $id, $table) = @_;
#     # Assumes no $ids are 0.  I think this is true in MySQL, not sure
#     # about other DB's
#     $obj || $id && $table->retrieve($id)
# 	or die "You must supply a valid object id or reference";
#}
