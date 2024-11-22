package main
import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strings"
import "core:unicode/utf8"
import rl "vendor:raylib"

DEBUG_MEMORY :: true

/* Data Layout
Dungeon consists of multiple Floors, each Floor is a 2D grid of Tiles plus some central registry info.
Tiles have 4 Edges (not shared with adjacent tiles, to handle one way walls/doors easily by having adjacent edges differ) plus a pseudo Edge for the tile itself.
Edges have a type and an event (trap, message, encounter, etc). The event has an argument (lock id, destination, encounter id, etc).
The Tile's pseudo Edge can have upto 3 events. The 4 Edges can have only 1 event.
The Floor has a central registry of Locks, Encounters, Messages, etc and their state (open/closed, triggered, etc)

Parse format
Edge: {event_type} {edge_type} {event_arg}
Tile:
    {???} {event_type1} {event_arg1}
    {???} {event_type2} {event_arg2}
    {???} {event_type3} {event_arg3}
FUTURE Tile:
    {event_type1} {???} {event_arg1}
    {event_type2} {tile_type} {event_arg2}
    {event_type3} {???} {event_arg3}

Known Issues
    - Parse tables default to nil, so unrecognized characters in map data are a silent failure
    - Code assumes right hand coordinate system, so foward is neg-Z. Unsure if easy to use left hand instead?
*/

Error :: enum {
    None,
    LoadMapRead,
    LoadMapDimensions,
}

EventArg :: rune

EventType :: union #shared_nil {
    TrapType,
    MessageType,
    EncounterType,
    TreasureType,
}
MessageType :: enum {
    None,
    WarningForTrapAhead,
}
TrapType :: enum {
    None,
    Spinner,
    Teleport,
    Pit,
    Zap,
    DispelMagic,
}
EncounterType :: enum {
    None,
    Encounter, // based on arg
    RandomEasy,
    RandomMedium,
    RandomHard,
    FireDragon,
    Werdna,
}
TreasureType :: enum {
    None,
    Treasure, // based on arg
}
EdgeType :: enum {
    Open,
    Wall,
    Door,
    FalseWall, // appears as Wall but acts as Open. once revealed appears as FalseWall
    InvisibleWall, // appears as Open but acts as Wall. once revealed appears as InvisibleWall
    SecretDoor, // appears and acts as Wall. once revealed appears as SecretDoor and acts as Door
    Button,
}
Event :: struct {
    type: EventType,
    arg: EventArg,
    completed: b8,
}
Edge :: struct {
    type: EdgeType,
    event: Event, // event triggered by walking into, through, or activating edge
    lockid: EventArg, // lock id for door, button, etc
    revealed: b8, // FalseWall, InvisibleWall, SecretDoor handled differently when revealed. Trap still triggered but displayed
}
Tile :: struct {
    edges: [Direction]Edge,
    events: [3]Event, // events triggered by entering tile
    // tile properties
    is_darkness: b8,
    is_antimagic: b8,
}
Direction :: enum {
    North,
    East,
    South,
    West,
}
Floor :: struct {
    tiles: [20][20]Tile,
    width: int,
    height: int,

    // central registry
    locks: [256]b8,
    // messages, coordinates, encounters, etc
}
Assets :: struct {
    edges: [EdgeType]rl.Texture2D,
    floor: rl.Texture2D,
    ceiling: rl.Texture2D,
}

floor : Floor

ParserEdgeType : map[rune]EdgeType = {
    ' '= .Open,
    '-'= .Wall,
    '|'= .Wall,
    'D'= .Door,
    'F'= .FalseWall,
    'I'= .InvisibleWall,
    'S'= .SecretDoor,
    'B'= .Button,
}
ParserEventType : map[rune]EventType = {
    ' '= nil,
    'S'= .Spinner,
    'W'= .Teleport,
    'P'= .Pit,
    'Z'= .Zap,
    'M'= .DispelMagic,

    'T'= .Treasure,
    
    'E'= .Encounter,
    'e'= .RandomEasy,
    'm'= .RandomMedium,
    'h'= .RandomHard,
    'f'= .FireDragon,
    'w'= .Werdna,
}
parse_tile :: proc( lines: []string, x, y: int ) -> (tile: Tile) {
    // Extract text data to intermediate struct to make things easier
    TileRaw :: struct {
        edges: [Direction][3]rune,
        center: [9]rune,
    }
    raw : TileRaw
    H := floor.height -1
    for i in 0..<3 {
        raw.edges[.North][i] = utf8.rune_at_pos( lines[ (H-y)*5 +0   ], x*5 +1+i )
        raw.edges[.South][i] = utf8.rune_at_pos( lines[ (H-y)*5 +4   ], x*5 +1+i )
        raw.edges[.West][i]  = utf8.rune_at_pos( lines[ (H-y)*5 +1+i ], x*5 +0   )
        raw.edges[.East][i]  = utf8.rune_at_pos( lines[ (H-y)*5 +1+i ], x*5 +4   )
    }
    for i in 0..<9 {
        raw.center[i] = utf8.rune_at_pos( lines[ (H-y)*5+1 +i/3 ], x*5+1 +i%3 )
    }

    // From intermediate, transform to Tile struct
    //TODO handle event args properly. often needs to leverage legend lookup
    for dir in Direction {
        tile.edges[dir] = Edge{
            type= ParserEdgeType[ raw.edges[dir][1] ],
            event= Event{
                type= ParserEventType[ raw.edges[dir][0] ],
                arg= EventArg( raw.edges[dir][2] ),
            },
        }
    }
    for i in 0..<3 {
        tile.events[i] = Event{
            type= ParserEventType[ raw.center[i*3 +1] ], // tile uses middle char for event type right now
            arg= EventArg( raw.center[i*3 +2] ),
        }
    }
    //fmt.printfln( "Raw: %v", raw )
    return
}

load_map :: proc( debug:bool = false ) -> Error {
    data, ok := os.read_entire_file( "../res/separate_edges.map" )
    if !ok { return .LoadMapRead }
    defer { delete( data ) }

    lines := strings.split( string(data), "\n" )
    defer { delete(lines) }

    // Determine and verify dimensions of map data. Map data and legend are split by an empty line
    num_lines := 0
    for line in lines {
        if line == "" { break }
        num_lines += 1
    }

    if num_lines < 5 { return .LoadMapDimensions }
    num_cols := len( lines[0] )
    if num_lines % 5 != 0 || num_cols % 5 != 0 { return .LoadMapDimensions }

    floor.width, floor.height = num_cols/5, num_lines/5

    if debug {
        fmt.printfln( "Map data size: %v x %v", num_cols, num_lines )
        fmt.printfln( "Map size: %v x %v", floor.width, floor.height )
        tile := parse_tile( lines, 7, 7 )
        fmt.printfln( "Tile: %v", tile )
    }

    //TODO handle legend's event arg data and leverage in tile parser
    // Parse post-map legend data
    if debug {
        fmt.printfln( "Legend" )
        for line in lines[num_lines+1:] {
            fmt.printfln( "    %v", line )
        }
    }

    // Parse individual map tiles
    for y in 0..<floor.height {
        for x in 0..<floor.width {
            floor.tiles[x][y] = parse_tile( lines, x, y )
        }
    }

    return .None
}

main :: proc() {
    when DEBUG_MEMORY {
        tracking_allocator : mem.Tracking_Allocator
        mem.tracking_allocator_init( &tracking_allocator, context.allocator )
        context.allocator = mem.tracking_allocator( &tracking_allocator )

        print_alloc_stats := proc( tracking: ^mem.Tracking_Allocator ) {
            for _, entry in tracking.allocation_map {
                fmt.printfln( "%v: Leaked %v bytes", entry.location, entry.size )
            }
            for entry in tracking.bad_free_array {
                fmt.printfln( "%v: Bad free @ %v", entry.location, entry.memory )
            }
        }
        defer { print_alloc_stats( &tracking_allocator ) }
    }

    fmt.printfln( "[MEM] Floor: %.1f kb", size_of( floor )/1024.0 )

    if err := load_map(true); err != nil {
        fmt.printfln( "Error loading map: %v", err )
        return
    }
    //for y in 0..<floor.height {
    for y := floor.height-1; y >= 0; y -=1 {
        for x in 0..<floor.width {
            fmt.printf( "%v ", floor.tiles[x][y].events[1].type )
            //fmt.printf( "%d,%d ", x, y )
        }
        fmt.printf( "\n" )
    }
    fmt.printfln( "(7,1) %v", floor.tiles[7][1] )
    

    when true {
        //rl.SetConfigFlags( rl_window_bitflags )
        //rl.SetWindowSize( 3840-0, 2160-1 )
        //rl.SetWindowPosition( 0, 0 )
        rl.InitWindow( 1280, 720, "Crawl" )
        rl.SetTargetFPS( 120 )
        rl.DisableCursor()

        player_pos := [2]int{ 0, 0 }
        scale :f32 = 1.0

        camera : rl.Camera3D
        camera.position = {0,scale/2,0}
        camera.target = {0,scale/2,-5}
        camera.up = {0,1,0}
        camera.fovy = 60
        camera.projection = .PERSPECTIVE

        player_can_move := true
        camera_can_fly := false
        camera_can_rotate := true
        camera_can_zoom := true

        for !rl.WindowShouldClose() {
            dt := rl.GetFrameTime()

            if rl.IsKeyPressed( .GRAVE ) {
                if player_can_move {
                    player_can_move = false
                    camera_can_fly = true
                } else {
                    player_can_move = true
                    camera_can_fly = false
                }
            }

            if player_can_move {
                if rl.IsKeyPressed( .W ) { player_pos.y += 1 }
                if rl.IsKeyPressed( .S ) { player_pos.y -= 1 }
                if rl.IsKeyPressed( .A ) { player_pos.x -= 1 }
                if rl.IsKeyPressed( .D ) { player_pos.x += 1 }
                if player_pos.x < 0 { player_pos.x = 0 }
                if player_pos.y < 0 { player_pos.y = 0 }
                if player_pos.x > (floor.width-1) { player_pos.x = (floor.width-1) }
                if player_pos.y > (floor.height-1) { player_pos.y = (floor.height-1) }
            }

            camera_rotate : rl.Vector3 = { rl.GetMouseDelta().x*0.5, rl.GetMouseDelta().y*0.5, 0 } if camera_can_rotate else {}
            camera_zoom : f32 = rl.GetMouseWheelMove()*-2.0 if camera_can_zoom else 0.0
            camera_movement : rl.Vector3 = {
                (rl.IsKeyDown(.W) ? 0.1 : 0.0) - (rl.IsKeyDown(.S) ? 0.1 : 0.0),
                (rl.IsKeyDown(.D) ? 0.1 : 0.0) - (rl.IsKeyDown(.A) ? 0.1 : 0.0),
                (rl.IsKeyDown(.Q) ? 0.1 : 0.0) - (rl.IsKeyDown(.E) ? 0.1 : 0.0)
                } if camera_can_fly else {}
            rl.UpdateCameraPro( &camera, camera_movement, camera_rotate, camera_zoom )

            if rl.IsKeyPressed( .R ) || player_can_move && (rl.IsKeyPressed( .W ) || rl.IsKeyPressed( .S ) || rl.IsKeyPressed( .A ) || rl.IsKeyPressed( .D )) {
                camera.position = { f32(player_pos.x), 0.5, f32(-player_pos.y) } * scale
                camera.target = camera.position + {0,0,-0.5}*scale
            }

            rl.BeginDrawing()
                rl.ClearBackground( rl.RAYWHITE )
                
            rl.BeginMode3D( camera )
                rl.DrawGrid( 20, 1.0 )

                for y := floor.height-1; y >= 0; y -=1 {
                    for x in 0..<floor.width {
                        tile := floor.tiles[x][y]
                        pos := rl.Vector3{ f32(x), 0, f32(-y) } *scale
                        size := rl.Vector3{1,2,1} * scale
                        rl.DrawCubeWires( pos, size.x, size.y, size.z, rl.GREEN )
                        //rl.DrawCube( pos, size.x, size.y, size.z, rl.GREEN )
                    }
                }
            rl.EndMode3D()
                rl.DrawText( rl.TextFormat( "FPS: %5.1f Map |%d,%d|", 1.0/dt, floor.width, floor.height ), 10, 10, 20, rl.MAROON )
                rl.DrawText( rl.TextFormat( "%v", camera ), 10, 40, 20, rl.MAROON )
                rl.DrawText( rl.TextFormat( "Player %v Can move %v", player_pos, player_can_move ), 10, 70, 20, rl.MAROON )
            rl.EndDrawing()
        }
    }
}