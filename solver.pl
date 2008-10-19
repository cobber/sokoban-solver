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

my $opposite = {
                'up'    => 'down',
                'down'  => 'up',
                'left'  => 'right',
                'right' => 'left',
                };

test_suite::run()   unless @ARGV;

my $puzzles = importer::import_puzzles( <> );

foreach my $puzzle ( @{$puzzles} )
    {
    print "\n";
    printf "Solving Puzzle Number %d\n", $puzzle->{'id'};
    $puzzle->dump();
    print Dump( $puzzle->solve() );
    }

exit 0;

package importer;

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

    foreach my $line ( @_ )
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
                    'score'  => 0,
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
                my $block = block->new( 'id' => scalar( @{$puzzle->{'blocks'}} ), );
                push( @{$puzzle->{'blocks'}}, $block );
                $puzzle->move_block_to( $block => $cell );
                }

            if( $import_cell =~ /[\@\+]/ )
                {
                my $mover = mover->new();
                $puzzle->{'mover'} = $mover;
                $mover->move_to( $cell );
                }

            }
        }

    push( @{$puzzles}, $puzzle )   if $puzzle;

    $_->setup() foreach @{$puzzles};

    return $puzzles;
    }

package puzzle;

use YAML;

sub new
    {
    my $class = shift;
    my $puzzle = bless { @_ }, $class;
    $puzzle->{'table'} = [];
    $puzzle->{'cells'} = [];
    return $puzzle;
    }

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

    if( ! $cell->is_wall() )
        {
        $cell->{'id'} = @{$puzzle->{'cells'}};
        push( @{$puzzle->{'cells'}}, $cell );
        }

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
    $puzzle->{'top_score'} = ( 1 << scalar( @{$puzzle->{'blocks'}} ) ) - 1;
    $puzzle->mark_corners();
    $puzzle->{'mover'}->{'cell'}->set_active();
    }

sub mark_corners
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

sub move_block_to
    {
    my $puzzle = shift;
    my $block  = shift;
    my $target = shift;

    $puzzle->{'score'}  &= ~$block->mask();
    $block->move_to( $target );
    $puzzle->{'score'}  |= $block->mask() if $block->is_home();
    }

sub move_block
    {
    my $puzzle    = shift;
    my $block     = shift;
    my $direction = shift;

    my $old_block_cell = $block->{'cell'};
    $puzzle->lift_mover();

    $puzzle->{'score'}  &= ~$block->mask();
    $block->move( $direction );
    $puzzle->{'score'}  |= $block->mask() if $block->is_home();

    $puzzle->place_mover_in( $old_block_cell );
    }

sub possible_moves
    {
    my $puzzle = shift;

    my @moves = ();
    foreach my $block ( @{$puzzle->{'blocks'}} )
        {
        foreach my $direction ( $block->possible_moves() )
            {
            push( @moves, {
                    'block_id'  => $block->{'id'},
                    'direction' => $direction,
                    }
                );
            }
        }

    return @moves;
    }

sub lift_mover
    {
    my $puzzle = shift;
    $puzzle->{'mover'}->lift_up();
    }

sub place_mover_in
    {
    my $puzzle      = shift;
    my $target_cell = shift;
    $puzzle->{'mover'}->move_to( $target_cell );
    }

sub is_solved
    {
    my $puzzle = shift; return $puzzle->{'score'} == $puzzle->{'top_score'};
    }

sub solve
    {
    my $puzzle    = shift;
    my $level     = shift || 0;
    my $state     = $puzzle->state();       # used for recovering the exact state
    my $state_id  = $puzzle->state_id();    # state_id doesn't specify exactly where the mover is
    my @trace     = ();

    return ( [ 'solved' ] ) if $puzzle->is_solved();

    return if $puzzle->{'has_tried'}{$state_id}++;

    my @possible_moves = $puzzle->possible_moves();

    my $movement = undef;
    while( ! $puzzle->is_solved()
            and $movement = shift( @possible_moves )
            )
        {
        my $block_id    = $movement->{'block_id'};
        my $direction   = $movement->{'direction'};
        my $block       = $puzzle->{'blocks'}[$block_id];

        $puzzle->move_block( $block => $direction );

        my @successful_trace = $puzzle->solve( $level + 1 );

        if( @successful_trace )
            {
            @trace = ( [$block->{'display'} => $direction], @successful_trace );
            }
        else
            {
            $puzzle->restore( $state );
            }
        }

    return @trace;
    }

sub state_id
    {
    my $puzzle = shift;
    return join( '', map { $_->has_block() ? '$' : ( $_->is_active() ? '+' : '-' ) } @{$puzzle->{'cells'}} );
    }

sub state
    {
    my $puzzle = shift;
    return join( ':', $puzzle->{'mover'}->{'cell'}{'id'}, map { $_->{'cell'}{'id'} } @{$puzzle->{'blocks'}} );
    }

sub restore
    {
    my $puzzle        = shift;
    my $recover_state = shift;
    $puzzle->{'score'} = 0;
    my @state = split( /:/, $recover_state );
    $puzzle->place_mover_in( $puzzle->{'cells'}[shift( @state )] );
    $puzzle->move_block_to( $_ => $puzzle->{'cells'}[shift( @state )] )  foreach @{$puzzle->{'blocks'}};
    }

sub dump
    {
    my $puzzle = shift;
    my $long   = shift || 0;

    printf "Puzzle: %d\n", $puzzle->{'id'};
    printf "Score:  %s ( %d of %d )\n", ( $puzzle->is_solved() ? 'SOLVED' : 'unsolved' ), $puzzle->{'score'}, $puzzle->{'top_score'};
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

sub set_active
    {
    my $cell = shift;
    return if $cell->is_active();
    return if $cell->is_wall();
    return if $cell->has_block();
    $cell->{'is_active'} = 1;
    $cell->{$_}->set_active() foreach qw( up down left right );
    }

sub clear_active
    {
    my $cell = shift;
    return unless $cell->is_active();
    return if $cell->is_wall();
    return if $cell->has_block();
    $cell->{'is_active'} = 0;
    $cell->{$_}->clear_active() foreach qw( up down left right );
    }

sub is_active { my $cell = shift; $cell->{'is_active'}; }
sub has_block { my $cell = shift; ref( $cell->{'contents'} ) =~ /block/; }
sub contents  { my $cell = shift; $cell->{'contents'}; }
sub up        { my $cell = shift; $cell->{'up'}; }
sub down      { my $cell = shift; $cell->{'down'}; }
sub left      { my $cell = shift; $cell->{'left'}; }
sub right     { my $cell = shift; $cell->{'right'}; }
sub is_goal   { my $cell = shift; $cell->{'display'} eq '.'; }
sub is_wall   { my $cell = shift; $cell->{'display'} eq '#'; }
sub is_bad    { my $cell = shift; $cell->{'is_corner'} and not $cell->is_goal(); }
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
use YAML;

sub new
    {
    my $class = shift;
    my $block = bless { @_ }, $class;

    $block->{'mask'}    = 1 << $block->{'id'};
    $block->{'display'} = chr( ord('a') + $block->{'id'} );

    return $block;
    }

sub cell      { my $block = shift; $block->{'cell'}; }
sub id        { my $block = shift; $block->{'id'}; }
sub mask      { my $block = shift; $block->{'mask'}; }
sub display   { my $block = shift; $block->is_home() ? uc( $block->{'display'} ) : $block->{'display'}; }
sub is_home   { my $block = shift; $block->{'cell'}->is_goal(); }
sub is_active { my $block = shift; my $direction = shift; $block->{'cell'}{$direction}->is_active(); }

sub can_move
    {
    my $block       = shift;
    my $direction   = shift;
    $block->{'cell'}{$direction}->is_free();
    }

sub move
    {
    my $block = shift;
    my $direction = shift;
    $block->move_to( $block->{'cell'}{$direction} );
    $block->{'cell'}{'is_active'} = 0;
    $block->{'cell'}{$_}->clear_active() foreach grep( ! /$opposite->{$direction}/, qw( up down left right ) );
    $block->{'cell'}{$opposite->{$direction}}->set_active();
    }

sub move_to
    {
    my $block = shift;
    $block->{'cell'}{'contents'}  = undef   if $block->{'cell'};
    $block->{'cell'}              = shift;
    $block->{'cell'}{'contents'}  = $block;
    }

sub possible_moves
    {
    my $block = shift;
    my @available_moves = ();
    foreach my $direction ( qw( up down left right ) )
        {
        next unless $block->can_move( $direction );
        next unless $block->is_active( $opposite->{$direction} );
        push( @available_moves, $direction );
        }
    return @available_moves;
    }

package mover;
use base qw( block );

sub new      { my $class = shift; return bless { @_ }, $class; }

sub display  { my $mover = shift; $mover->{'cell'}->is_goal() ? '+' : '@'; }

sub lift_up  { my $mover = shift; $mover->{'cell'}{'contents'} = undef; $mover->{'cell'} = undef; }

package test_suite;

use YAML;
use Test::More;

sub run
    {
    plan( tests => 116 );

    my $puzzles = importer::import_puzzles( <DATA> );

    test0( $puzzles->[0] );
    test1( $puzzles->[1] );

    exit();
    }

sub test0
    {
    my $puzzle = shift;
    is( scalar( @{$puzzle->{'cells'}} ),        3,      'only 3 cells' );
    is( scalar( @{$puzzle->{'blocks'}} ),       1,      'only 1 block' );
    is( $puzzle->{'mover'}{'cell'}{'id'},       1,      'mover on cell 1' );
    is( $puzzle->{'blocks'}[0]{'cell'}{'id'},   0,      'block on cell 0' );
    is( $puzzle->state(),                       '1:0',  'mover on cell 1, block only on cell 0' );
    is( $puzzle->state_id(),                    '$++',  'state id: block active active' );
    is( $puzzle->{'score'},                     1,      'score' );
    is( $puzzle->{'top_score'},                 1,      'top score' );
    is( $puzzle->is_solved(),                   '1',    'puzzle is already solved' );
    is( $puzzle->{'cells'}[0]{'is_corner'},     1,      'corner' );
    is( $puzzle->{'cells'}[0]->has_block(),     1,      'has block' );
    is( $puzzle->{'cells'}[0]->is_bad(),        '',     'not bad (is goal)' );
    is( $puzzle->{'cells'}[0]->is_free(),       '',     'not free' );
    is( $puzzle->{'cells'}[0]->is_goal(),       1,      'goal' );
    is( $puzzle->{'cells'}[1]{'is_corner'},     '',     'not corner' );
    is( $puzzle->{'cells'}[1]->has_block(),     '',     'no block' );
    is( $puzzle->{'cells'}[1]->is_bad(),        '',     'not bad' );
    is( $puzzle->{'cells'}[1]->is_free(),       1,      'free (mover doesn\'t count)' );
    is( $puzzle->{'cells'}[1]->is_goal(),       '',     'not goal' );
    is( $puzzle->{'cells'}[2]{'is_corner'},     1,      'corner' );
    is( $puzzle->{'cells'}[2]->has_block(),     '',     'no block' );
    is( $puzzle->{'cells'}[2]->is_bad(),        1,      'bad' );
    is( $puzzle->{'cells'}[2]->is_free(),       '',     'not free (is bad)' );
    is( $puzzle->{'cells'}[2]->is_goal(),       '',     'not goal' );
    }

sub test1
    {
    my $puzzle         = shift;
    my @possible_moves = ();
    my $state          = undef;

    is( scalar( @{$puzzle->{'cells'}} ),        9,              'number of cells' );
    is( scalar( @{$puzzle->{'blocks'}} ),       2,              'number of blocks' );
    is( $puzzle->{'mover'}{'cell'}{'id'},       1,              'mover location' );
    is( $puzzle->{'blocks'}[0]{'cell'}{'id'},   3,              'block location' );
    is( $puzzle->state(),                       '1:3:4',        'mover and then block locations' );
    is( $puzzle->state_id(),                    '+++$$++++',    'state id: block active active' );
    is( $puzzle->{'score'},                     0,              'score' );
    is( $puzzle->{'top_score'},                 3,              'top score' );
    is( $puzzle->is_solved(),                   '',             'puzzle is already solved' );
    is( $puzzle->{'cells'}[0]{'is_corner'},     1,              'corner' );
    is( $puzzle->{'cells'}[0]->has_block(),     '',             'no block' );
    is( $puzzle->{'cells'}[0]->is_bad(),        1,              'bad (corner)' );
    is( $puzzle->{'cells'}[0]->is_free(),       '',             'not free (corner)' );
    is( $puzzle->{'cells'}[0]->is_goal(),       '',             'not goal' );
    is( $puzzle->{'cells'}[1]{'is_corner'},     '',             'not corner' );
    is( $puzzle->{'cells'}[1]->has_block(),     '',             'no block' );
    is( $puzzle->{'cells'}[1]->is_bad(),        '',             'not bad' );
    is( $puzzle->{'cells'}[1]->is_free(),       1,              'free (mover doesn\'t count)' );
    is( $puzzle->{'cells'}[1]->is_goal(),       1,              'goal' );
    is( $puzzle->{'cells'}[2]{'is_corner'},     1,              'corner' );
    is( $puzzle->{'cells'}[2]->has_block(),     '',             'no block' );
    is( $puzzle->{'cells'}[2]->is_bad(),        1,              'bad (corner)' );
    is( $puzzle->{'cells'}[2]->is_free(),       '',             'not free (is bad)' );
    is( $puzzle->{'cells'}[2]->is_goal(),       '',             'not goal' );
    is( $puzzle->{'cells'}[3]{'is_corner'},     '',             'not a corner' );
    is( $puzzle->{'cells'}[3]->has_block(),     1,              'block' );
    is( $puzzle->{'cells'}[3]->is_bad(),        '',             'not bad' );
    is( $puzzle->{'cells'}[3]->is_free(),       '',             'not free (has block)' );
    is( $puzzle->{'cells'}[3]->is_goal(),       '',             'not goal' );
    is( $puzzle->{'cells'}[4]{'is_corner'},     '',             'not corner' );
    is( $puzzle->{'cells'}[4]->has_block(),     1,              'has block' );
    is( $puzzle->{'cells'}[4]->is_bad(),        '',             'not bad' );
    is( $puzzle->{'cells'}[4]->is_free(),       '',             'not free (has block)' );
    is( $puzzle->{'cells'}[4]->is_goal(),       '',             'not goal' );
    is( $puzzle->{'cells'}[5]{'is_corner'},     '',             'not corner' );
    is( $puzzle->{'cells'}[5]->has_block(),     '',             'no block' );
    is( $puzzle->{'cells'}[5]->is_bad(),        '',             'not bad' );
    is( $puzzle->{'cells'}[5]->is_free(),       1,              'free' );
    is( $puzzle->{'cells'}[5]->is_goal(),       '',             'not goal' );
    is( $puzzle->{'cells'}[6]{'is_corner'},     1,              'corner' );
    is( $puzzle->{'cells'}[6]->has_block(),     '',             'no block' );
    is( $puzzle->{'cells'}[6]->is_bad(),        '',             'not bad (is goal)' );
    is( $puzzle->{'cells'}[6]->is_free(),       1,              'free' );
    is( $puzzle->{'cells'}[6]->is_goal(),       1,              'goal' );
    is( $puzzle->{'cells'}[7]{'is_corner'},     '',             'not corner' );
    is( $puzzle->{'cells'}[7]->has_block(),     '',             'no block' );
    is( $puzzle->{'cells'}[7]->is_bad(),        '',             'not bad' );
    is( $puzzle->{'cells'}[7]->is_free(),       1,              'free' );
    is( $puzzle->{'cells'}[7]->is_goal(),       '',             'not goal' );
    is( $puzzle->{'cells'}[8]{'is_corner'},     1,              'corner' );
    is( $puzzle->{'cells'}[8]->has_block(),     '',             'no block' );
    is( $puzzle->{'cells'}[8]->is_bad(),        1,              'bad' );
    is( $puzzle->{'cells'}[8]->is_free(),       '',             'not free (is bad)' );
    is( $puzzle->{'cells'}[8]->is_goal(),       '',             'not goal' );

    @possible_moves = $puzzle->possible_moves();
    is( scalar( @possible_moves ), 3, 'number of possible moves' );
    is( $possible_moves[0]{'block_id'},       0, 'block to move' );
    is( $possible_moves[0]{'direction'}, 'down', 'direction to move' );
    is( $possible_moves[1]{'block_id'},       1, 'block to move' );
    is( $possible_moves[1]{'direction'},   'up', 'direction to move' );
    is( $possible_moves[2]{'block_id'},       1, 'block to move' );
    is( $possible_moves[2]{'direction'}, 'down', 'direction to move' );

    $puzzle->move_block( $puzzle->{'blocks'}[0], 'down' );
    is( $puzzle->{'blocks'}[0]->is_home(),  1,  'moved block 0 onto goal' );
    is( $puzzle->{'score'},                 1,  'score' );
    is( $puzzle->{'top_score'},             3,  'top score' );
    is( $puzzle->is_solved(),              '', 'not solved yet' );

    @possible_moves = $puzzle->possible_moves();
    is( scalar( @possible_moves ), 4, 'number of possible moves' );
    is( $possible_moves[0]{'block_id'},        1, 'block to move' );
    is( $possible_moves[0]{'direction'},    'up', 'direction to move' );
    is( $possible_moves[1]{'block_id'},        1, 'block to move' );
    is( $possible_moves[1]{'direction'},  'down', 'direction to move' );
    is( $possible_moves[2]{'block_id'},        1, 'block to move' );
    is( $possible_moves[2]{'direction'},  'left', 'direction to move' );
    is( $possible_moves[3]{'block_id'},        1, 'block to move' );
    is( $possible_moves[3]{'direction'}, 'right', 'direction to move' );

    $state = $puzzle->state();

    $puzzle->move_block( $puzzle->{'blocks'}[1], 'down' );
    is( $puzzle->{'blocks'}[1]->is_home(), '', 'moved block 1 wrong' );
    is( $puzzle->{'score'},                 1,  'score' );
    is( $puzzle->{'top_score'},             3,  'top score' );
    is( $puzzle->is_solved(),              '', 'not solved yet' );

    @possible_moves = $puzzle->possible_moves();
    is( scalar( @possible_moves ), 0, 'no moves available' );

    $puzzle->restore( $state );
    $puzzle->dump();

    @possible_moves = $puzzle->possible_moves();
    is( scalar( @possible_moves ), 4, 'number of possible moves' );
    is( $possible_moves[0]{'block_id'},        1, 'block to move' );
    is( $possible_moves[0]{'direction'},    'up', 'direction to move' );
    is( $possible_moves[1]{'block_id'},        1, 'block to move' );
    is( $possible_moves[1]{'direction'},  'down', 'direction to move' );
    is( $possible_moves[2]{'block_id'},        1, 'block to move' );
    is( $possible_moves[2]{'direction'},  'left', 'direction to move' );
    is( $possible_moves[3]{'block_id'},        1, 'block to move' );
    is( $possible_moves[3]{'direction'}, 'right', 'direction to move' );

    $puzzle->move_block( $puzzle->{'blocks'}[1], 'up' );
    $puzzle->dump();
    is( $puzzle->{'blocks'}[1]->is_home(),  1,  'moved block 1 to goal' );
    is( $puzzle->{'score'},                 3,  'score' );
    is( $puzzle->{'top_score'},             3,  'top score' );
    is( $puzzle->is_solved(),               1,  'solved' );


    }

__DATA__

#####
#*@ #
#####

#####
# + #
#$$ #
#.  #
#####

####
#. #
# ##
#  #
#$ #
#@ #
####

#####
# + #
##$##
#   #
#   #
#   #
#####

  ####
###  #
#  $ #
# ## #
#   .#
#  @ #
#    #
######
