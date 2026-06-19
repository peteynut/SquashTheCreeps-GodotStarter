extends Node

@export var mob_scene: PackedScene
@export var player_scene: PackedScene

const PORT = 7777
const MAX_PEERS = 4

var _players: Dictionary = {}      # peer_id -> Node
var _scores: Dictionary = {}       # peer_id -> int
var _eliminated: Dictionary = {}   # peer_id -> bool
var _player_labels: Dictionary = {} # peer_id -> "P1", "P2", ...
var _mob_counter: int = 0
var _game_time := 0.0
var _font: FontFile
var _leaderboard_rows: VBoxContainer
var _game_over_scores_box: VBoxContainer
var _game_over_center: Control
var _game_over_panel: Control
var _restart_btn: Button
var _ui_canvas: CanvasLayer
var _in_game := false
var _music_volume: float = 0.0
var _music_tween: Tween
var _in_lobby := false
var _ready_players: Dictionary = {}   # peer_id -> bool (clients only)
var _lobby_center: Control
var _lobby_panel: Control
var _lobby_player_list: VBoxContainer
var _lobby_status: Label
var _lobby_action_btn: Button

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_ui()
	_setup_hud()
	if not InputMap.has_action("menu"):
		InputMap.add_action("menu")
		var key := InputEventKey.new()
		key.keycode = KEY_ESCAPE
		InputMap.action_add_event("menu", key)
		var btn := InputEventJoypadButton.new()
		btn.button_index = 6  # Start / Options on most controllers
		InputMap.action_add_event("menu", btn)
	if not InputMap.has_action("lobby_confirm"):
		InputMap.add_action("lobby_confirm")
		var enter_key := InputEventKey.new()
		enter_key.keycode = KEY_ENTER
		InputMap.action_add_event("lobby_confirm", enter_key)
		var kp_key := InputEventKey.new()
		kp_key.keycode = KEY_KP_ENTER
		InputMap.action_add_event("lobby_confirm", kp_key)
		var space_key := InputEventKey.new()
		space_key.keycode = KEY_SPACE
		InputMap.action_add_event("lobby_confirm", space_key)
		var a_btn := InputEventJoypadButton.new()
		a_btn.button_index = 0  # A / Cross button
		InputMap.action_add_event("lobby_confirm", a_btn)
	# Ground is on layer 3. Player detects layer 3 for IsOnFloor().
	# Mobs detect layer 3 for ground, but player is on layer 3 so no collision.
	$Ground.set_collision_layer_value(1, false)
	$Ground.set_collision_layer_value(3, true)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	_music_volume = $AudioStreamPlayer.volume_db

func _setup_ui() -> void:
	_ui_canvas = CanvasLayer.new()
	_ui_canvas.name = "UI"
	_ui_canvas.layer = 1
	add_child(_ui_canvas)

	var menu_center := CenterContainer.new()
	menu_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui_canvas.add_child(menu_center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	menu_center.add_child(vbox)

	var ip_input := LineEdit.new()
	ip_input.name = "IPInput"
	ip_input.placeholder_text = "IP Address"
	ip_input.text = "127.0.0.1"
	ip_input.custom_minimum_size = Vector2(200, 0)
	vbox.add_child(ip_input)

	var port_input := LineEdit.new()
	port_input.name = "PortInput"
	port_input.placeholder_text = "Port"
	port_input.text = str(PORT)
	port_input.custom_minimum_size = Vector2(200, 0)
	vbox.add_child(port_input)

	var host_btn := Button.new()
	host_btn.text = "Host"
	host_btn.pressed.connect(_host_game.bind(port_input))
	vbox.add_child(host_btn)

	var join_btn := Button.new()
	join_btn.text = "Join"
	join_btn.pressed.connect(_join_game.bind(ip_input, port_input))
	vbox.add_child(join_btn)

	var quit_btn := Button.new()
	quit_btn.text = "Quit Game"
	quit_btn.pressed.connect(get_tree().quit)
	vbox.add_child(quit_btn)

func _setup_hud() -> void:
	_font = load("res://fonts/Montserrat-Medium.ttf")

	var hud := CanvasLayer.new()
	hud.name = "HUD"
	hud.layer = 2
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(hud)

	# --- Live leaderboard (top-right) ---
	var lb_bg := PanelContainer.new()
	var lb_style := StyleBoxFlat.new()
	lb_style.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	lb_style.set_corner_radius_all(8)
	lb_bg.add_theme_stylebox_override("panel", lb_style)
	lb_bg.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	lb_bg.position = Vector2(-200, 16)
	lb_bg.custom_minimum_size = Vector2(184, 0)
	hud.add_child(lb_bg)

	var lb_vbox := VBoxContainer.new()
	lb_vbox.add_theme_constant_override("separation", 4)
	lb_bg.add_child(lb_vbox)

	var lb_title := Label.new()
	lb_title.text = "SCORES"
	lb_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb_title.add_theme_font_override("font", _font)
	lb_title.add_theme_font_size_override("font_size", 13)
	lb_title.modulate = Color(0.8, 0.8, 0.8)
	lb_vbox.add_child(lb_title)

	var lb_sep := HSeparator.new()
	lb_vbox.add_child(lb_sep)

	_leaderboard_rows = VBoxContainer.new()
	_leaderboard_rows.add_theme_constant_override("separation", 2)
	lb_vbox.add_child(_leaderboard_rows)

	# --- Lobby panel (center) ---
	_lobby_center = CenterContainer.new()
	_lobby_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lobby_center.visible = false
	_lobby_center.process_mode = Node.PROCESS_MODE_ALWAYS
	hud.add_child(_lobby_center)

	_lobby_panel = PanelContainer.new()
	_lobby_panel.name = "LobbyPanel"
	_lobby_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_lobby_center.add_child(_lobby_panel)

	var lobby_vbox := VBoxContainer.new()
	lobby_vbox.custom_minimum_size = Vector2(340, 0)
	lobby_vbox.add_theme_constant_override("separation", 10)
	_lobby_panel.add_child(lobby_vbox)

	var lobby_title := Label.new()
	lobby_title.text = "LOBBY"
	lobby_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lobby_title.add_theme_font_override("font", _font)
	lobby_title.add_theme_font_size_override("font_size", 36)
	lobby_vbox.add_child(lobby_title)

	lobby_vbox.add_child(HSeparator.new())

	_lobby_player_list = VBoxContainer.new()
	_lobby_player_list.add_theme_constant_override("separation", 8)
	lobby_vbox.add_child(_lobby_player_list)

	lobby_vbox.add_child(HSeparator.new())

	_lobby_status = Label.new()
	_lobby_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lobby_status.add_theme_font_override("font", _font)
	_lobby_status.add_theme_font_size_override("font_size", 15)
	_lobby_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lobby_status.custom_minimum_size = Vector2(300, 0)
	lobby_vbox.add_child(_lobby_status)

	_lobby_action_btn = Button.new()
	_lobby_action_btn.add_theme_font_size_override("font_size", 20)
	_lobby_action_btn.pressed.connect(_on_lobby_action_pressed)
	lobby_vbox.add_child(_lobby_action_btn)

	# --- Game over panel (center) ---
	_game_over_center = CenterContainer.new()
	_game_over_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_game_over_center.visible = false
	_game_over_center.process_mode = Node.PROCESS_MODE_ALWAYS
	hud.add_child(_game_over_center)

	_game_over_panel = PanelContainer.new()
	_game_over_panel.name = "GameOverPanel"
	_game_over_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_game_over_center.add_child(_game_over_panel)

	var panel_vbox := VBoxContainer.new()
	panel_vbox.custom_minimum_size = Vector2(320, 0)
	panel_vbox.add_theme_constant_override("separation", 8)
	_game_over_panel.add_child(panel_vbox)

	var over_label := Label.new()
	over_label.text = "Game Over"
	over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	over_label.add_theme_font_override("font", _font)
	over_label.add_theme_font_size_override("font_size", 48)
	panel_vbox.add_child(over_label)

	panel_vbox.add_child(HSeparator.new())

	_game_over_scores_box = VBoxContainer.new()
	_game_over_scores_box.add_theme_constant_override("separation", 4)
	panel_vbox.add_child(_game_over_scores_box)

	panel_vbox.add_child(HSeparator.new())

	_restart_btn = Button.new()
	_restart_btn.text = "Restart"
	_restart_btn.add_theme_font_size_override("font_size", 24)
	_restart_btn.pressed.connect(_on_restart_pressed)
	panel_vbox.add_child(_restart_btn)

	var quit_to_menu_btn := Button.new()
	quit_to_menu_btn.text = "Quit to Menu"
	quit_to_menu_btn.add_theme_font_size_override("font_size", 20)
	quit_to_menu_btn.pressed.connect(_quit_to_menu)
	panel_vbox.add_child(quit_to_menu_btn)

func _host_game(port_input: LineEdit) -> void:
	_ui_canvas.visible = false
	_in_game = true
	_in_lobby = true
	var port := int(port_input.text) if port_input.text.is_valid_int() else PORT
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PEERS)
	if err != OK:
		push_error("Failed to create server: %d" % err)
		_ui_canvas.visible = true
		_in_game = false
		_in_lobby = false
		return
	multiplayer.multiplayer_peer = peer
	_player_labels[multiplayer.get_unique_id()] = "P1"
	_lobby_center.visible = true
	_refresh_lobby_ui()

func _join_game(ip_input: LineEdit, port_input: LineEdit) -> void:
	_ui_canvas.visible = false
	_in_game = true
	_in_lobby = true
	var port := int(port_input.text) if port_input.text.is_valid_int() else PORT
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip_input.text, port)
	if err != OK:
		push_error("Failed to connect: %d" % err)
		_ui_canvas.visible = true
		_in_game = false
		return
	multiplayer.multiplayer_peer = peer

func _process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if multiplayer.is_server() and not _players.is_empty():
		_game_time += delta

func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	if _in_lobby:
		_ready_players[id] = false
		if id not in _player_labels:
			_player_labels[id] = "P%d" % (_player_labels.size() + 1)
		_sync_lobby.rpc(_ready_players, _player_labels)
	else:
		for existing_id in _players:
			_spawn_player.rpc_id(id, existing_id)
		_spawn_player.rpc(id)

func _on_peer_disconnected(id: int) -> void:
	if _in_lobby and multiplayer.is_server():
		_ready_players.erase(id)
		_player_labels.erase(id)
		_sync_lobby.rpc(_ready_players, _player_labels)
	if _players.has(id):
		_players[id].queue_free()
		_players.erase(id)

func _on_connected_to_server() -> void:
	_lobby_center.visible = true
	_lobby_status.text = "Connected — waiting for lobby info..."

func _on_connection_failed() -> void:
	push_error("Connection failed")

@rpc("authority", "call_local", "reliable")
func _spawn_player(peer_id: int) -> void:
	var player := player_scene.instantiate()
	player.name = str(peer_id)
	player.set_multiplayer_authority(peer_id)
	player.position = Vector3(_players.size() * 3.0 - 1.5, 0.5, 0.0)
	$Players.add_child(player)
	_players[peer_id] = player
	_scores[peer_id] = 0
	if peer_id not in _player_labels:
		_player_labels[peer_id] = "P%d" % (_player_labels.size() + 1)
	_refresh_score_display()

func _on_timer_timeout() -> void:
	if not multiplayer.is_server():
		return
	if _players.is_empty():
		return
	var mob_spawn_location := $SpawnPath/SpawnLocation
	mob_spawn_location.progress_ratio = randf()
	var player_values := _players.values()
	var target_player: Node3D = player_values[randi() % player_values.size()]
	_mob_counter += 1
	var angle_offset := randf_range(-PI / 4, PI / 4)
	var t := clampf(_game_time / 120.0, 0.0, 1.0)
	var speed := randi_range(int(lerpf(5.0, 15.0, t)), int(lerpf(10.0, 25.0, t)))
	_spawn_mob.rpc(_mob_counter, mob_spawn_location.position, target_player.position, angle_offset, speed)

@rpc("authority", "call_local", "reliable")
func _spawn_mob(mob_id: int, spawn_pos: Vector3, target_pos: Vector3, angle_offset: float, speed: int) -> void:
	var mob := mob_scene.instantiate()
	mob.name = "Mob%d" % mob_id
	mob.set_multiplayer_authority(1)
	mob.position = spawn_pos  # pre-position before add_child so physics never sees it at origin
	$Mobs.add_child(mob)
	mob.initialize(spawn_pos, target_pos, angle_offset, speed)

@rpc("any_peer", "reliable")
func _on_squash_request(mob_name: String, squasher_id: int) -> void:
	if not multiplayer.is_server():
		return
	if squasher_id != multiplayer.get_remote_sender_id() and multiplayer.get_remote_sender_id() != 0:
		return
	var mob = $Mobs.get_node_or_null(mob_name)
	if mob == null:
		return
	mob._die.rpc()
	_scores[squasher_id] = _scores.get(squasher_id, 0) + 1
	_update_score.rpc(squasher_id, _scores[squasher_id])

@rpc("authority", "call_local", "reliable")
func _update_score(peer_id: int, new_score: int) -> void:
	_scores[peer_id] = new_score
	_refresh_score_display()

@rpc("any_peer", "reliable")
func _on_player_died(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_eliminate_player.rpc(peer_id)

@rpc("authority", "call_local", "reliable")
func _eliminate_player(peer_id: int) -> void:
	_eliminated[peer_id] = true
	var player = _players.get(peer_id)
	if is_instance_valid(player) and player.is_inside_tree():
		var sync_node = player.get_node_or_null("Sync")
		if sync_node:
			sync_node.queue_free()
		var death_pos: Vector3 = player.global_position
		player.TriggerDeathExplosion()
		player.queue_free()
		_players.erase(peer_id)
		var sfx := AudioStreamPlayer3D.new()
		sfx.stream = load("res://audio/deathpop.mp3")
		sfx.unit_size = 10.0
		sfx.position = death_pos
		sfx.autoplay = true
		add_child(sfx)
		sfx.finished.connect(sfx.queue_free)
	elif _players.has(peer_id):
		_players.erase(peer_id)
	_refresh_score_display()
	if multiplayer.is_server() and _players.is_empty():
		_game_over.rpc()

@rpc("authority", "call_local", "reliable")
func _game_over() -> void:
	$Timer.stop()
	_fade_music_in()
	await get_tree().create_timer(2.0).timeout
	_populate_game_over_scores()
	_restart_btn.visible = multiplayer.is_server()
	get_tree().paused = true
	_game_over_center.visible = true

func _populate_game_over_scores() -> void:
	for child in _game_over_scores_box.get_children():
		child.queue_free()
	var sorted_ids := _scores.keys()
	sorted_ids.sort_custom(func(a, b): return _scores[a] > _scores[b])
	var rank_labels: Array[String] = ["1st", "2nd", "3rd", "4th"]
	for i in sorted_ids.size():
		var pid: int = sorted_ids[i]
		var label: String = _player_labels.get(pid, "P?")
		var pname: String = "You (%s)" % label if pid == multiplayer.get_unique_id() else label
		var rank := rank_labels[mini(i, rank_labels.size() - 1)]
		var row := Label.new()
		row.text = "%s  %s — %d" % [rank, pname, _scores[pid]]
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_theme_font_override("font", _font)
		row.add_theme_font_size_override("font_size", 20)
		if i == 0:
			row.modulate = Color(1.0, 0.85, 0.1)
		_game_over_scores_box.add_child(row)

func _on_restart_pressed() -> void:
	if multiplayer.is_server():
		_restart_game.rpc()

@rpc("authority", "call_local", "reliable")
func _restart_game() -> void:
	get_tree().paused = false
	_game_over_center.visible = false
	_fade_music_out()
	for child in _game_over_scores_box.get_children():
		child.queue_free()
	for mob in $Mobs.get_children():
		mob.queue_free()
	if multiplayer.is_server():
		_scores.clear()
		_eliminated.clear()
		_player_labels.clear()
		_mob_counter = 0
		_game_time = 0.0
		for pid in Array(_players.keys()):
			_players[pid].queue_free()
		_players.clear()
		var all_peers := [multiplayer.get_unique_id()] + Array(multiplayer.get_peers())
		for pid in all_peers:
			_spawn_player.rpc(pid)
		$Timer.start()
	_refresh_score_display()

func _refresh_score_display() -> void:
	if not is_instance_valid(_leaderboard_rows):
		return
	for child in _leaderboard_rows.get_children():
		child.queue_free()
	var sorted_ids := _scores.keys()
	sorted_ids.sort_custom(func(a, b): return _scores[a] > _scores[b])
	for pid in sorted_ids:
		var label: String = _player_labels.get(pid, "P?")
		var pname: String = "You (%s)" % label if pid == multiplayer.get_unique_id() else label
		var score: int = _scores[pid]
		var dead: bool = _eliminated.get(pid, false)
		var row := Label.new()
		row.text = "%s  %d" % [pname, score]
		row.add_theme_font_override("font", _font)
		row.add_theme_font_size_override("font_size", 16)
		row.modulate = Color(0.55, 0.55, 0.55) if dead else \
			(Color(1.0, 0.85, 0.1) if pid == multiplayer.get_unique_id() else Color.WHITE)
		_leaderboard_rows.add_child(row)

func _unhandled_input(event: InputEvent) -> void:
	if _in_lobby:
		if event.is_action_pressed("lobby_confirm"):
			_on_lobby_action_pressed()
		elif event.is_action_pressed("menu"):
			_quit_to_menu()
		return
	if not _in_game:
		return
	if event.is_action_pressed("menu"):
		_quit_to_menu()

func _quit_to_menu() -> void:
	_in_game = false
	_in_lobby = false
	get_tree().paused = false
	_lobby_center.visible = false
	_game_over_center.visible = false
	_fade_music_in(1.0)
	_ready_players.clear()
	$Timer.stop()
	for player in _players.values():
		player.queue_free()
	_players.clear()
	for mob in $Mobs.get_children():
		mob.queue_free()
	_scores.clear()
	_eliminated.clear()
	_player_labels.clear()
	_mob_counter = 0
	_game_time = 0.0
	multiplayer.multiplayer_peer = null
	for child in _game_over_scores_box.get_children():
		child.queue_free()
	_refresh_score_display()
	_ui_canvas.visible = true

func _on_lobby_action_pressed() -> void:
	if multiplayer.is_server():
		var all_ready := true
		for pid in _ready_players:
			if not _ready_players[pid]:
				all_ready = false
				break
		if all_ready:
			_begin_game.rpc()
	else:
		_request_ready_toggle.rpc_id(1)

@rpc("any_peer", "reliable")
func _request_ready_toggle() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender in _ready_players:
		_ready_players[sender] = not _ready_players[sender]
	_sync_lobby.rpc(_ready_players, _player_labels)

@rpc("authority", "call_local", "reliable")
func _sync_lobby(ready_dict: Dictionary, labels_dict: Dictionary) -> void:
	_ready_players = ready_dict
	_player_labels = labels_dict
	_lobby_center.visible = true
	_refresh_lobby_ui()

@rpc("authority", "call_local", "reliable")
func _begin_game() -> void:
	_in_lobby = false
	_lobby_center.visible = false
	_fade_music_out()
	if multiplayer.is_server():
		for pid in _player_labels.keys():
			_scores[pid] = 0
			_spawn_player.rpc(pid)
		$Timer.start()

func _refresh_lobby_ui() -> void:
	if not is_instance_valid(_lobby_player_list):
		return
	for child in _lobby_player_list.get_children():
		child.queue_free()

	var my_id := multiplayer.get_unique_id()
	var all_clients_ready := true

	for pid in _player_labels:
		var is_pid_host: bool = pid == 1
		var is_me: bool = pid == my_id
		var is_ready: bool = is_pid_host or _ready_players.get(pid, false)
		if not is_pid_host and not is_ready:
			all_clients_ready = false

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)

		var name_lbl := Label.new()
		var lbl: String = _player_labels.get(pid, "P?")
		name_lbl.text = lbl + ("  (You)" if is_me else "") + ("  [HOST]" if is_pid_host else "")
		name_lbl.add_theme_font_override("font", _font)
		name_lbl.add_theme_font_size_override("font_size", 18)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)

		var status_lbl := Label.new()
		status_lbl.add_theme_font_override("font", _font)
		status_lbl.add_theme_font_size_override("font_size", 16)
		if is_pid_host:
			status_lbl.text = "HOST"
			status_lbl.modulate = Color(0.7, 0.75, 1.0)
		elif is_ready:
			status_lbl.text = "READY"
			status_lbl.modulate = Color(0.3, 1.0, 0.4)
		else:
			status_lbl.text = "Waiting..."
			status_lbl.modulate = Color(0.6, 0.6, 0.6)
		row.add_child(status_lbl)
		_lobby_player_list.add_child(row)

	if multiplayer.is_server():
		_lobby_action_btn.text = "Start Game"
		if all_clients_ready:
			_lobby_status.text = "All players ready — press Start or Enter to begin!"
			_lobby_action_btn.disabled = false
		else:
			_lobby_status.text = "Waiting for all players to ready up..."
			_lobby_action_btn.disabled = true
	else:
		var i_am_ready: bool = _ready_players.get(my_id, false)
		_lobby_action_btn.disabled = false
		if i_am_ready:
			_lobby_action_btn.text = "Unready"
			_lobby_status.text = "You are ready! Waiting for the host to start..."
		else:
			_lobby_action_btn.text = "Ready"
			_lobby_status.text = "Press Ready (or Space / A) when you're good to go."

func _fade_music_out(duration: float = 1.5) -> void:
	if _music_tween:
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_property($AudioStreamPlayer, "volume_db", -60.0, duration)

func _fade_music_in(duration: float = 3.0) -> void:
	if _music_tween:
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_property($AudioStreamPlayer, "volume_db", _music_volume, duration)
