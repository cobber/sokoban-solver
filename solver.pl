#!/usr/local/bin/perl

# Puzzle Map Definition:
#
#   map characters:
#       <space> empty
#       #       wall
#       .       goal
#       $       box
#       *       box on goal
#       @       mover
#       +       mover on goal

use strict;
use warnings;
use FindBin qw( $RealBin $Script );  # $Script is the name of the program
use lib "$RealBin/../lib";           # where to find private libraries
use YAML;                            # VERY useful for debugging

my $puzzles = import_puzzles();

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
    my $puzzles = [];
    my $row     = 0;
    my $column  = 0;
    my $puzzle  = undef
    my $mover   = undef;

    while( my $line = <> )
        {
        chomp( $line );

        if( $line =~ m:^(//.*|\s*)$: )
            {
            if( $puzzle )
                {
                push( @{$puzzles}, $puzzle );
                $puzzle = undef;
                }
            next;
            }

        if( ! $puzzle )
            {
            $puzzle = puzzle->new(
                    'id'     => @{$puzzles} + 1,
                    'width'  => 0,
                    'state'  => 0,
                    'table'  => [],
                    'blocks' => [],
                    'mover'  => undef,
                    );
            }

        $puzzle->push_row();
        foreach my $import_cell ( split( '', $line ) )
            {
            my $cell_display = ' ';
            $cell_display    = '#' if $import_cell =~ /#/;
            $cell_display    = '.' if $import_cell =~ /[\.\*\+]/;

            my $cell = cell->new( 'display' => $cell_display, );
            $puzzle->push_cell( $cell );

            if( $import_cell =~ /[\$*]/ )
                {
                my $block = block->new( 'cell' => $cell, 'id' => scalar( @{$puzzle->{'blocks'}} ), );
                $cell->{'contents'} = $block;
                push( @{$puzzle->{'blocks'}}, $block );
                }

            if( $import_cell =~ /[\@\+]/ )
                {
                my $mover = mover->new( 'cell' => $cell, );
                $cell->{'contents'} = $mover;
                $puzzle->{'mover'}  = $mover;
                }

            }
        }

    push( @{$puzzles}, $puzzle )   if $puzzle;

    $_->setup() foreach @{$puzzles};

    return $puzzles;
    }

package puzzle;

use YAML;

sub new { my $class = shift; return bless { @_ }, $class; }

sub push_row
    {
    my $puzzle = shift;
    push( @{$puzzle->{'table'}}, [] );
    }

sub push_cell
    {
    my $puzzle = shift;
    my $cell   = shift;
    my $table = $puzzle->{'table'};

    push( @{$table->[-1]}, $cell );

    my $row     = $#{$table};
    my $column  = $#{$table->[$row]};

    $puzzle->{'width'} = $column    if $column > $puzzle->{'width'};

    $cell->connect(
            'up'   => $row    ? $table->[$row-1][$column] : undef,
            'left' => $column ? $table->[$row][$column-1] : undef,
            );
    }

sub setup
    {
    my $puzzle = shift;
    $puzzle->{'solved_mask'} = ( 1 << scalar( @{$puzzle->{'blocks'}} ) ) - 1;
    $puzzle->analyse_cells();
    }

sub analyse_cells
    {
    my $puzzle = shift;
    foreach my $row ( @{$puzzle->{'table'}} )
        {
        foreach my $cell ( @{$row} )
            {
            next unless $cell->{'up'} and $cell->{'down'} and $cell->{'left'} and $cell->{'right'};
            $cell->{'is_corner'} = ( $cell->{'up'}->is_wall()   || $cell->{'down'}->is_wall()  )
                                && ( $cell->{'left'}->is_wall() || $cell->{'right'}->is_wall() );
            }
        }
    }

sub is_solved
    {
    my $s = shift; return $s->{'solved_mask'} == $s->{'state'};
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
    return join( ':', $s->{'state'}, $s->{'mover'}->location(), sort { $a <=> $b } map { $_->location() } @{$s->{'blocks'}} );
    }

sub restore
    {
    my $s = shift;
#     printf "restoring: %s", $s->state();
    print "---\n";
    my @locations = split( /:/, shift );
    $s->{'state'} = shift( @locations );
    $_->move_to( $s->{'table'}[shift( @locations )] )  foreach $s->{'mover'}, @{$s->{'blocks'}};
#     printf " to: %s\n", $s->state();
    }

sub dump
    {
    my $puzzle = shift;
    my $long   = shift || 0;

    printf "Puzzle: %d\n", $puzzle->{'id'};
    printf "State:  %s ( %x <=> %x )\n", ( $puzzle->is_solved() ? 'SOLVED' : 'unsolved' ), $puzzle->{'state'}, $puzzle->{'solved_mask'};
    foreach my $row ( @{$puzzle->{'table'}} )
        {
#         printf "%s\n", join( "", map { $_->display() } @{$row} );
#         printf "%s\n", join( "", map { sprintf "%s%s%s%s%s", ( $_->{'left'} ? '<' : ' ' ), ( $_->{'up'} ? '^' : ' ' ), $_->display(), ( $_->{'down'} ? 'v' : ' ' ), ( $_->{'right'} ? '>' : ' ' ), } @{$row} );
        my $cell = $row->[0];
        do
            {
            printf( "%s%s%s%s%s",
                   ( $long ? ( $cell->{'left'}  ? '<' : ' ' ) : '' ),
                   ( $long ? ( $cell->{'up'}    ? '^' : ' ' ) : '' ),
                   $cell->display(),
                   ( $long ? ( $cell->{'down'}  ? 'v' : ' ' ) : '' ),
                   ( $long ? ( $cell->{'right'} ? '>' : ' ' ) : '' )
                   );
            } while( $cell = $cell->{'right'} );
        print "\n";
        }
    }

package cell;

sub new       { my $class = shift; return bless { @_ }, $class; }

sub connect
    {
    my $cell = shift;
    my $opts = { @_ };
    my $up   = $opts->{'up'}   || undef;
    my $left = $opts->{'left'} || undef;

    $cell->{'up'}    = $up      if $up;
    $up->{'down'}    = $cell    if $up;
    $cell->{'left'}  = $left    if $left;
    $left->{'right'} = $cell    if $left;
    }

sub has_block { my $cell = shift; ref( $cell->{'contents'} ) =~ /block/; }
sub contents  { my $cell = shift; $cell->{'contents'}; }
sub up        { my $cell = shift; $cell->{'up'}; }
sub down      { my $cell = shift; $cell->{'down'}; }
sub left      { my $cell = shift; $cell->{'left'}; }
sub right     { my $cell = shift; $cell->{'right'}; }
sub is_goal   { my $cell = shift; $cell->{'display'} eq '.'; }
sub is_wall   { my $cell = shift; $cell->{'display'} eq '#'; }
sub is_bad    { my $cell = shift; $cell->{'is_corner'}; }
sub is_free   { my $cell = shift; not ( $cell->has_block() or $cell->is_wall() or $cell->is_bad() ); }

sub display  
    {
    my $cell = shift;
    return $cell->{'contents'}->display()   if $cell->{'contents'};
    return $cell->{'display'}               if $cell->is_wall or $cell->is_goal();
    return 'X'                              if $cell->is_bad();
    return $cell->{'display'};
    }

package block;

sub new      { my $class = shift; return bless { @_ }, $class; }
sub cell     { my $block = shift; $block->{'cell'}; }
sub id       { my $block = shift; $block->{'id'}; }
sub mask     { my $block = shift; 1 << $block->{'id'}; }
sub display  { my $block = shift; $block->is_home() ? '*' : '$'; }
sub is_home  { my $block = shift; $block->{'cell'}->is_goal(); }
sub can_move { my $block = shift; my $direction = shift; $block->{'cell'}{$direction} and $block->{'cell'}{$direction}->is_free(); }
sub move     { my $block = shift; my $direction = shift; $block->move_to( $block->{'cell'}{$direction} ); }
sub move_to
    {
    my $block = shift;
    $block->{'puzzle'}{'state'}  &= ~$block->mask();
    $block->{'cell'}{'contents'}  = undef if $block->{'cell'};
    $block->{'cell'}              = shift;
    $block->{'cell'}{'contents'}  = $block;
    $block->{'puzzle'}{'state'}  |= $block->mask() if $block->is_home();
    }

package mover;
use base qw( block );

sub display  { my $mover = shift; $mover->{'cell'}->is_goal() ? '+' : '@'; }

sub can_move
    {
    my $mover = shift;
    my $direction = shift;
    my $neighbour = $mover->{'cell'}{$direction} or return;
#     printf "mover can move %s: %s\n", $direction, ( $neighbour->is_free() or ( $neighbour->{'contents'} and $neighbour->{'contents'}->can_move( $direction ) ) ) ? "yes" : "no";
    return ( $neighbour->is_free()
            or ( $neighbour->{'contents'} and $neighbour->{'contents'}->can_move( $direction ) ) );   # can block move
    }

sub move
    {
    my $mover = shift;
    my $direction = shift;
    my $neighbour = $mover->{'cell'}{$direction} or return;
    $neighbour->{'contents'} and $neighbour->{'contents'}->move( $direction );  # move the block
    $mover->move_to( $neighbour );                                                  # move mover
    }

sub move_to
    {
    my $mover = shift;
    $mover->{'cell'}{'contents'}  = undef if $mover->{'cell'};
    $mover->{'cell'}              = shift;
    $mover->{'cell'}{'contents'}  = $mover;
    }
