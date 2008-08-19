#!perl

# Test that the example in the POD is actually correct

use Test::More tests => 1;
use strict;
use warnings;

my %saved_bits;

use Data::Iterator::Hierarchical;

{
    package Data::Iterator::Hierarchical::Test::Pod::Parser;
    use base 'Pod::Parser';

    my $save_bit;

    sub command {
	my ($parser, $command, $paragraph, $line_num) = @_;
	my ($arg) = $paragraph =~ /(.*)/;
	$save_bit = "$command $arg";
    }

    sub verbatim {
	my ($parser, $paragraph, $line_num) = @_;
	push@{$saved_bits{$save_bit}} => $paragraph;
    }

    sub textblock {
	my ($parser, $paragraph, $line_num) = @_;
    }
}

{
    my $parser = Data::Iterator::Hierarchical::Test::Pod::Parser->new;
    $parser->parse_from_file('lib/Data/Iterator/Hierarchical.pm');
}

#use Data::Dumper; die Dumper \%saved_bits;

my $sth = [ map { my @r = /(\w+)/g; for (@r) { undef $_ if $_ eq 'NULL' }; @r ? \@r : () } split /\n/, $saved_bits{'head2 input'}[0] ];
shift @$sth; # Remove header row

my $code = "1";
for ( reverse @{$saved_bits{'head1 SYNOPSIS'}} ) {
    last if /->execute/;
    $code = "$_$code";
}

my $expected = $saved_bits{'head2 output'}[0];

for ( $expected ) {
    my ($indent) = /(\s*)/;
    s/^$indent//mg;
    s/ +$//mg;
    s/\n+\Z/\n/;
}

open my $output_fh, '>', \my $output or die $!;
select $output_fh;
eval $code or die $@;
select *STDOUT;
close $output_fh;

# Uncomment this to get something to paste into POD
# print "---8<---\n$output---8<---\n";

is_deeply([$output =~ /^(.*)/mg],[$expected =~ /^(.*)/mg]);
