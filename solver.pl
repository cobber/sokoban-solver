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
    print "\n\nNew Puzzle:\n";
    $puzzle->dump();
    my @trace = $puzzle->solve();
    printf "Trace: %s\n", join( ', ', @trace );
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

        if( $line =~ m:^(//.*|\s*)$: )
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
            $puzzle = puzzle->new(
                    'width'  => $width,
                    'height' => $height,
                    'status' => 0,
                    'table'  => [],
                    'blocks' => [],
                    );
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
                my $block = block->new( 'puzzle' => $puzzle, 'display' => "\L$import_cell", 'id' => scalar( @{$puzzle->{'blocks'}} ), );
                push( @{$puzzle->{'blocks'}}, $block );
                $block->move_to( $cell );
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

    $_->setup() foreach @{$puzzles};

    return $puzzles;
    }

package puzzle;

use YAML;

sub new { my $c = shift; return bless { @_ }, $c; }

sub setup { my $s = shift; $s->{'solved_mask'} = ( 1 << scalar( @{$s->{'blocks'}} ) ) - 1; }

sub is_solved
    {
    my $s = shift; return $s->{'solved_mask'} == $s->{'status'};
    }

sub solve
    {
    my $s = shift;

    return 'solved' if $s->is_solved();

    if( $s->{'states_seen'}{$s->state()}++ )
        {
#         print "skipping repeat...\n";
        return;
        }

#     print "solving ...\n";
    $s->dump();

    my @trace = ();
    my $mover = $s->{'mover'};
    foreach my $movement ( qw( left right up down ) )
        {
        if( $mover->can_move( $movement ) )
            {
#             print "will move: $movement\n";
            my $state = $s->state();
            $mover->move( $movement );
            my @successful_trace = $s->solve();
            if( @successful_trace )
                {
                @trace = ( $movement, @successful_trace );
                }
            else
                {
                $s->restore( $state );
                }
            }
        last    if @trace;
        }

    return @trace;
    }

sub state
    {
    my $s = shift;
    return join( ':', $s->{'status'}, $s->{'mover'}->location(), sort { $a <=> $b } map { $_->location() } @{$s->{'blocks'}} );
    }

sub restore
    {
    my $s = shift;
#     printf "restoring: %s", $s->state();
    print "---\n";
    my @locations = split( /:/, shift );
    $s->{'status'} = shift( @locations );
    $_->move_to( $s->{'table'}[shift( @locations )] )  foreach $s->{'mover'}, @{$s->{'blocks'}};
#     printf " to: %s\n", $s->state();
    }

sub dump
    {
    my $s = shift;

#     printf "State:  %s\n", $s->state();
#     printf "Status: %s ( %x <=> %x )\n", ( $s->is_solved() ? 'SOLVED' : 'unsolved' ), $s->{'status'}, $s->{'solved_mask'};
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

sub new      { my $class = shift; return bless { @_ }, $class; }

sub location { my $cell = shift; $cell->{'location'}; }
sub is_goal  { my $cell = shift; $cell->{'display'} eq '_'; }
sub is_wall  { my $cell = shift; $cell->{'display'} eq '#'; }
sub is_free  { my $cell = shift; not ( $cell->{'contents'} or $cell->is_wall() ); }

sub display  { my $cell = shift; $cell->{'contents'} ? $cell->{'contents'}->display() : $cell->{'display'}; }

package block;

sub new      { my $c = shift; return bless { @_ }, $c; }
sub location { my $s = shift; $s->{'container'}->location(); }
sub id       { my $s = shift; $s->{'id'}; }
sub mask     { my $s = shift; 1 << $s->{'id'}; }
sub display  { my $s = shift; $s->is_home() ? "\U$s->{'display'}" : $s->{'display'}; }
sub is_home  { my $s = shift; $s->{'container'}->is_goal(); }
sub can_move { my $s = shift; my $direction = shift; $s->{'container'}{$direction} and $s->{'container'}{$direction}->is_free(); }
sub move     { my $s = shift; my $direction = shift; $s->move_to( $s->{'container'}{$direction} ); }
sub move_to
    {
    my $s = shift;
    $s->{'puzzle'}{'status'}      &= ~$s->mask();
    $s->{'container'}{'contents'}  = undef if $s->{'container'};
    $s->{'container'}              = shift;
    $s->{'container'}{'contents'}  = $s;
    $s->{'puzzle'}{'status'}      |= $s->mask() if $s->is_home();
    }

package mover;
use base qw( block );

sub can_move
    {
    my $s = shift;
    my $direction = shift;
    my $neighbour = $s->{'container'}{$direction} or return;
#     printf "mover can move %s: %s\n", $direction, ( $neighbour->is_free() or ( $neighbour->{'contents'} and $neighbour->{'contents'}->can_move( $direction ) ) ) ? "yes" : "no";
    return ( $neighbour->is_free()
            or ( $neighbour->{'contents'} and $neighbour->{'contents'}->can_move( $direction ) ) );   # can block move
    }

sub move
    {
    my $s = shift;
    my $direction = shift;
    my $neighbour = $s->{'container'}{$direction} or return;
    $neighbour->{'contents'} and $neighbour->{'contents'}->move( $direction );  # move the block
    $s->move_to( $neighbour );                                                  # move mover
    }

sub move_to
    {
    my $s = shift;
    $s->{'container'}{'contents'}  = undef if $s->{'container'};
    $s->{'container'}              = shift;
    $s->{'container'}{'contents'}  = $s;
    }
