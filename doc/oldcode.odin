/*
	
	buffercstring := cstring( buffer )
	bufferstring := strings.string_from_ptr( buffer, 256 )
	*/
	//fmt.printfln( "Buffer: '%s'", buffercstring )
	//delete_cstring( buffer )
	
	//foo : [256]u8
	//foo = raw_data( string( "foobar" ) )
	//bar : string
	//bar = "foobar"
	//foo : [256]u8 = cstring( "foobar" )
	
	when false { // wrong
		buffer := make( [^]u8, 256 )
		buffer = transmute([^]u8) cstring("foobar")
		rl.GuiTextBox( rl.Rectangle{ 100, 550, 100, 40 }, cstring(buffer), 256, true )
	}
	when false { // with slice
		buffer := make( []u8, 256 )
		fmt.bprint( buffer, "foobar" )
		rl.GuiTextBox( rl.Rectangle{ 100, 550, 100, 40 }, cstring( raw_data(buffer) ), 256, true )
	}
	when false { // with fixed array
		//buffer : [256]u8
		//fmt.bprint( buffer[:], "foobar" )
		//rl.GuiTextBox( rl.Rectangle{ 100, 550, 100, 40 }, cstring( &buffer[0] ), 256, true )
	}
	//rl.GuiTextBox( rl.Rectangle{ 100, 550, 100, 40 }, cstring( &st.navpoints_map[0] ), NAVPOINT_MAPNAME_MAX_LEN, true )
	rl.GuiCheckBox( rl.Rectangle{ 50, 100, 20, 20 }, "Recording", &st.nav_recording )
	//if drop_editing { rl.GuiLock() }
	//rl.GuiUnlock()
	/*
	rl.GuiSpinner( rl.Rectangle{ 100, 200, 100, 40 }, "Quest Step", &quest_step, 1, 100, false )
	//slider
	rl.GuiTextBox( rl.Rectangle{ 100, 550, 100, 40 }, cstring( &text_buffer[0] ), len(text_buffer), true )
	rl.GuiComboBox( rl.Rectangle{ 100, 600, 100, 40 }, "All files", &combo_active )
	rl.GuiUnlock()
	if rl.GuiDropdownBox( rl.Rectangle{ 400, 600, 100, 40 }, "boxrun;ch2_pw3;ch2_pw4", &drop_selection, drop_editing ) { drop_editing = !drop_editing }
	*/
	// Display last frame error, if applicable. Do this first in case we error out



	//draw_text( st^, .TOP_LEFT, {0,20}, "Map %s [%d] + %v", strings.unsafe_string_to_cstring(string( st.navpoints_map[:] )), len(st.navpoints), new_navpoint )
	//draw_text( st^, .TOP_LEFT, {0,20}, "Map %s [%d] + %v", st.navpoints_map[:len(st.navpoints_map)-2], len(st.navpoints), new_navpoint )
	//fmt.printfln( "Map name %s size %d", st.navpoints_map, len(st.navpoints) )
	//fmt.println( rl.TextFormat( "Map name %s size %d", cstring("teststring\x00"), len(st.navpoints) ) )
	
	
		/*
	//text := rl.TextFormat( "start %s end", strings.unsafe_string_to_cstring(string( st.navpoints_map[:] )) )
	//text := rl.TextFormat( "start %s end", raw_data( st.navpoints_map[:] ) )
	//text := rl.TextFormat( "start %s end", cstring( &st.navpoints_map[0] ) )
	text := rl.TextFormat( "start %s end", cstring( &st.navpoints_map[0] ) )
	fmt.println( text )
	*/	

	when false {
		buffer : [256]byte
		copy( buffer[:], "hellope" )
		text := rl.TextFormat( "2 %s 3", buffer )
		fmt.printfln( "1 %s 4", text )
		// 1 2 hellope 4
	}
	when false {
		buffer : [256]byte
		copy( buffer[:], "hellope" )
		text := rl.TextFormat( "2 %s 3", cstring( &buffer[0] ) )
		fmt.printfln( "1 %s 4", text )
		// 1 2 hellope 3 4
	}
	when true {
		buffer : [256]byte
		copy( buffer[:], "hellope" )
		cbuffer := cstring( &buffer[0] )
		cap_of_buffer := cap(buffer)
		len_of_buffer := len(cbuffer)
		sbuffer := slice.bytes_from_ptr( cast(^u8) cbuffer, cap(buffer) )
		fmt.bprintf( sbuffer, "hello world" )

		text := rl.TextFormat( "2 %s 3", cbuffer )
		fmt.printfln( "1 %s 4", text )
		// 1 2 hellope 3 4
	}
	
	foo : cstring = cstring( make( [^]byte, 256 ) )
	fmt.bprintf( slice.bytes_from_ptr( rawptr( foo ), 256 ), "Hello, World!" )








//main_overlay()cast(win32.LPARAM) 
	fmt.printfln( "START Input simulation tests start" )
	
	// acquire handle to PSOBB window, ie hWnd
	fooA : cstring = "Ephinea: Phantasy Star Online Blue Burst"
	hwndA := win32.FindWindowA( nil, fooA )

	//hwnd = win32.FindWindowA( nil, "Ephinea: Phantasy Star Online Blue Burst" )
	hwnd := hwndA

	key := 'W' // for special keys, use win32.VK_{foo}. 
	vk := u32( key ) // consider VkKeyScanEx for more complex keys
	scan := u32( win32.MapVirtualKeyW( vk, win32.MAPVK_VK_TO_VSC ) )
	repeat : u32 = 1
	extended : u32 = 0
	fmt.printfln( "hWnd %v (%d) key %q vk 0x%X scan 0x%X", hwnd, hwnd, key, vk, scan )

	lparam_down : u32 = ( (scan << 16) + ( repeat << 0 ) ) // scan @ 16, repeat count @ 0
	//lparam_down := cast(win32.LPARAM) ( (scan << 16) + ( 1 << 0 ) ) // scan @ 16, repeat count @ 0
	lparam_up : u32 = ( (1 << 31) + ( 1 << 30 ) + lparam_down ) // transition state @ 31, prev key state @ 30

	/* How native inputs are handled
	W (forward): lParam
		0x00 11 00 01	down- first press (0<<31 + 0<<30)
		0x40 11 00 01	down- holding down (0<<31 + 1<<30)
		0xC0 11 00 01	up- release (1<<31 + 1<<30)
	*/

	fmt.printfln( "PostMessage hwnd 0x%X msg 0x%x wParam 0x%X lParam_down 0x%x lParam_up 0x%X", hwnd, win32.WM_KEYDOWN, vk, lparam_down, lparam_up )
	fmt.printfln( "PostMessage hwnd 0x%X msg 0x%x wParam %q lParam_down %q lParam_up %q", hwnd, win32.WM_KEYDOWN, cast(win32.WPARAM) vk, cast(win32.LPARAM) lparam_down, cast(win32.LPARAM) lparam_up )
	when false { // Switch focus to window, send key, then switch focus back
		prev_foreground_hwnd := win32.GetForegroundWindow()
		prev_active_hwnd := win32.GetActiveWindow()
		fmt.printfln( "Changing focus from 0x%X to 0x%X", prev_foreground_hwnd, hwnd )
		win32.SetForegroundWindow( hwnd )
		win32.SetActiveWindow( hwnd )
		time.sleep( time.Millisecond * 40 )
		fmt.printfln( "Changing focus back from 0x%X to 0x%X", hwnd, prev_foreground_hwnd )
		win32.SetForegroundWindow( prev_foreground_hwnd )
		win32.SetActiveWindow( prev_active_hwnd )
		fmt.printfln( "Done" )
	}
	when false { // PostMessage
		time.sleep( time.Second * 1 )
		fmt.printfln( "sending key via PostMessage" )

		retDown := win32.PostMessageA( hwnd, win32.WM_KEYDOWN, cast(win32.WPARAM) vk, cast(win32.LPARAM) lparam_down )
		time.sleep( time.Millisecond * 40 )
		retUp := win32.PostMessageA( hwnd, win32.WM_KEYUP, cast(win32.WPARAM) vk, cast(win32.LPARAM) lparam_up )
		fmt.printfln( "PostMessage down %v up %v", retDown, retUp )
	}
	when false { // SendMessage
		time.sleep( time.Second * 1 )
		fmt.printfln( "sending key via PostMessage" )

		win32.SendMessageW( hwnd, win32.WM_KEYDOWN, cast(win32.WPARAM) vk, cast(win32.LPARAM) lparam_down )
		time.sleep( time.Millisecond * 40 ) 
		win32.SendMessageW( hwnd, win32.WM_KEYDOWN, cast(win32.WPARAM) vk, cast(win32.LPARAM) lparam_up )
	}
	when false { // keydb_event
		time.sleep( time.Second * 1 )
		fmt.printfln( "sending key via keybd" )

		// Note, we can leave scan code as 0 and windows will usually figure it out, but specifying it seems to work better with legacy games		
		fmt.printfln( "Key VK_RETURN, VK 0x%X, scan 0x%X", vk, scan )
		keybd_event( cast(u8) vk, cast(u8) scan, 0, 0 ) // down
		// if we release too soon, the game doesn't detect the down press
		// 1ms is too short, 2ms seems sufficient. no release at all seems to work? unsure if that will cause issues
		time.sleep( time.Millisecond * 40 )
		keybd_event( cast(u8) vk, cast(u8) scan, 0x2, 0 ) // up
	}

	fmt.printfln( "END" )
	
	
//Spy++ C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools

nav_find_neighbors_cast_out :: proc( graph: NavGraph, origin: NavGraphNode, search_radius: f32 ) -> (neighbors: NavGraphNeighbors) {
	// cast out a search epicenter in each direction, then search around said epicenter for the nearest point to our origin that's on graph and within the epicenter radius
	for direction in Direction {
		offset := DirectionVectors[direction] * i16(search_radius*2)
		epicenter := origin + offset
		nearest_navpoint := origin // default to self if no valid neighbor
		nearest_dist : f32 = math.F32_MAX
		// now find points near the epicenter. for now we'll implement as a loop over all points and culls those outside search radius
		// this approach has great cache locality and is actually fewer checks than a naive epicenter grid search for radius > 24
		for navpoint in graph {
			dist_to_epicenter := nav_vector3i_distance( epicenter, navpoint )
			dist_to_origin := nav_vector3i_distance( origin, navpoint )
			if dist_to_epicenter <= search_radius && dist_to_origin < nearest_dist && navpoint != origin {
				nearest_dist = dist_to_origin
				nearest_navpoint = navpoint
			}
		}
		neighbors[direction] = nearest_navpoint
	}
	return
}

nav_check_on_graph :: proc( graph: NavGraph, navpoint: NavGraphNode ) -> bool {
	return navpoint in graph
}