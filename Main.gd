extends Node2D

## QCom · Quantum Command
## Top-down arcade shooter — single-script, no external assets

const W := 800.0
const H := 600.0

const POWER_DEFS := {
	"ENERGY":    {"color": Color(0.0, 1.0, 0.6),   "desc": "Triple Shot", "dur": 8.0},
	"SHIELD":    {"color": Color(0.3, 0.6, 1.0),   "desc": "Shields Up",  "dur": 6.0},
	"OVERDRIVE": {"color": Color(1.0, 0.6, 0.0),   "desc": "Overdrive",   "dur": 5.0},
	"BURST":     {"color": Color(1.0, 0.9, 0.0),   "desc": "Q-Burst",     "dur": 0.0},
	"WARP":      {"color": Color(0.74, 0.58, 0.98),"desc": "Time Warp",   "dur": 4.0},
}

enum State { MENU, PLAY, OVER }

# ── state ──────────────────────────────────────────────────────────────────────
var gstate: State = State.MENU
var score: int    = 0
var hi:    int    = 0
var lives: int    = 3
var wave:  int    = 0

# ── entities (plain dictionaries) ─────────────────────────────────────────────
var player:    Dictionary = {}
var enemies:   Array      = []
var bullets:   Array      = []
var powerups:  Array      = []
var particles: Array      = []
var stars:     Array      = []

# ── timers ─────────────────────────────────────────────────────────────────────
var shoot_cd:   float = 0.0
var shield_t:   float = 0.0
var shield_hp:  int   = 0
var over_t:     float = 0.0   # overdrive
var warp_t:     float = 0.0
var triple_t:   float = 0.0
var invuln_t:   float = 0.0
var wave_delay: float = 0.0
var wave_anim:  float = 0.0
var wave_label: String = ""
var clock:      float = 0.0   # global time for animations

# ── font ───────────────────────────────────────────────────────────────────────
var font:    Font
var font_sz: int = 16

# ══════════════════════════════════════════════════════════════════════════════
func _ready() -> void:
	font    = ThemeDB.fallback_font
	font_sz = ThemeDB.fallback_font_size
	_make_stars()

func _make_stars() -> void:
	stars.clear()
	for _i in 160:
		stars.append({
			"p":  Vector2(randf() * W, randf() * H),
			"r":  randf_range(0.4, 2.0),
			"sp": randf_range(18.0, 75.0),
			"a":  randf_range(0.3, 1.0),
		})

# ── input ─────────────────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	match event.keycode:
		KEY_SPACE, KEY_ENTER, KEY_Z:
			if   gstate == State.MENU: _start()
			elif gstate == State.OVER: _start()
		KEY_ESCAPE:
			if gstate == State.PLAY:
				gstate = State.MENU

# ── lifecycle ─────────────────────────────────────────────────────────────────
func _start() -> void:
	score = 0; lives = 3; wave = 0
	enemies.clear(); bullets.clear(); powerups.clear(); particles.clear()
	shoot_cd = 0.0; shield_t = 0.0; shield_hp = 0
	over_t = 0.0; warp_t = 0.0; triple_t = 0.0; invuln_t = 0.0
	wave_delay = 0.0; wave_anim = 0.0
	player = {"p": Vector2(W / 2.0, H - 80.0), "guns": 1}
	gstate = State.PLAY
	_next_wave()

func _next_wave() -> void:
	wave += 1
	wave_label = "WAVE  %d" % wave
	wave_anim  = 2.5
	wave_delay = 3.0
	var tier   := clampi((wave - 1) / 3, 0, 3)
	var count  := 5 + wave * 2

	for i in count:
		var t := _tier(tier + (1 if randf() < 0.25 else 0))
		enemies.append({
			"p":         Vector2(randf_range(40.0, W - 40.0), -55.0 - i * 55.0),
			"v":         Vector2(randf_range(-60.0, 60.0), t.spd),
			"hp": t.hp,  "mhp": t.hp,
			"pts": t.pts,"col": t.col,
			"sz":  t.sz, "shoots": t.shoots,
			"scd": randf_range(1.0, 2.5),
			"wob": randf() * TAU,
			"boss": t.boss, "big": false,
		})

	if wave % 5 == 0:
		var bhp := 20 + wave * 3
		enemies.append({
			"p": Vector2(W / 2.0, -110.0), "v": Vector2.ZERO,
			"hp": bhp, "mhp": bhp, "pts": 600,
			"col": Color(1.0, 0.0, 0.6), "sz": 42.0,
			"shoots": true, "scd": 0.7, "wob": 0.0,
			"boss": true,  "big": true,
		})

func _tier(t: int) -> Dictionary:
	var T := [
		{"col":Color(1,.26,.26),"hp":1,"pts":10, "spd":70., "sz":13.,"shoots":false,"boss":false},
		{"col":Color(1,.53, 0.),"hp":2,"pts":25, "spd":55., "sz":17.,"shoots":true, "boss":false},
		{"col":Color(.6,.2, 1.),"hp":3,"pts":50, "spd":42., "sz":21.,"shoots":true, "boss":false},
		{"col":Color(1, 0,  1.),"hp":6,"pts":130,"spd":30., "sz":26.,"shoots":true, "boss":true },
	]
	return T[clampi(t, 0, 3)]

# ── main loop ─────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	clock += delta
	_update(delta)
	queue_redraw()

func _update(d: float) -> void:
	var ts := 0.3 if warp_t > 0.0 else 1.0  # time-warp scale

	for s in stars:
		s.p.y += s.sp * d * ts
		if s.p.y > H: s.p = Vector2(randf() * W, -2.0)

	if gstate != State.PLAY: return

	# timers
	shoot_cd   = maxf(0.0, shoot_cd   - d)
	shield_t   = maxf(0.0, shield_t   - d)
	over_t     = maxf(0.0, over_t     - d)
	warp_t     = maxf(0.0, warp_t     - d)
	invuln_t   = maxf(0.0, invuln_t   - d)
	wave_delay = maxf(0.0, wave_delay  - d)
	wave_anim  = maxf(0.0, wave_anim   - d)
	if triple_t > 0.0:
		triple_t -= d
		if triple_t <= 0.0: player.guns = 1

	_move_player(d, ts)
	_move_enemies(d, ts)
	_move_bullets(d, ts)
	_move_powerups(d, ts)

	# particles
	for pt in particles: pt.p += pt.v * d; pt.life -= d
	particles = particles.filter(func(pt): return pt.life > 0.0)

	if enemies.is_empty() and wave_delay <= 0.0: _next_wave()

# ── player ────────────────────────────────────────────────────────────────────
func _move_player(d: float, ts: float) -> void:
	var spd := 240.0 * (1.8 if over_t > 0.0 else 1.0)
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT)  or Input.is_key_pressed(KEY_A): dir.x -= 1
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D): dir.x += 1
	if Input.is_key_pressed(KEY_UP)    or Input.is_key_pressed(KEY_W): dir.y -= 1
	if Input.is_key_pressed(KEY_DOWN)  or Input.is_key_pressed(KEY_S): dir.y += 1
	if dir.length_squared() > 0.0: dir = dir.normalized()
	player.p   += dir * spd * d * ts
	player.p.x  = clampf(player.p.x, 18.0, W - 18.0)
	player.p.y  = clampf(player.p.y, 18.0, H - 18.0)

	var auto_fire := Input.is_key_pressed(KEY_SPACE) or \
	                 Input.is_key_pressed(KEY_Z)      or \
	                 Input.is_key_pressed(KEY_ENTER)
	if auto_fire and shoot_cd <= 0.0: _fire()

func _fire() -> void:
	shoot_cd = 0.10 if over_t > 0.0 else 0.16
	var p  := player.p
	var sp := 580.0
	if player.guns >= 3:
		bullets.append({"p":Vector2(p.x-10,p.y-15),"v":Vector2(-90,-sp),"fr":true})
		bullets.append({"p":Vector2(p.x,   p.y-20),"v":Vector2(  0,-sp),"fr":true})
		bullets.append({"p":Vector2(p.x+10,p.y-15),"v":Vector2( 90,-sp),"fr":true})
	else:
		bullets.append({"p":Vector2(p.x,p.y-20),"v":Vector2(0,-sp),"fr":true})

# ── enemies ───────────────────────────────────────────────────────────────────
func _move_enemies(d: float, ts: float) -> void:
	var fell: Array = []
	for e in enemies:
		e.wob += 2.0 * d
		if e.big:
			e.v.y = (120.0 - e.p.y) * 2.0
			e.v.x = sin(e.wob * 0.4) * 155.0
		else:
			e.v.x += sin(e.wob) * 28.0 * d
			e.v.x  = clampf(e.v.x, -130.0, 130.0)
		e.p   += e.v * d * ts
		if e.p.x < e.sz or e.p.x > W - e.sz: e.v.x *= -1.0

		if e.shoots:
			e.scd -= d * ts
			if e.scd <= 0.0:
				e.scd = (0.65 if e.big else 1.8) + randf() * 0.6
				var dir := (player.p - e.p).normalized()
				bullets.append({"p":e.p+dir*e.sz,"v":dir*(195.0 if e.big else 145.0),"fr":false,"col":e.col})

		if e.p.y > H + 60.0:
			fell.append(e)
			_hit_player()

	for e in fell: enemies.erase(e)

# ── bullets ───────────────────────────────────────────────────────────────────
func _move_bullets(d: float, ts: float) -> void:
	for b in bullets: b.p += b.v * d * ts

	var rem: Array = []

	# friendly hits enemies
	for b in bullets:
		if not b.fr or rem.has(b): continue
		for e in enemies:
			if b.p.distance_to(e.p) < e.sz + 5.0:
				rem.append(b)
				_burst(b.p, e.col, 4)
				e.hp -= 1
				if e.hp <= 0:
					score    += e.pts
					e["dead"] = true
					_burst(e.p, e.col, 14)
					_try_drop(e.p)
				break

	# enemy hits player
	if invuln_t <= 0.0:
		for b in bullets:
			if b.fr or rem.has(b): continue
			if b.p.distance_to(player.p) < 20.0:
				rem.append(b)
				_hit_player()

	bullets  = bullets.filter(func(b): return \
		not rem.has(b) and not b.get("dead",false) and \
		b.p.x>-10 and b.p.x<W+10 and b.p.y>-20 and b.p.y<H+20)
	enemies  = enemies.filter(func(e): return not e.get("dead",false))

func _hit_player() -> void:
	if shield_t > 0.0:
		shield_hp -= 1
		_burst(player.p, Color(0.3,0.7,1.0), 8)
		if shield_hp <= 0: shield_t = 0.0
		return
	if invuln_t > 0.0: return
	invuln_t = 1.8
	lives   -= 1
	_burst(player.p, Color(1.0,0.4,0.0), 20)
	if lives <= 0:
		hi     = max(score, hi)
		gstate = State.OVER

# ── power-ups ─────────────────────────────────────────────────────────────────
func _try_drop(pos: Vector2) -> void:
	if randf() > 0.28: return
	var names := POWER_DEFS.keys()
	var nm: String = names[randi() % names.size()]
	var d  := POWER_DEFS[nm]
	powerups.append({"p":pos,"name":nm,"col":d.color,"desc":d.desc,"dur":d.dur,"ang":0.0,"life":7.0})

func _move_powerups(d: float, ts: float) -> void:
	var rem: Array = []
	for pw in powerups:
		pw.p.y += 75.0 * d * ts
		pw.ang += 2.5 * d
		pw.life -= d
		if pw.p.distance_to(player.p) < 24.0:
			_grab(pw); rem.append(pw)
		elif pw.p.y > H + 20.0 or pw.life <= 0.0:
			rem.append(pw)
	for pw in rem: powerups.erase(pw)

func _grab(pw: Dictionary) -> void:
	match pw.name:
		"ENERGY":    player.guns = 3; triple_t = 8.0
		"SHIELD":    shield_t = 6.0;  shield_hp = 3
		"OVERDRIVE": over_t   = 5.0
		"BURST":
			for e in enemies:
				score += e.pts; _burst(e.p, e.col, 10); _try_drop(e.p)
			enemies.clear()
			bullets = bullets.filter(func(b): return b.fr)
		"WARP":      warp_t = 4.0
	_pop(pw.p, pw.desc, pw.col)

# ── particles ─────────────────────────────────────────────────────────────────
func _burst(pos: Vector2, col: Color, n: int) -> void:
	for _i in n:
		var a := randf() * TAU
		var s := randf_range(40.0, 180.0)
		particles.append({"p":pos,"v":Vector2(cos(a),sin(a))*s,"col":col,
			"life":randf_range(0.4,0.9),"r":randf_range(2.0,4.5),"txt":false})

func _pop(pos: Vector2, text: String, col: Color) -> void:
	particles.append({"p":pos,"v":Vector2(0,-55.0),"col":col,
		"life":1.6,"r":0.0,"txt":true,"msg":text})

# ══════════════════════════════════════════════════════════════════════════════
#  DRAW
# ══════════════════════════════════════════════════════════════════════════════
func _draw() -> void:
	draw_rect(Rect2(0,0,W,H), Color(0.0,0.02,0.08))
	for s in stars: draw_circle(s.p, s.r, Color(1,1,1,s.a))

	match gstate:
		State.MENU:    _draw_menu()
		State.PLAY:    _draw_game()
		State.OVER:    _draw_game(); _draw_over()

func _draw_menu() -> void:
	var cx := W / 2.0
	_tc("Q C O M", Vector2(cx,130), 72, Color(0.0,1.0,1.0))
	_tc("QUANTUM COMMAND", Vector2(cx,184), 18, Color(0.55,0.88,1.0,0.85))
	draw_line(Vector2(cx-190,208), Vector2(cx+190,208), Color(0,1,1,0.25), 1)

	_tc("POWER-UPS", Vector2(cx,236), 13, Color(0.75,0.75,0.75))
	var names := POWER_DEFS.keys()
	for i in names.size():
		var nm: String = names[i]
		var pd := POWER_DEFS[nm]
		_tc("[%s]  —  %s" % [nm, pd.desc], Vector2(cx, 258.0 + i * 22.0), 13, pd.color)

	_tc("WASD / Arrows = Move     Space / Z = Shoot", Vector2(cx,388), 12, Color(.4,.4,.4))
	var a := abs(sin(clock * TAU / 1.5))
	_tc("PRESS  SPACE  TO  START", Vector2(cx,438), 20, Color(0.0,1.0,1.0,a))
	if hi > 0: _tc("BEST: %d" % hi, Vector2(cx,478), 14, Color(1.0,1.0,0.0))

func _draw_game() -> void:
	_draw_pups()
	_draw_enemies()
	_draw_bullets()
	_draw_player()
	_draw_particles()
	_draw_hud()

func _draw_player() -> void:
	if invuln_t > 0.0 and int(invuln_t * 8) % 2 == 0: return
	var p := player.p
	# thruster flame
	var fl := 8.0 + randf() * 8.0
	draw_colored_polygon(PackedVector2Array([
		Vector2(p.x-5, p.y+16), Vector2(p.x, p.y+16+fl), Vector2(p.x+5, p.y+16)
	]), Color(1.0,0.6,0.0,0.9))
	# hull
	draw_colored_polygon(PackedVector2Array([
		Vector2(p.x,    p.y-20), Vector2(p.x-14, p.y+16),
		Vector2(p.x-6,  p.y+10), Vector2(p.x,   p.y+14),
		Vector2(p.x+6,  p.y+10), Vector2(p.x+14, p.y+16),
	]), Color(0.0,0.8,1.0))
	# cockpit
	draw_colored_polygon(PackedVector2Array([
		Vector2(p.x, p.y-12), Vector2(p.x-5, p.y+4), Vector2(p.x+5, p.y+4)
	]), Color(0.55,1.0,1.0))
	# shield ring
	if shield_t > 0.0:
		var sa := 0.45 + 0.3 * sin(clock * TAU * 2.0)
		draw_arc(p, 30.0, 0.0, TAU, 32, Color(0.3,0.7,1.0,sa), 2.5)
		for i in shield_hp:
			var ang := i / float(shield_hp) * TAU - PI / 2.0
			draw_circle(p + Vector2(cos(ang),sin(ang)) * 30.0, 4.0, Color(0.3,0.7,1.0))

func _draw_enemies() -> void:
	for e in enemies:
		var p  := e.p
		var sz := e.sz
		var c: Color = e.col

		if e.big:
			var pts := PackedVector2Array()
			for i in 4:
				var a := e.wob * 0.5 + i * PI / 2.0
				pts.append(p + Vector2(cos(a),sin(a)) * sz)
			draw_colored_polygon(pts, c)
			draw_circle(p, sz * 0.35, Color(1.0,0.5,0.8))
			_hpbar(p, sz, e.hp, e.mhp, c, 2.6)
		elif e.boss:
			draw_colored_polygon(PackedVector2Array([
				Vector2(p.x, p.y-sz), Vector2(p.x-sz, p.y+sz*.6),
				Vector2(p.x, p.y+sz*.3), Vector2(p.x+sz, p.y+sz*.6),
			]), c)
			_hpbar(p, sz, e.hp, e.mhp, c, 2.2)
		else:
			draw_colored_polygon(PackedVector2Array([
				Vector2(p.x, p.y+sz),
				Vector2(p.x-sz*.8, p.y-sz*.6),
				Vector2(p.x+sz*.8, p.y-sz*.6),
			]), c)
			if e.mhp > 1: _hpbar(p, sz, e.hp, e.mhp, c, 2.0)

func _hpbar(p: Vector2, sz: float, hp: int, mhp: int, col: Color, scale: float) -> void:
	var bw := sz * scale
	draw_rect(Rect2(p.x-bw/2.0, p.y-sz-10.0, bw, 5.0), Color(0.18,0.18,0.18))
	draw_rect(Rect2(p.x-bw/2.0, p.y-sz-10.0, bw * hp / mhp, 5.0), col)

func _draw_bullets() -> void:
	for b in bullets:
		if b.fr:
			draw_rect(Rect2(b.p.x-2.5, b.p.y-7, 5, 14), Color(0.0,1.0,1.0))
		else:
			draw_circle(b.p, 4.5, b.get("col", Color(1.0,0.4,0.4)))

func _draw_pups() -> void:
	for pw in powerups:
		var p  := pw.p
		var c: Color = pw.col
		var s  := 13.0
		draw_set_transform(p, pw.ang, Vector2.ONE)
		draw_rect(Rect2(-s,-s,s*2,s*2), Color(c.r,c.g,c.b,0.2))
		draw_rect(Rect2(-s,-s,s*2,s*2), c, false, 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_tc(pw.name.left(1), p + Vector2(0.0,5.0), 14, c)

func _draw_particles() -> void:
	for pt in particles:
		var a := clampf(pt.life / 0.9, 0.0, 1.0)
		if pt.txt:
			_tc(pt.msg, pt.p, 13, Color(pt.col.r,pt.col.g,pt.col.b,a))
		else:
			draw_circle(pt.p, pt.r, Color(pt.col.r,pt.col.g,pt.col.b,a))

func _draw_hud() -> void:
	_tl(Vector2(10,24),  "SCORE: %d" % score, 17, Color(0.0,1.0,1.0))
	_tl(Vector2(10,44),  "BEST: %d"  % hi,    12, Color(1.0,1.0,0.0))
	_tc("WAVE  %d" % wave, Vector2(W/2.0,24), 17, Color(0.0,1.0,1.0))

	# ship life icons
	for i in lives:
		var lx := W - 18.0 - i * 24.0
		draw_colored_polygon(PackedVector2Array([
			Vector2(lx,10), Vector2(lx-6,22), Vector2(lx+6,22)
		]), Color(0.0,0.8,1.0))

	# active power labels
	var px := 8.0; var py := H - 10.0
	if shield_t   > 0.0: _tl(Vector2(px,py),"[SHIELD %.0fs]"    % ceil(shield_t),  11,Color(.3,.7,1.));  px+=115
	if over_t     > 0.0: _tl(Vector2(px,py),"[OVERDRIVE %.0fs]" % ceil(over_t),    11,Color(1.,.6,0.));  px+=135
	if warp_t     > 0.0: _tl(Vector2(px,py),"[TIME WARP %.0fs]" % ceil(warp_t),    11,Color(.74,.58,.98));px+=125
	if player.guns >= 3: _tl(Vector2(px,py),"[TRIPLE]",                              11,Color(0.,1.,.6))

	# warp overlay
	if warp_t > 0.0:
		draw_rect(Rect2(0,0,W,H), Color(0.74,0.58,0.98,0.07))

	# wave announcement
	if wave_anim > 0.0:
		var t := wave_anim / 2.5
		var a := 1.0 if t > 0.2 else t / 0.2
		_tc(wave_label, Vector2(W/2.0, H/2.0), 38, Color(1.0,1.0,0.0,a))

func _draw_over() -> void:
	draw_rect(Rect2(0,0,W,H), Color(0,0,0,0.62))
	_tc("GAME  OVER",            Vector2(W/2,200), 52, Color(1.0,0.3,0.3))
	_tc("SCORE:  %d" % score,    Vector2(W/2,278), 22, Color(1,1,1))
	_tc("BEST:   %d" % hi,       Vector2(W/2,308), 22, Color(1.0,1.0,0.0))
	_tc("WAVE REACHED: %d" % wave,Vector2(W/2,340), 15, Color(.65,.65,.65))
	var a := abs(sin(clock * TAU / 1.5))
	_tc("SPACE  TO  PLAY  AGAIN", Vector2(W/2,405), 20, Color(0.0,1.0,1.0,a))

# ── text helpers ──────────────────────────────────────────────────────────────
func _tl(pos: Vector2, text: String, sz: int, col: Color) -> void:
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)

func _tc(text: String, pos: Vector2, sz: int, col: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	draw_string(font, Vector2(pos.x - w / 2.0, pos.y), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
