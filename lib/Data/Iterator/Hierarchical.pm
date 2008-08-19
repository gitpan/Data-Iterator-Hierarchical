package Data::Iterator::Hierarchical;

use warnings;
use strict;

=head1 NAME

Data::Iterator::Hierarchical - Iterate hierarchically over data

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';


=head1 SYNOPSIS

      my $sth = $db->prepare(<<SQL);
        SELECT agent, co, co_name, sound
        FROM some_view_containing_left_joins 
        ORDER BY agent, co, sound
      SQL

      $sth->execute;

      my $it = hierarchical_iterator($sth);

      while( my($agent) = $it->(my $it_co, 1)) {
	print "agent=$agent\n";
	while( my ($co,$co_name) = $it_co->(my $it_sound, 2) ) {
	  print "  co=$co, co_name=$co_name\n";
	  while( my($sound) = $it_sound->() ) {
	    print "    sound=$sound\n";   
	  }
	}
      }

=head1 DESCRIPTION

This module allows nested loops to iterate in the natural way
over a sorted rowset as would typically be returned from an SQL
database query.

In the example from the synopsis we want an interator that loops over
agent. Within that we want another interator to loop over country
(code and name).  Finally within that we want to loop over sound.

And mostly that's all there is to say the iterator should just "Do
What I Mean" (DWIM).

=head2 input

     agent   |  co     | co_name  | sound
    =========|=========|==========|========
      X      |  B      | Belgum   | fizz
      X      |  D      | Germany  | bang
      X      |  D      | Germany  | pow
      X      |  D      | Germany  | zap
      Y      |  NULL   | NULL     | NULL
      Z      |  B      | Belgum   | NULL
      Z      |  E      | Spain    | bar 
      Z      |  E      | Spain    | bar 
      Z      |  I      | Italy    | foo

=head2 output

    agent=X
      co=B, co_name=Belgum
        sound=fizz
      co=D, co_name=Germany
        sound=bang
        sound=pow
        sound=zap
    agent=Y
    agent=Z
      co=B, co_name=Belgum
      co=E, co_name=Spain
        sound=bar
        sound=bar
      co=I, co_name=Italy
        sound=foo

=head1 EXPORT

C<hierarchical_iterator>

=cut 

use base qw(Exporter);
our @EXPORT = qw(hierarchical_iterator);

=head1 FUNCTIONS

=head2 hierarchical_iterator($rowset_source)

A factory for iterator functions. Takes a rowset source as an argument
and returns an interator function.

The input rowset is cannonically presented as iterator function that
is to be called with no arguments in a list context and is expected to
return the next row from the set as a list.  When the input is
exhasted the iterator is expected to return an empty list.

For convienience the data source can also be specified simply as
C<\@array> in which case the interator C<sub { shift @array }> is
assumed. Finally, if the data source is specified as anything other
than an ARRAY or CODE reference then it is assumed to be an object
that provides a C<fetchrow_array()> method (such as a L<DBI> handle).

=cut

sub hierarchical_iterator {
    my ($input) = @_;
    my $get = do {
	if (ref($input) eq 'CODE') { 
	    $input;
	} elsif ( ref($input) eq 'ARRAY' ) {
	    +sub { @{ shift @$input || [] } } ;
	} else {
	    +sub { $input->fetchrow_array }; 
	};       
    };
    my ($row,$unchanged,$returned,$undef_after);

    my $make_iterator = sub {
	my ($mk_another,$fixed) = @_;
	sub {
	    unless ( wantarray ) {
		require Carp;
		Carp::croak('Data::Iterator::Hierarchical iterator called in non-LIST context');
	    }
	    my ($inner,$cols) ;

	    if ( @_ ) {
		$inner = \shift;
		$cols = shift;
		unless ( defined $cols ) {
		    unless ( eval { require Want; 1 }) {
			require Carp;
			Carp::croak('Number of columns to consume must be specified if Want is not installed');
		    }

		    unless ( $cols = Want::howmany() ) {
			require Carp;
			Carp::croak('Number of columns to consume must be specified if not implicit');
		    }
		}
	    }
	    
	    my $last_col;
	    $last_col = $fixed + $cols - 1 if $cols;
	    
	  GET:
	    while(1) {
		if ( $row ) {
		    # Input exhasted
		    return unless @$row;

		    # This level exhasted
		    return if defined $unchanged && $unchanged < $fixed;

		    # Unspecifed cols => all
		    $last_col = $#$row unless $cols;

		    # Skip duplicate data when we're not at the innermost
		    next if defined $unchanged &&
			$inner &&
			$unchanged > $last_col; 
		    
		    # Skip if everything to the right is undef
		    next if $undef_after <= $fixed;

		    # There's more to come from the current row
		    last if $returned < $fixed;
		}
	    } continue {
		my $prev_row = $row;
		$row = [ $get->() ];
	      
		# Nothing of this data has been returned yet
		$returned = -1;
		
		# Count unchanged columns at left
		$unchanged=0;
		if ( $prev_row ) {
		    for ( @$row ) {
			last unless @$prev_row;
			last unless defined ==
			    defined ( my $old_datum = shift @$prev_row);
			no warnings 'uninitialized';
			last unless $_ eq $old_datum;
			$unchanged++;
		    }
		}

		# Count undef colums at right
		$undef_after = @$row;
		for ( reverse @$row ) {
		    last if defined;
		    $undef_after--;
		}
		
	    }
	    undef $unchanged;

	    if ($inner) {
		# Must pass $mk_another in each time as if we were to
		# use $make_iterator directly we'd create a circular
		# reference and break garbage collection.
		$$inner = $mk_another->($mk_another, $last_col + 1);
	    }	    
	    
	    $returned = $fixed;
	    return @$row[$fixed .. $last_col];
	};
    };
    $make_iterator->($make_iterator,0);
}

=head2 $iterator->($inner_iterator,$want)

The ineresting function from this module is, of course, the iterator
function returned by the iterator factory.  This iterator when called
in a list context without arguments simply returns the next a row of
data, or an empty list to denote exhaustion. It is an error to call
the iterator in a non-LIST context.  As an artifact, rows that consist
entirely of undef()s are skipped.

So, when called without arguments, the iterator returned by
C<hierarchical_iterator()> is pretty much the same as the iterator
that was supplied as the input!  The interesting stuff starts
happening when you pass arguments to the iterator function.

The I<second> argument instructs the interator to return only a
limited number of leading columns to from each row. The I<first>
argument is used to return an inner Data::Iterator::Hierarchical iterator
that will iterate over only the successive rows of the input until the
leading colums change and return only the I<remaining> columns.

    my ($col1,$col2) = $iterator->(my $inner_iterator,2);

The two arguments are specified this seemingly illogical order because
the second argument becomes optional if the L<Want> module is
installed and the iterator is used in a simple list assignment (as
above). In this case the number of columns can be inferred from the
left hand side of the assignment.

In the above example, if $inner_iterator is not used to exhastion,
then the next invocation of $iterator will discard all input rows
until there is a different pair of values in the first two columns.

=head1 BUGS AND CAVEATS

Note that 

To do: (need stuff in here about nulls, non-rectangular input,
repeated rows, changing the number of columns half way etc.)

=head1 AUTHOR

Brian McCauley, C<< <nobull at cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-data-iterator-hierarchical at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Data-Iterator::Hierarchical>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Data::Iterator::Hierarchical


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Data-Iterator::Hierarchical>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Data-Iterator::Hierarchical>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Data-Iterator::Hierarchical>

=item * Search CPAN

L<http://search.cpan.org/dist/Data-Iterator::Hierarchical>

=back

=head1 ACKNOWLEDGEMENTS


=head1 COPYRIGHT & LICENSE

Copyright 2008 Brian McCauley, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


=cut

1; # End of Data::Iterator::Hierarchical
