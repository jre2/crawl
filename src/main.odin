package main
import "core:fmt"
import "core:mem"
import "core:os"
import "core:reflect"
import "core:strings"
import "core:unicode/utf8"
import rl "vendor:raylib"
import gl "vendor:raylib/rlgl"

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
*/

DEBUG_MEMORY :: true
DISABLE_TEXTURES :: false
MAX_FLOOR_WIDTH :: 20
MAX_FLOOR_HEIGHT :: 20
MAX_NUM_LOCKS :: 256

Vec3 :: [3]f32
Vec2 :: [2]int
EventArg :: rune

Error :: enum {
    None,
    LoadMapRead,
    LoadMapDimensions,
}
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
DirectionNormal : [Direction]Vec3 = {
    .North= {0,0,-1},
    .East= {+1,0,0},
    .South= {0,0,+1},
    .West= {-1,0,0},
}
Floor :: struct {
    tiles: [MAX_FLOOR_WIDTH][MAX_FLOOR_HEIGHT]Tile,
    width: int,
    height: int,

    // central registry
    locks: [MAX_NUM_LOCKS]b8,
    // messages, coordinates, encounters, etc
}
Assets :: struct {
    edges: [EdgeType]rl.Texture2D,
    floor: rl.Texture2D,
    ceiling: rl.Texture2D,
}
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
floor : Floor
assets : Assets

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

draw_quad :: proc( pos, size, rot:Vec3, rot_angle:f32, normal :Vec3, texture:rl.Texture, tint :rl.Color ) {
    tint := rl.PINK if DISABLE_TEXTURES else tint
    gl.PushMatrix()
        gl.Translatef( pos.x, pos.y, pos.z )
        gl.Rotatef( rot_angle, rot.x, rot.y, rot.z )
        gl.Scalef( size.x, size.y, size.z )

        if !DISABLE_TEXTURES { gl.SetTexture( texture.id ) }
        gl.Begin( gl.QUADS )
            gl.Color4ub( tint.r, tint.g, tint.b, tint.a )
            gl.Normal3f( normal.x, normal.y, normal.z )
            // Determine which winding order to use based on normal
            if normal.z < 0 || normal.x < 0 {
                // Clockwide winding order; lower left, lower right, upper right, upper left
                gl.TexCoord2f( 0, 0 ); gl.Vertex3f( -0.5, -0.5, 0 )
                gl.TexCoord2f( 1, 0 ); gl.Vertex3f( +0.5, -0.5, 0 )
                gl.TexCoord2f( 1, 1 ); gl.Vertex3f( +0.5, +0.5, 0 )
                gl.TexCoord2f( 0, 1 ); gl.Vertex3f( -0.5, +0.5, 0 )
            } else {
                // Counter-clockwise winding order; bottom right, bottom left, top left, top right
                gl.TexCoord2f( 1, 0 ); gl.Vertex3f( +0.5, -0.5, 0 )
                gl.TexCoord2f( 0, 0 ); gl.Vertex3f( -0.5, -0.5, 0 )
                gl.TexCoord2f( 0, 1 ); gl.Vertex3f( -0.5, +0.5, 0 )
                gl.TexCoord2f( 1, 1 ); gl.Vertex3f( +0.5, +0.5, 0 )
            }
        gl.End()
        gl.SetTexture( 0 )
    gl.PopMatrix()
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

    // Load and prepare game data
    fmt.printfln( "[MEM] Floor: %.1f kb", size_of( floor )/1024.0 )

    if err := load_map(false); err != nil {
        panic( fmt.aprint("Error loading map %v", reflect.enum_name_from_value(err) ) )
    }

    // Create game window
    rl.SetConfigFlags( {.WINDOW_HIGHDPI, .MSAA_4X_HINT} )
    rl.InitWindow( 1920, 1080, "Crawl" )
    //rl.SetWindowSize( 3840-0, 2160-1 )
    //rl.SetWindowPosition( 0, 0 )
    rl.SetTargetFPS( 120 )
    rl.DisableCursor()

    // Prepare assets
    scale :f32 = 1.0
    tile_size :Vec3 = {1.0,2.0,1.0} * scale
    edge_size :Vec3 = tile_size * {1,1,1}
    assets.edges[.Wall] = rl.LoadTexture( "../res/wall.png" )

    // Initialize player, camera, and movement settings
    player_pos := Vec2{ 0, 0 }
    player_can_move := false
    camera_can_fly := true
    camera_can_rotate := true
    camera_can_zoom := true
    camera_speed_move : f32 = 10
    camera_speed_rotate : f32 = 50.0

    camera : rl.Camera3D
    camera.position = {0,scale*0.5,0}
    camera.target = {0,scale*0.5,-5}
    camera.up = {0,1,0}
    camera.fovy = 90
    camera.projection = .PERSPECTIVE

    for !rl.WindowShouldClose() {
        dt := rl.GetFrameTime()
        num_things := 0
        { // Input, movement, camera
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
            camera_rotate : Vec3 = { rl.GetMouseDelta().x, rl.GetMouseDelta().y, 0 } *dt*camera_speed_rotate if camera_can_rotate else {}
            camera_zoom : f32 = rl.GetMouseWheelMove()*-2.0 if camera_can_zoom else 0.0
            camera_movement : Vec3 = {
                (rl.IsKeyDown(.W) ? 1 : 0) - (rl.IsKeyDown(.S) ? 1 : 0),
                (rl.IsKeyDown(.D) ? 1 : 0) - (rl.IsKeyDown(.A) ? 1 : 0),
                (rl.IsKeyDown(.Q) ? 1 : 0) - (rl.IsKeyDown(.E) ? 1 : 0),
                } * dt*camera_speed_move if camera_can_fly else {}
            rl.UpdateCameraPro( &camera, camera_movement, camera_rotate, camera_zoom )

            if rl.IsKeyPressed( .R ) || player_can_move && (rl.IsKeyPressed( .W ) || rl.IsKeyPressed( .S ) || rl.IsKeyPressed( .A ) || rl.IsKeyPressed( .D )) {
                camera.position = { f32(player_pos.x), 0.5, f32(-player_pos.y) } * scale
                camera.target = camera.position + {0,0,-0.5}*scale
            }
        }

        rl.BeginDrawing() // Render map
            rl.ClearBackground( rl.RAYWHITE )
            rl.BeginMode3D( camera )
                for y in 0..<floor.height {
                    for x in 0..<floor.width {
                        tile := floor.tiles[x][y]
                        for dir in Direction {
                            edge := tile.edges[dir]
                            if edge.type == .Open { continue }

                            edge_pos :Vec3 = ( {f32(x),0,f32(-y)} + 0.5*DirectionNormal[dir] ) * scale
                            edge_rot_angle :f32 = 0 if dir == .North || dir == .South else 90
                            edge_rot_axis := Vec3{0,1,0}

                            // Texture based on edge type and whether true nature has been revealed
                            texture := assets.edges[ .Wall ]
                            draw_quad( edge_pos, edge_size, edge_rot_axis, edge_rot_angle, DirectionNormal[dir], texture, rl.WHITE )
                        }
                    }
                }
            rl.EndMode3D()
            rl.DrawText( rl.TextFormat( "FPS: %5.1f Map |%d,%d|", 1.0/dt, floor.width, floor.height ), 10, 10, 20, rl.MAROON )
            rl.DrawText( rl.TextFormat( "%v", camera ), 10, 40, 20, rl.MAROON )
            rl.DrawText( rl.TextFormat( "Player %v, Move? %v, Things %v", player_pos, player_can_move, num_things ), 10, 70, 20, rl.MAROON )
        rl.EndDrawing()
    }
}