#!/usr/bin/python

SHARED_EDGE = False
path = 'res/shared_edges.map' if SHARED_EDGE else 'res/separate_edges.map'

buf = open( path, 'r' ).read()
lines = buf.split('\n')

num_lines = len( lines )
num_cols = len( lines[0] )
print( f'Map data size: {num_lines}x{num_cols}' )

if SHARED_EDGE:
    map_height = (num_lines -1) // 4
    map_width = (num_cols -1) // 4
else:
    map_height = num_lines // 5
    map_width = num_cols // 5

print( f'Map size: {map_height}x{map_width}' )

# parse data in natural read order
if 0:
    x, y = 0, 0
    row = 0
    for line in lines:
        col = 0
        for c in line:
            x, y = row//5, col//5
            print( f'({x},{y}) ', end='' )
            col += 1
        row += 1
        print()

# parse data by tile
if 0:
    for y in range( map_height ):
        for x in range( map_width ):
            print( f'({x},{y}) ', end='' )
            north = lines[ y*5 ][ x*5 : x*5+5 ]
            print( north )
            break
        print()
        break

def parse_tile( x, y ):
    north = lines[ y*5+0 ][ x*5+1 : x*5+4 ]
    south = lines[ y*5+4 ][ x*5+1 : x*5+4 ]
    west = ''.join( lines[ y*5+1 +i ][ x*5+0 ] for i in range(3) )
    east = ''.join( lines[ y*5+1 +i ][ x*5+4 ] for i in range(3) )
    tile9 = ''.join( lines[ y*5+1 +row ][ x*5+1 : x*5+4 ] for row in range(3) )

    tile = tile9.strip() or '.'
    if 'W' in tile:
        wx = tile.split('W')[0].strip()
        wy = tile.split('W')[1].strip()
        tile = f'{wx}W{wy}'
        tile = 'W'
    #print( 'N', north )
    #print( 'S', south )
    #print( 'W', west )
    #print( 'E', east )
    #print( f'tile [{tile}]' )
    #print( tile )
    #disp = f'{x},{y}={tile} '
    print( tile, end='' )

#parse_tile( 7, 7 )

for y in range( map_height ):
    for x in range( map_width ):
        parse_tile( x, y )
    print()