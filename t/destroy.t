#!perl

# Make sure that the objects get destroyed at the appropriate time

use Test::More tests => 3;
use strict;
use warnings;

use Data::Iterator::Hierarchical;

my $destroyed;

sub Data::Iterator::Hierarchical::Test::DESTROY {
    $destroyed++;
}

my $sth = [
    [ 1, 1, 999 ],
    [ 2, 2, 2 ],
    [ bless {}, 'Data::Iterator::Hierarchical::Test' ],
    ];

{
    my $it = hierarchical_iterator($sth);
    undef $sth;
    my ($one) = $it->(my $it2,1);
    my ($two) = $it2->(my $it3,1);
    my ($three) = $it3->();
    is($three,999,'sanity check - looking at right data');
    ok(!$destroyed,'santy check - not prematurely destroyed');
}

ok($destroyed,'destroyed');
