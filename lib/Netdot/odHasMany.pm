package Class::DBI::Relationship::odHasMany;

use strict;
use warnings;

use base 'Class::DBI::Relationship::HasMany';

sub remap_arguments {
    my ($proto, $class, $accessor, $f_class, $f_key, $args) = @_;
    
    my %on_delete_beh = ( 'cascade'  => 1,
			  'set-null' => 1,
			  'restrict' => 1,
			  );
    
    return $class->_croak("has_many needs an accessor name") unless $accessor;
    return $class->_croak("has_many needs a foreign class")  unless $f_class;
    $class->can($accessor)
	and return $class->_carp("$accessor method already exists in $class\n");
    
    my @f_method = ();
    if (ref $f_class eq "ARRAY") {
	($f_class, @f_method) = @$f_class;
    }
    $class->_require_class($f_class);
    
    if (ref $f_key eq "HASH") {    # didn't supply f_key, this is really $args
	$args  = $f_key;
	$f_key = "";
    }
    
    $f_key ||= do {
	my $meta = $f_class->meta_info('has_a');
	my ($col) = grep $meta->{$_}->foreign_class eq $class, keys %$meta;
	$col || $class->table_alias;
    };

    if (ref $f_key eq "ARRAY") {
	return $class->_croak("Multi-column foreign keys not supported")
	    if @$f_key > 1;
	$f_key = $f_key->[0];
    }
    
    $args ||= {};
    $args->{mapping}     = \@f_method;
    $args->{foreign_key} = $f_key;
    $args->{order_by} ||= $args->{sort};    
    warn "sort argumemt to has_many deprecated in favour of order_by"
	if $args->{sort};             

    # Make 'cascade' the default on_delete behaviour
    $args->{on_delete} ||= "cascade";
    
    unless ( exists $on_delete_beh{$args->{on_delete}} ){
	return $class->_croak("Unknown on_delete behavior: $args->{on_delete}");
    }
    
    return ($class, $accessor, $f_class, $args);
}


sub triggers {
    my $self = shift;
    if ($self->args->{on_delete} eq "restrict"){
	return (
		before_delete => sub {
		    if ( scalar  $self->foreign_class->search($self->args->{foreign_key} => shift->id) ){
			return $self->class->_croak("Deletion restricted to keep referential integrity");
		    }
		});
	
    }elsif ($self->args->{on_delete} eq "set-null"){
	return (
		before_delete => sub {
		    foreach ( $self->foreign_class->search($self->args->{foreign_key} => shift->id) ){
			$_->set($self->args->{foreign_key}, 'NULL');
			$_->update;
		    }
		});
    }elsif ($self->args->{on_delete} eq "cascade"){
	return (
		before_delete => sub {
		    $self->foreign_class->search($self->args->{foreign_key} => shift->id)
			->delete_all;
		});
    }
}


1;

__END__

=head1 NAME

     Class::DBI::Relationship::odHasMany - on_delete HasMany Relationship Class   

=head1 SYNOPSIS

    In your application base class:

    use Music::odHasMany;

     __PACKAGE__->add_relationship_type(
        has_many   => "Class::DBI::Relationship::odHasMany",
	       );

    Music::CD->has_many(tracks => 'Music::Track', { on_delete=>"cascade" } ");

=head1 DESCRIPTION
    
     odHasMany inherits from Class::DBI::Relationship::HasMany and overrides some of its methods to add
     the argument "on_delete", which defines three behaviors at object deletion time:
    
             'restrict'  : The object can't be deleted because objects exist that reference it
             'cascade'   : Deletes the object and all objects referencing it (default)
             'set-null'  : The object is deleted and the referencing objects' foreign keys are set to NULL

     This mimics what several DBs offer, avoiding the need to define it at the DB level.
    
     The current CDBI's (0.96) only option is no_cascade_delete, which is limited.  odHasMany provides
     more flexibility.

=head1 CURRENT AUTHOR
    
    Carlos Vicente <cvicente@uoregon.edu> (extended Tony Bowden's HasMany)
    
    This functionality was first suggested by Tim Bunce in the CDBI mailing list.

        http://groups.kasei.com/mail/arc/cdbi-talk/2003-02/msg00142.html

=head1 LICENSE

     This library is free software; you can redistribute it and/or modify
     it under the same terms as Perl itself.

=head1 SEE ALSO

     L<Class::DBI::Relationship>

