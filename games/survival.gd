extends Node2D

const MAX_HEALTH = 3

const SIDE_STEP = 5
const DROP_SPEED = 50
const FAST_DROP_SPEED = 3 * DROP_SPEED
const ROTATION_SPEED = 8

const INPUT_DELAY = 0.1
const NUDGE_DELAY = 0.1

const SPAWN_OFFSET = 200

const CAMERA_LOW_OFFSET = 100
const CAMERA_HIGH_OFFSET = 1.5 * SPAWN_OFFSET
const CAMERA_MIN_ZOOM = 1
const CAMERA_MAX_ZOOM = 3

var piece_loader = PieceLoad.new()
var scores = Scores.new()
var gamerules = Gamerules.new()
var nudge_effect = preload("res://effects/nudge.tscn")
var highscore_screenshot = Texture.new()
var current_highest = 0

@onready var score_display = $HUD/Info/Score/Label as Label
@onready var next_piece_texture = $HUD/NextPieceContainer/VBox/Texture as TextureRect
@onready var health_bar = $HUD/Info/HealthBar as HealthBar
@onready var existing_pieces = $Level/ExistingPieces as Node2D
@onready var camera = $Level/Camera as Camera2D
@onready var drop_audio = $Level/DropAudio as AudioStreamPlayer2D
@onready var beam = $Level/BeamBorder as Node2D
@onready var health_cooldown = $Level/HealthCooldown as Timer
@onready var pause_button = $HUD/PauseButton as Control
@onready var pause_menu = $HUD/PauseMenu as PauseMenu
@onready var game_over_timer = $Level/GameOverTimer as Timer
@onready var touch_screen = $TouchScreen as CanvasLayer
@onready var easy_mode_label = $HUD/Info/EasyModeLabel as Label
@onready var screenshot_sprite = $HUD/TextureRect as TextureRect
@onready var screenshot_audio = $HUD/ScreenshotAudio as AudioStreamPlayer2D

func _ready():
	if gamerules.easy:
		health_bar.hide()
		easy_mode_label.show()
		pause_menu.easy_mode()
	pick_next_piece()
	spawn_next_piece()

var health: int = MAX_HEALTH
var game_over: bool

var last_piece: RigidBody2D
var last_piece_data: PieceLoad.PieceData
var next_piece_data: PieceLoad.PieceData

var prev_rotation: float
var next_rotation: float
var elapsed: float
var rotate: bool

var next_input_delay: float
var nudge_delay: float
var nudge_direction: Vector2

func _process(delta):
	
	var scrmod = screenshot_sprite.modulate.r
	if scrmod > 1:
		screenshot_sprite.modulate = Color(scrmod-0.5, scrmod-0.5, scrmod-0.5)
		
	if game_over:
		return
	if last_piece == null:
		spawn_next_piece()
	update_movement(delta)
	update_rotation(delta)
	update_camera(delta)
	update_beam()
	update_score()
	
func update_score():
	var score = existing_pieces.get_child_count() - 1
	score_display.text = str(score)
	if not gamerules.easy and score > scores.best_score:
		scores.update_score(score)
		
	if (score > current_highest):
		current_highest = score
		highscore_screenshot = ImageTexture.create_from_image(get_viewport().get_texture().get_image())
		
func update_rotation(delta):
	if not rotate:
		if Input.is_action_just_pressed("rotate_clockwise"):
			prev_rotation = last_piece.rotation
			next_rotation = last_piece.rotation + PI / 2
			rotate = true
		if Input.is_action_just_pressed("rotate_anticlockwise"):
			prev_rotation = last_piece.rotation
			next_rotation = last_piece.rotation - PI / 2
			rotate = true
	else:
		elapsed += ROTATION_SPEED * delta
		last_piece.rotation = lerp_angle(prev_rotation, next_rotation, elapsed)
		if elapsed > 1:
			last_piece.rotation = next_rotation
			elapsed = 0
			rotate = false

func _unhandled_input(event):
	if event is InputEventScreenTouch:
		if event.pressed:
			for touch_control in touch_screen.get_children():
				var touch_button = touch_control.get_child(0) as TouchScreenButton
				if touch_button.is_pressed():
					return
			Input.action_press("fast_drop")
		else:
			Input.action_release("fast_drop")

func update_movement(delta):
	next_input_delay -= delta
	nudge_delay -= delta

	var do_nudge = func(dir):
		nudge_delay = NUDGE_DELAY
		nudge_direction = dir
		var e = nudge_effect.instantiate() as CPUParticles2D
		e.direction = -nudge_direction
		e.rotation = -last_piece.rotation
		last_piece.add_child(e)

	if Input.is_action_just_pressed("nudge_right"):
		do_nudge.call(Vector2.RIGHT)
	if Input.is_action_just_pressed("nudge_left"):
		do_nudge.call(Vector2.LEFT)
	if nudge_delay > 0:
		last_piece.move_and_collide(nudge_direction * SIDE_STEP)

	var collision
	if Input.is_action_pressed("fast_drop"):
		collision = last_piece.move_and_collide(Vector2(0, FAST_DROP_SPEED * delta))
	else:
		collision = last_piece.move_and_collide(Vector2(0, DROP_SPEED * delta))

	if next_input_delay <= 0 and nudge_delay <= 0 and Input.is_action_pressed("move_right"):
		collision = last_piece.move_and_collide(Vector2(SIDE_STEP, 0))
		next_input_delay = INPUT_DELAY
	if next_input_delay <= 0 and nudge_delay <= 0 and Input.is_action_pressed("move_left"):
		collision = last_piece.move_and_collide(Vector2(-SIDE_STEP, 0))
		next_input_delay = INPUT_DELAY

	if nudge_delay <= 0 and collision != null:
		spawn_next_piece()

func update_camera(delta):
	var highest = find_highest_y() - CAMERA_HIGH_OFFSET
	var lowest = CAMERA_LOW_OFFSET
	var mid = (highest + lowest) / 2
	var height = abs(highest - lowest)
	var view_h = abs(get_viewport_rect().size.y)
	var pos = Vector2(0, mid)
	var zoom = clampf(view_h / height, CAMERA_MIN_ZOOM, CAMERA_MAX_ZOOM)

	if is_equal_approx(zoom, CAMERA_MIN_ZOOM):
		pos = Vector2(0, highest + view_h / zoom / 2)

	camera.position = lerp(camera.position, pos, delta)
	camera.zoom = lerp(camera.zoom, zoom * Vector2.ONE, delta)
	
func update_beam():
	beam.position = last_piece.position
	var width = last_piece_data.width(last_piece.rotation)
	beam.scale = Vector2(width, 1000000)

func spawn_next_piece():
	if last_piece != null:
		last_piece.freeze = false
		last_piece.linear_velocity = Vector2.ZERO
		last_piece.get_child(0).disabled = true
		last_piece.get_child(1).disabled = false
		drop_audio.play()
	last_piece_data = next_piece_data
	last_piece = last_piece_data.scene.instantiate()
	last_piece.freeze = true
	last_piece.freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
	reset_rotation()
	last_piece.move_local_y(find_highest_y() - SPAWN_OFFSET)
	last_piece.get_child(0).disabled = false
	last_piece.get_child(1).disabled = true
	existing_pieces.add_child(last_piece)
	pick_next_piece()

func pick_next_piece():
	next_piece_data = piece_loader.random_piece()
	var next_piece = next_piece_data.scene.instantiate()
	var piece_sprite = next_piece.get_child(2) as Sprite2D
	next_piece_texture.texture = piece_sprite.texture
	next_piece.queue_free()

func find_highest_y() -> float:
	var highest = 0
	for child in existing_pieces.get_children():
		if child != last_piece:
			highest = min(child.position.y, highest)
	return highest

func reset_rotation():
	prev_rotation = 0
	next_rotation = 0
	elapsed = 0
	rotate = false

func _on_world_border_piece_fell():
	if gamerules.easy:
		return
	if health_cooldown.is_stopped():
		health = clampi(health - 1, 0, MAX_HEALTH)
		health_bar.remove_heart(health)
		health_cooldown.start()
	if health <= 0:
		if not game_over:
			game_over = true
			
			screenshot_sprite.set_texture(highscore_screenshot)
			screenshot_sprite.modulate = Color(8, 8, 8);
			screenshot_audio.play()
			
			beam.hide()
			if last_piece != null:
				last_piece.hide()
			game_over_timer.start()

func _on_health_cooldown_timeout():
	health_bar.stop_animation()

func _on_pause_button_pause_game():
	pause_game()

func pause_game():
	pause_button.hide()
	pause_menu.show()
	pause_menu.update_score(scores.best_score)
	touch_screen.hide()
	get_tree().paused = true

func _on_pause_menu_continue_game():
	pause_button.show()
	pause_menu.hide()
	touch_screen.show()

func _on_pause_menu_restart_game():
	get_tree().reload_current_scene()

func _on_pause_menu_leave_game():
	get_tree().change_scene_to_file("res://interface/main_menu.tscn")

func _on_game_over_timer_timeout():
	pause_menu.game_over()
	pause_game()
