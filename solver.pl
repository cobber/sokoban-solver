#!/usr/local/bin/perl

# Puzzle File Definition:
#
#   width
#   height
#   map
#
#   map characters:
#       <space> empty
#       #       wall
#       _       goal
#       x       box
#       X       box on goal
#       o       mover
#       O       mover on goal

use strict;
use warnings;
use FindBin qw( $RealBin $Script );  # $Script is the name of the program
use lib "$RealBin/../lib";           # where to find private libraries
use YAML;                            # VERY useful for debugging

my $puzzles = import_puzzles( 'puzzles.txt' );

foreach my $puzzle ( @{$puzzles} )
    {
    $puzzle->dump();
    }

exit 0;

#
# import all the puzzles in a puzzle file for solving
#
sub import_puzzles
    {
    my $filename = shift;
    open( IMPORT_FILE, "<", $filename ) or die "Can't open import file $filename: $!\n";

    my $puzzles = [];
    my $width   = 0;
    my $height  = 0;
    my $row     = 0;
    my $column  = 0;
    my $puzzle  = undef
    my $mover   = undef;

    while( my $line = <IMPORT_FILE> )
        {
        chomp( $line );

        if( $line =~ /^\s*$/ )
            {
            $width  = 0;
            $height = 0;
            push( @{$puzzles}, $puzzle )   if $puzzle;
            $puzzle = undef;
            }

        if( $line =~ /^\s*(\d+)\s*$/ )
            {
            $width  = $1, next  unless $width;
            $height = $1, next  unless $height;
            }

        if( ! $puzzle and $width and $height )
            {
            $puzzle = puzzle->new( 'width' => $width, 'height' => $height, 'table' => [], );
            $row = 0;
            }

        next    unless $puzzle;

        my $table = $puzzle->{'table'};
        $column = 0;
        foreach my $import_cell ( split( '', $line ) )
            {
            my $cell = cell->new( 'location' => $row*$width+$column );

            $cell->{'display'} = ( $import_cell =~ /[_X]/ ) ? '_' : ( ( $import_cell =~ /#/ ) ? '#' : ' ' );

            $table->[$row*$width+$column] = $cell;

            $cell->{'up'} = $table->[($row-1)*$width+$column]   if $row;
            $table->[($row-1)*$width+$column]{'down'} = $cell   if $row;
            $cell->{'left'} = $table->[$row*$width+$column-1]   if $column;
            $table->[$row*$width+$column-1]{'right'} = $cell    if $column;

            if( $import_cell =~ /x/i )
                {
                my $block = block->new( 'container' => $cell, 'display' => "\L$import_cell", );
                $cell->{'contents'} = $block;
                push( @{$puzzle->{'blocks'}}, $block );
                }

            if( $import_cell =~ /o/i )
                {
                my $mover = mover->new( 'container' => $cell, 'display' => "\L$import_cell", );
                $cell->{'contents'} = $mover;
                $puzzle->{'mover'}  = $mover;
                }

            $column++;
            }
            while( $column < $width )
                {
                $puzzle->{'table'}[$row*$width+$column++] = cell->new( 'display' => ' ' );
                }
        $row++;
        }

    push( @{$puzzles}, $puzzle )   if $puzzle;

    close( IMPORT_FILE );

    $_->setup()     foreach @{$puzzles};

    return $puzzles;
    }

package puzzle;

sub new { my $c = shift; return bless { @_ }, $c; }

sub setup
    {
    my $s = shift;
    my $i = 0;
    foreach( @{$s->{'blocks'}} )
        {
        $s->{'status'} |= 1 << ( $_->{'id'} = $i++ );
        }
    $s->{'solved_mask'} = ( 1 << $i ) - 1;
    }

sub solve
    {
    my $s = shift;

    return if $s->is_solved();

    my $mover  = $s->{'mover'};
    my @blocks = $s->{'blocks'};

    my $state = $s->state();
    foreach my $direction ( qw( up down left right ) )
        {
        if( $mover->can_move( $direction ) )
            {
            $mover->move( $direction );
            $s->solve();
            }
        }
    $s->restore( $state )   unless $s->is_solved();

    }

sub state
    {
    my $s = shift;
    return join( ':', $s->{'status'}, map { $_->location() } $s->{'mover'}, @{$s->{'blocks'}} );
    }

sub restore
    {
    my $s = shift;
    my @locations = split( /:/, shift );
    $s->{'status'} = shift( @locations );
    $_->move_to( $s->{'table'}[shift( @locations )] )  foreach $s->{'mover'}, @{$s->{'blocks'}};
    }

sub is_solved
    {
    my $s = shift; return $s->{'solved_mask'} == $s->{'status'};
    }

sub dump
    {
    my $s = shift;

    printf "State: %s\n", $s->state();
    my $width = $s->{'width'};
    foreach my $cell ( @{$s->{'table'}} )
        {
        print $cell->display();
        unless( --$width )
            {
            $width = $s->{'width'};
            print "\n";
            }
        }
    }

package cell;

sub new { my $c = shift; return bless { @_ }, $c; }

sub location { my $s = shift; $s->{'location'}; }
sub is_goal  { my $s = shift; $s->{'display'} eq '_'; }
sub is_wall  { my $s = shift; $s->{'display'} eq '#'; }
sub is_free  { my $s = shift; ! $s->{'contents'}; }
sub up       { my $s = shift; $s->{'up'}    || undef; }
sub down     { my $s = shift; $s->{'down'}  || undef; }
sub left     { my $s = shift; $s->{'left'}  || undef; }
sub right    { my $s = shift; $s->{'right'} || undef; }

sub display { my $s = shift; $s->{'contents'} ? $s->{'contents'}->display( $s->is_goal() ) : $s->{'display'}; }

package block;

sub new      { my $c = shift; return bless { @_ }, $c; }
sub location { my $s = shift; $s->{'container'}->location(); }
sub id       { my $s = shift; $s->{'id'}; }
sub mask     { my $s = shift; 1 << $s->{'id'}; }
sub display  { my $s = shift; my $g = shift; $g ? "\U$s->{'display'}" : $s->{'display'}; }
sub move_to  { my $s = shift; $s->{'container'}{'contents'} = undef; $s->{'container'} = shift; $s->{'container'}{'contents'} = $s; }
sub can_move { my $s = shift; my $direction = shift; $s->{$direction}->is_free(); }
sub move     { my $s = shift; my $direction = shift; $s->move_to( $s->{$direction}->location() ); }

package mover;
use base qw( block );

sub can_move
    {
    my $s = shift;
    my $direction = shift;
    return $s->{$direction}->is_free()
        or $s->{$direction}{'contents'} and $s->{$direction}{'contents'}->can_move( $direction );   # can block move
    }

sub move
    {
    my $s = shift;
    my $direction = shift;
    $s->{$direction}{'contents'} and $s->{$direction}{'contents'}->move( $direction );  # move the block
    $s->move_to( $s->{$direction}->location() );                                        # move mover
    }
