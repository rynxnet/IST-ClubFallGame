class_name Sfx
extends RefCounted
## Sound effects, called from anywhere: `Sfx.play_at(&"rifle_shot", global_position, self)`.
##
## Sound names: rifle_shot, enemy_shot, dry_fire, reload_out, reload_in, bolt, footstep,
## land, hitmarker, headshot, kill_confirm, player_hurt, enemy_hurt, enemy_death,
## impact_concrete, impact_metal, impact_flesh. Unknown names are ignored silently.
##
## PLACEHOLDER AUDIO. Every sound is synthesized here (filtered noise, decaying sines,
## ringing metal modes, wall echoes) the first time it plays, then cached. To replace one
## with a recorded CC0 sample, drop `assets/audio/<name>.ogg` (or `.wav` / `.mp3`) into the
## project, e.g. `assets/audio/rifle_shot.ogg` (Git LFS, see CONTRIBUTING.md): a file there
## always wins over synthesis, and any new name with a file works too. Normalize files to
## about -1 dBFS; `MIX_DB` balances sounds against each other and `UNIT_SIZE` sets how far
## each one carries. To change a synthesized sound, edit its `_<name>()` function below.
## `warm_up()` builds everything up front if a first-use hitch ever matters.

const SOUNDS: Array[StringName] = [
	&"rifle_shot", &"enemy_shot", &"dry_fire", &"reload_out", &"reload_in", &"bolt",
	&"footstep", &"land", &"hitmarker", &"headshot", &"kill_confirm", &"player_hurt",
	&"enemy_hurt", &"enemy_death", &"impact_concrete", &"impact_metal", &"impact_flesh",
]
const OVERRIDE_PATH := "res://assets/audio/%s.%s"
const OVERRIDE_EXTENSIONS: Array[String] = ["ogg", "wav", "mp3"]

## Per-sound level offset in dB, added to the caller's `volume_db`.
const MIX_DB := {
	&"rifle_shot": 0.0, &"enemy_shot": -3.0, &"dry_fire": -9.0, &"reload_out": -9.0,
	&"reload_in": -7.0, &"bolt": -7.0, &"footstep": -13.0, &"land": -7.0, &"hitmarker": -11.0,
	&"headshot": -9.0, &"kill_confirm": -7.0, &"player_hurt": -4.0, &"enemy_hurt": -6.0,
	&"enemy_death": -5.0, &"impact_concrete": -5.0, &"impact_metal": -6.0, &"impact_flesh": -6.0,
}
## Distance in metres at which a positional sound plays at its mixed level.
const UNIT_SIZE := {
	&"rifle_shot": 15.0, &"enemy_shot": 15.0, &"footstep": 2.5, &"land": 3.0,
	&"enemy_hurt": 5.0, &"enemy_death": 5.0, &"impact_concrete": 6.0, &"impact_metal": 7.0,
	&"impact_flesh": 5.0,
}
const DEFAULT_UNIT_SIZE := 4.0
const MAX_DISTANCE := 80.0
## Sounds that repeat a lot get a few takes so they don't sound machine-gunned.
const VARIANTS := {
	&"footstep": 4, &"impact_concrete": 3, &"impact_metal": 3, &"impact_flesh": 2,
	&"enemy_hurt": 2,
}
const PITCH_JITTER := 0.06
## Oldest voice of a sound is cut when another would exceed this (automatic fire).
const MAX_VOICES := 6

const RATE := 22050
const NYQUIST := RATE * 0.5
const PEAK := 0.95
## 1.5 s of shared noise: longer than any single layer, so a layer never hears it repeat.
const NOISE_SIZE := 32768

static var _cache: Dictionary[StringName, AudioStream] = {}
static var _voices: Dictionary[StringName, Array] = {}
static var _white := PackedFloat32Array()


## Positional sound at a world position. `parent` is any node in the scene tree.
static func play_at(sound: StringName, position: Vector3, parent: Node, volume_db: float = 0.0) -> void:
	var host := _host(parent)
	if host == null:
		return
	var stream := get_stream(sound)
	if stream == null:
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = volume_db + float(MIX_DB.get(sound, 0.0))
	player.pitch_scale = randf_range(1.0 - PITCH_JITTER, 1.0 + PITCH_JITTER)
	player.unit_size = float(UNIT_SIZE.get(sound, DEFAULT_UNIT_SIZE))
	player.max_distance = MAX_DISTANCE
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
	player.position = (host as Node3D).to_local(position) if host is Node3D else position
	player.autoplay = true
	player.finished.connect(player.queue_free)
	_add_voice(sound, player, host)


## Non-positional sound (UI, the player's own gun).
static func play(sound: StringName, parent: Node, volume_db: float = 0.0) -> void:
	var host := _host(parent)
	if host == null:
		return
	var stream := get_stream(sound)
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db + float(MIX_DB.get(sound, 0.0))
	player.pitch_scale = randf_range(1.0 - PITCH_JITTER, 1.0 + PITCH_JITTER)
	player.autoplay = true
	player.finished.connect(player.queue_free)
	_add_voice(sound, player, host)


## The stream for a sound (override file or synthesized), or null if the name is unknown.
## A sound with several takes gains one more per call until all exist, which spreads the
## synthesis cost over its first few plays.
static func get_stream(sound: StringName) -> AudioStream:
	if not _cache.has(sound):
		var file := _load_override(sound)
		_cache[sound] = file if file else _synthesize(sound)
	else:
		var pool := _cache[sound] as AudioStreamRandomizer
		if pool and pool.streams_count < int(VARIANTS.get(sound, 1)):
			pool.add_stream(-1, _take(sound, pool.streams_count))
	return _cache[sound]


## Builds every sound (all takes) now instead of on first play.
static func warm_up() -> void:
	for sound in SOUNDS:
		for take in int(VARIANTS.get(sound, 1)):
			get_stream(sound)


static func _host(parent: Node) -> Node:
	if not is_instance_valid(parent) or not parent.is_inside_tree():
		return null
	var tree := parent.get_tree()
	return tree.current_scene if tree.current_scene else tree.root


static func _add_voice(sound: StringName, player: Node, host: Node) -> void:
	var live: Array = _voices.get(sound, []).filter(
			func(p: Variant) -> bool: return is_instance_valid(p) and not p.is_queued_for_deletion())
	while live.size() >= MAX_VOICES:
		live.pop_front().queue_free()
	live.append(player)
	_voices[sound] = live
	# Deferred so playing from _ready/_exit_tree (parent busy) never fails; autoplay starts it.
	host.add_child.call_deferred(player)


static func _load_override(sound: StringName) -> AudioStream:
	for ext in OVERRIDE_EXTENSIONS:
		var path := OVERRIDE_PATH % [sound, ext]
		if ResourceLoader.exists(path):
			return load(path) as AudioStream
	return null


# --- Synthesis -------------------------------------------------------------------------

static func _synthesize(sound: StringName) -> AudioStream:
	if not SOUNDS.has(sound):
		return null
	if not VARIANTS.has(sound):
		return _take(sound, 0)
	var pool := AudioStreamRandomizer.new()
	pool.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
	pool.random_volume_offset_db = 1.5
	pool.add_stream(-1, _take(sound, 0))
	return pool


static func _take(sound: StringName, index: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = String(sound).hash() + index
	return _to_wav(_render(sound, rng))


static func _render(sound: StringName, rng: RandomNumberGenerator) -> PackedFloat32Array:
	match sound:
		&"rifle_shot": return _rifle_shot(rng)
		&"enemy_shot": return _enemy_shot(rng)
		&"dry_fire": return _dry_fire(rng)
		&"reload_out": return _reload_out(rng)
		&"reload_in": return _reload_in(rng)
		&"bolt": return _bolt(rng)
		&"footstep": return _footstep(rng)
		&"land": return _land(rng)
		&"hitmarker": return _hitmarker(rng)
		&"headshot": return _headshot(rng)
		&"kill_confirm": return _kill_confirm(rng)
		&"player_hurt": return _player_hurt(rng)
		&"enemy_hurt": return _enemy_hurt(rng)
		&"enemy_death": return _enemy_death(rng)
		&"impact_concrete": return _impact_concrete(rng)
		&"impact_metal": return _impact_metal(rng)
		&"impact_flesh": return _impact_flesh(rng)
	return PackedFloat32Array()


# --- Sounds ----------------------------------------------------------------------------
# Times and decays are in seconds, filters in Hz. Layers are summed, then normalized.

static func _rifle_shot(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := _silence(1.0)
	_n_wave(out, 0.0, 0.0007, 1.0)  # shock front: the instant "crack"
	_noise(out, rng, 0.0, 0.004, NYQUIST, 1800.0, 1.2, 0.0002)  # crack / muzzle hiss
	_noise(out, rng, 0.0, 0.035, 4000.0, 150.0, 1.0, 0.0004, 1200.0)  # blast body
	_noise(out, rng, 0.0, 0.05, 500.0, 60.0, 0.6, 0.001)  # low boom
	_tone(out, 0.0, 120.0, 62.0, 0.02, 0.045, 0.6)  # chest thump
	_clack(out, rng, 0.03, 0.12, PackedFloat32Array([2730.0, 4180.0]), 0.02)  # bolt carrier
	_ring(out, 0.04, 820.0, 0.05, 0.03)  # buffer spring
	# Clip the blast like a real shot overloads ears and mics; the tail stays clean.
	_saturate(out, 0.25, 2.2)
	_echoes(out, 0.15, [
		Vector2(0.043, 0.34), Vector2(0.067, 0.27), Vector2(0.094, 0.24), Vector2(0.131, 0.18),
		Vector2(0.177, 0.14), Vector2(0.236, 0.10), Vector2(0.302, 0.07),
	], 3500.0)
	_noise(out, rng, 0.02, 0.22, 3000.0, 60.0, 0.3, 0.04, 600.0)  # yard reverb, darkening
	return out


static func _enemy_shot(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := _silence(1.2)
	# Same rifle ~50 m away: air eats the highs, bass carries, walls add more echo than blast.
	_noise(out, rng, 0.0, 0.002, 3500.0, 1200.0, 0.25, 0.0004)
	_noise(out, rng, 0.0, 0.025, 1800.0, 120.0, 0.9, 0.0004, 700.0)
	_noise(out, rng, 0.0, 0.06, 400.0, 50.0, 0.5, 0.001)
	_tone(out, 0.0, 95.0, 55.0, 0.03, 0.05, 0.4)
	_echoes(out, 0.15, [
		Vector2(0.031, 0.50), Vector2(0.058, 0.45), Vector2(0.089, 0.38), Vector2(0.12, 0.33),
		Vector2(0.16, 0.27), Vector2(0.21, 0.20), Vector2(0.28, 0.14), Vector2(0.37, 0.10),
	], 1800.0)
	_noise(out, rng, 0.03, 0.26, 1800.0, 50.0, 0.35, 0.08, 300.0)
	return out


static func _dry_fire(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := _silence(0.15)
	_noise(out, rng, 0.0, 0.0008, 7000.0, 1500.0, 0.3)  # trigger breaks
	_clack(out, rng, 0.03, 0.8, PackedFloat32Array([3150.0, 4870.0, 6920.0]), 0.012)  # hammer
	_ring(out, 0.03, 1400.0, 0.006, 0.12)
	return out


static func _reload_out(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := _silence(0.35)
	_clack(out, rng, 0.0, 0.5, PackedFloat32Array([2300.0, 3700.0]), 0.008)  # release button
	_grains(out, rng, 0.02, 0.1, 900.0, 5000.0, 1500.0, 0.2, 0.0)  # mag sliding out
	_noise(out, rng, 0.02, 0.03, 4000.0, 1200.0, 0.1, 0.04)
	_clack(out, rng, 0.12, 0.7, PackedFloat32Array([1250.0, 2650.0, 3900.0]), 0.025)  # clears the well
	_tone(out, 0.12, 330.0, 280.0, 0.01, 0.015, 0.25)  # polymer magazine body
	return out


static func _reload_in(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := _silence(0.32)
	_grains(out, rng, 0.0, 0.07, 1100.0, 5500.0, 1400.0, 0.32, 0.0)  # mag sliding in
	_noise(out, rng, 0.0, 0.025, 3500.0, 1000.0, 0.15, 0.04)
	_clack(out, rng, 0.075, 1.0, PackedFloat32Array([1650.0, 2900.0, 4450.0, 6100.0]), 0.03)  # seats
	_tone(out, 0.075, 240.0, 175.0, 0.008, 0.025, 0.45)
	_clack(out, rng, 0.092, 0.35, PackedFloat32Array([3300.0, 5200.0]), 0.008)  # catch snaps over
	return out


static func _bolt(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := _silence(0.5)
	_clack(out, rng, 0.0, 0.7, PackedFloat32Array([2100.0, 3400.0]), 0.01)  # handle unlatches
	_grains(out, rng, 0.01, 0.1, 1400.0, 6000.0, 1800.0, 0.4, 0.0)  # carrier slides back
	_noise(out, rng, 0.012, 0.035, 5000.0, 1500.0, 0.18, 0.05)
	_clack(out, rng, 0.115, 0.8, PackedFloat32Array([1900.0, 3300.0, 5100.0]), 0.015)  # rear stop
	_grains(out, rng, 0.205, 0.02, 2000.0, 6000.0, 1800.0, 0.2, 0.0)  # spring drives it home
	_clack(out, rng, 0.225, 1.0, PackedFloat32Array([1350.0, 2480.0, 3720.0, 5230.0, 7010.0]), 0.055)
	_tone(out, 0.225, 210.0, 150.0, 0.01, 0.03, 0.5)  # heavy carrier mass
	_grains(out, rng, 0.23, 0.08, 300.0, 7000.0, 2000.0, 0.06, 1.0)
	return out


static func _footstep(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := _silence(0.22)
	var heel := rng.randf_range(0.85, 1.15)
	var toe := rng.randf_range(0.035, 0.055)
	# Rubber sole on concrete: the heel is a dull low-passed knock, the grit gives "concrete".
	_noise(out, rng, 0.0, 0.009, 1100.0 * heel, 70.0, 0.8 * heel, 0.001)
	_tone(out, 0.0, 100.0 * heel, 70.0, 0.01, 0.018, 0.18)
	_grains(out, rng, 0.004, 0.07, 1800.0, 6500.0, 1800.0, 0.18, 1.0)
	_noise(out, rng, toe, 0.007, 1800.0, 180.0, 0.45 * rng.randf_range(0.7, 1.1), 0.0015)
	_noise(out, rng, toe - 0.01, 0.022, 3200.0, 900.0, 0.06, 0.012)  # sole scuffs
	return out


static func _land(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := _silence(0.4)
	_noise(out, rng, 0.0, 0.014, 1000.0, 45.0, 0.9, 0.0015)
	_noise(out, rng, 0.013, 0.012, 1100.0, 45.0, 0.6, 0.0015)  # second foot
	_tone(out, 0.0, 120.0, 52.0, 0.025, 0.04, 0.55)
	_grains(out, rng, 0.0, 0.09, 2200.0, 6500.0, 1800.0, 0.2, 1.0)
	_noise(out, rng, 0.005, 0.04, 1600.0, 300.0, 0.12, 0.01)  # clothing
	_rattle(out, rng, 0.012, 0.22, 4, 0.06)
	return out


static func _hitmarker(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := _silence(0.08)
	_noise(out, rng, 0.0, 0.0012, NYQUIST, 2500.0, 0.6, 0.0001)
	_modes(out, 0.0, PackedFloat32Array([3400.0, 5150.0]), 0.006, 0.5)
	_ring(out, 0.0, 1900.0, 0.003, 0.2)
	return out


static func _headshot(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := _silence(0.4)
	_noise(out, rng, 0.0, 0.001, NYQUIST, 3000.0, 0.6, 0.0001)
	_noise(out, rng, 0.0, 0.008, 1200.0, 100.0, 0.3)  # the hit itself, under the ping
	# 3920/3937 Hz are near-twins: they beat slowly, like a real helmet shell.
	_modes(out, 0.0, PackedFloat32Array([3920.0, 3937.0, 5810.0, 8150.0]), 0.09, 0.3)
	return out


static func _kill_confirm(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := _silence(0.3)
	_noise(out, rng, 0.0, 0.0012, NYQUIST, 2500.0, 0.8, 0.0001)
	_ring(out, 0.0, 3800.0, 0.006, 0.6)
	_tone(out, 0.004, 150.0, 68.0, 0.02, 0.05, 0.8)
	_noise(out, rng, 0.004, 0.016, 900.0, 40.0, 0.6, 0.001)
	return out


static func _player_hurt(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := _silence(0.35)
	_noise(out, rng, 0.0, 0.025, 700.0, 60.0, 1.0, 0.002)
	_noise(out, rng, 0.0, 0.006, 1800.0, 300.0, 0.35, 0.0005)  # the blow lands
	_tone(out, 0.0, 88.0, 52.0, 0.03, 0.07, 0.5)
	_noise(out, rng, 0.004, 0.03, 2600.0, 700.0, 0.15, 0.008)  # clothing and kit
	return out


static func _enemy_hurt(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := _silence(0.25)
	var v := rng.randf_range(0.88, 1.12)
	_noise(out, rng, 0.0, 0.01, 1200.0 * v, 90.0, 1.0, 0.0006)
	_tone(out, 0.0, 165.0 * v, 95.0, 0.012, 0.026, 0.35)
	_noise(out, rng, 0.006, 0.03, 3000.0, 900.0, 0.12, 0.012)
	_rattle(out, rng, 0.01, 0.12, 1, 0.05)
	return out


static func _enemy_death(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := _silence(0.8)
	_noise(out, rng, 0.0, 0.02, 1000.0, 50.0, 0.6, 0.002)  # knees hit
	_tone(out, 0.0, 110.0, 65.0, 0.02, 0.04, 0.3)
	_noise(out, rng, 0.06, 0.06, 2000.0, 400.0, 0.12, 0.05)  # body folds
	_noise(out, rng, 0.28, 0.035, 800.0, 40.0, 1.0, 0.003)  # torso slams down
	_tone(out, 0.28, 95.0, 48.0, 0.03, 0.08, 0.55)
	_rattle(out, rng, 0.0, 0.45, 6, 0.08)
	var rifle := PackedFloat32Array([880.0, 1730.0, 2950.0, 4420.0])
	_noise(out, rng, 0.36, 0.003, 7000.0, 600.0, 0.6)  # dropped rifle hits...
	_modes(out, 0.36, rifle, 0.06, 0.3)
	_noise(out, rng, 0.47, 0.002, 7000.0, 800.0, 0.25)  # ...and bounces once
	_modes(out, 0.47, rifle, 0.045, 0.12)
	return out


static func _impact_concrete(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := _silence(0.3)
	var v := rng.randf_range(0.85, 1.15)
	_noise(out, rng, 0.0, 0.0015, NYQUIST, 1500.0, 1.0, 0.0001)  # crack
	_noise(out, rng, 0.0, 0.006, 3000.0 * v, 350.0, 0.5, 0.0003)  # chunk breaks off
	_tone(out, 0.0, 650.0 * v, 430.0 * v, 0.003, 0.006, 0.25)
	_grains(out, rng, 0.012, 0.2, 700.0, 7000.0, 1500.0, 0.22, 1.0)  # chips and grit fall
	_noise(out, rng, 0.005, 0.04, 6000.0, 2500.0, 0.06, 0.012)  # dust
	return out


static func _impact_metal(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := _silence(0.55)
	var v := rng.randf_range(0.9, 1.1)
	_noise(out, rng, 0.0, 0.0015, NYQUIST, 900.0, 0.9, 0.0001)
	_modes(out, 0.0, PackedFloat32Array([1180.0 * v, 2210.0 * v, 3460.0 * v, 4970.0 * v]), 0.12, 0.25)
	_ricochet(out, rng, 0.006, rng.randf_range(3200.0, 4000.0), rng.randf_range(1200.0, 1600.0), 0.35)
	return out


static func _impact_flesh(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := _silence(0.22)
	var v := rng.randf_range(0.9, 1.1)
	_noise(out, rng, 0.0, 0.012, 1100.0 * v, 60.0, 1.0, 0.0005)
	_tone(out, 0.0, 135.0 * v, 80.0, 0.012, 0.03, 0.4)
	_noise(out, rng, 0.0, 0.003, 3500.0, 1200.0, 0.3, 0.0003)  # wet slap
	return out


# --- Building blocks (all add into `out`) -----------------------------------------------
# Layers stop after 5 decay time constants (-43 dB): later samples are inaudible but cost time.

static func _silence(seconds: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(seconds * RATE))
	out.fill(0.0)
	return out


## Filtered noise burst: rises over `attack`, then decays exponentially (time constant
## `decay`). The lowpass can glide toward `lp_end`, the way a shot's tail darkens with time.
static func _noise(out: PackedFloat32Array, rng: RandomNumberGenerator, at: float, decay: float,
		lp: float, hp: float, gain: float, attack: float = 0.0005, lp_end: float = 0.0) -> void:
	var start := int(at * RATE)
	var stop := mini(out.size(), start + int((attack + decay * 5.0) * RATE))
	if stop <= start:
		return
	var white := _white_noise()
	var shift := rng.randi_range(0, NOISE_SIZE - (stop - start)) - start
	var fall := exp(-1.0 / (decay * RATE))
	var rise := _smoothing(attack)
	var a := _coef(lp)
	var a_end := _coef(lp_end) if lp_end > 0.0 else a
	var h := _coef(hp)
	var target := gain * _band_gain(lp, hp)
	var env := 0.0
	var l1 := 0.0
	var l2 := 0.0
	var hs := 0.0
	for i in range(start, stop):
		target *= fall
		env += rise * (target - env)
		a = a_end + (a - a_end) * fall
		# Two one-poles in series (12 dB/oct): a single pole leaves noise sounding hissy.
		l1 += a * (white[i + shift] * env - l1)
		l2 += a * (l1 - l2)
		hs += h * (l2 - hs)
		out[i] += l2 - hs


## Sine gliding exponentially from `f0` to `f1` (time constant `glide`) under an exponential
## decay: thumps and body resonances. Starting at zero phase gives a natural quarter-period
## attack, so there is no click and no separate attack stage.
static func _tone(out: PackedFloat32Array, at: float, f0: float, f1: float, glide: float,
		decay: float, gain: float) -> void:
	var start := int(at * RATE)
	var stop := mini(out.size(), start + int(decay * 5.0 * RATE))
	var fall := exp(-1.0 / (decay * RATE))
	var bend := exp(-1.0 / (glide * RATE))
	var step := TAU * f0 / RATE
	var step_end := TAU * f1 / RATE
	var phase := 0.0
	var env := gain
	for i in range(start, stop):
		step = step_end + (step - step_end) * bend
		phase += step
		out[i] += sin(phase) * env
		env *= fall


## One vibration mode of a struck object: an exponentially decaying sine, computed with the
## two-pole resonator recurrence (two multiplies per sample instead of a sin() call).
static func _ring(out: PackedFloat32Array, at: float, hz: float, decay: float, gain: float) -> void:
	if hz >= NYQUIST:
		return
	var start := int(at * RATE)
	var w := TAU * hz / RATE
	var r := exp(-1.0 / (decay * RATE))
	var c := 2.0 * r * cos(w)
	var r2 := r * r
	var y := 0.0
	var y_prev := -gain * sin(w) / r
	for i in range(start, mini(out.size(), start + int(decay * 5.0 * RATE))):
		out[i] += y
		var y_next := c * y - r2 * y_prev
		y_prev = y
		y = y_next


## A struck metal part: inharmonic modes where higher partials die faster, as on real plates
## and bars. Same recurrence as `_ring`, with four modes side by side in one Vector4 so they
## share the per-sample cost.
static func _modes(out: PackedFloat32Array, at: float, freqs: PackedFloat32Array, decay: float,
		gain: float) -> void:
	var start := int(at * RATE)
	for first in range(0, freqs.size(), 4):
		var c := Vector4.ZERO
		var r2 := Vector4.ZERO
		var y := Vector4.ZERO
		var y_prev := Vector4.ZERO
		var longest := 0.0
		for lane in mini(4, freqs.size() - first):
			var k := first + lane
			if freqs[k] >= NYQUIST:
				continue
			var d := decay * pow(freqs[0] / freqs[k], 0.7)
			var w := TAU * freqs[k] / RATE
			var r := exp(-1.0 / (d * RATE))
			c[lane] = 2.0 * r * cos(w)
			r2[lane] = r * r
			y_prev[lane] = -gain / (1.0 + 0.5 * k) * sin(w) / r
			longest = maxf(longest, d)
		for i in range(start, mini(out.size(), start + int(longest * 5.0 * RATE))):
			out[i] += y.x + y.y + y.z + y.w
			var y_next := c * y - r2 * y_prev
			y_prev = y
			y = y_next


## Metal-on-metal contact: a sharp broadband tick plus the part ringing.
static func _clack(out: PackedFloat32Array, rng: RandomNumberGenerator, at: float, gain: float,
		freqs: PackedFloat32Array, decay: float) -> void:
	_noise(out, rng, at, 0.0015, NYQUIST, 500.0, gain, 0.0001)
	_modes(out, at, freqs, decay, gain * 0.35)


## Random micro-clicks: grit, falling debris, sliding friction. `rate` is clicks per second;
## `thin` = 1 makes them die out over `dur` (debris settling), 0 keeps them steady.
static func _grains(out: PackedFloat32Array, rng: RandomNumberGenerator, at: float, dur: float,
		rate: float, lp: float, hp: float, gain: float, thin: float) -> void:
	var start := int(at * RATE)
	var n := maxi(1, int(dur * RATE))
	var stop := mini(out.size(), start + n)
	if stop <= start:
		return
	var white := _white_noise()
	var shift := rng.randi_range(0, NOISE_SIZE - (stop - start)) - start
	var per_sample := rate / RATE
	var fall := exp(-1.0 / (0.0008 * RATE))
	var a := _coef(lp)
	var h := _coef(hp)
	var amp := gain * _band_gain(lp, hp)
	var next := start
	var env := 0.0
	var l1 := 0.0
	var l2 := 0.0
	var hs := 0.0
	for i in range(start, stop):
		if i >= next:
			env = amp * (0.2 + 0.8 * rng.randf())
			# Exponentially distributed gaps make the clicks a Poisson process, like real grit.
			var density := maxf(0.02, 1.0 - thin * (i - start) / n)
			next = i + 1 + int(-log(1.0 - rng.randf()) / (per_sample * density))
		l1 += a * (white[i + shift] * env - l1)
		l2 += a * (l1 - l2)
		hs += h * (l2 - hs)
		out[i] += l2 - hs
		env *= fall


## Loose gear knocking about: sparse clicks plus a few small metal pings, mostly early.
static func _rattle(out: PackedFloat32Array, rng: RandomNumberGenerator, at: float, dur: float,
		pings: int, gain: float) -> void:
	_grains(out, rng, at, dur, 260.0, 7000.0, 2200.0, gain, 1.0)
	for i in pings:
		var t := at + dur * rng.randf() * rng.randf()
		_ring(out, t, rng.randf_range(2300.0, 5200.0), rng.randf_range(0.006, 0.018),
				gain * rng.randf_range(0.3, 0.8))


## Ricochet whine: the tumbling bullet's tone falls in pitch as it flies off and slows.
static func _ricochet(out: PackedFloat32Array, rng: RandomNumberGenerator, at: float, f0: float,
		f1: float, gain: float) -> void:
	var start := int(at * RATE)
	var stop := mini(out.size(), start + int(0.45 * RATE))
	var fall := exp(-1.0 / (0.09 * RATE))
	var rise := _smoothing(0.008)
	var bend := exp(-1.0 / (0.12 * RATE))
	var step := TAU * f0 / RATE
	var step_end := TAU * f1 / RATE
	# The tumble wobble (40-70 Hz) is an undamped resonator: cheaper than a second sin().
	var w := TAU * rng.randf_range(40.0, 70.0) / RATE
	var spin := 2.0 * cos(w)
	var wobble := 0.0
	var wobble_prev := -0.25 * sin(w)
	var phase := 0.0
	var target := gain
	var env := 0.0
	for i in range(start, stop):
		target *= fall
		env += rise * (target - env)
		step = step_end + (step - step_end) * bend
		phase += step
		var s := sin(phase)
		# s^3 adds odd harmonics, the slightly buzzy edge of a real whine.
		out[i] += (s + 0.35 * s * s * s) * env * (0.75 + wobble)
		var wobble_next := spin * wobble - wobble_prev
		wobble_prev = wobble
		wobble = wobble_next


## Idealized N-wave: pressure jumps up, falls linearly below zero, then snaps back.
static func _n_wave(out: PackedFloat32Array, at: float, length: float, gain: float) -> void:
	var start := int(at * RATE)
	var n := maxi(2, int(length * RATE))
	for k in mini(n, out.size() - start):
		out[start + k] += gain * (1.0 - 2.0 * k / (n - 1))


## Early reflections off the yard walls: delayed, darker copies of the first `src` seconds.
## Each tap is Vector2(delay, gain).
static func _echoes(out: PackedFloat32Array, src: float, taps: Array[Vector2], lp: float) -> void:
	var n := mini(out.size(), int(src * RATE))
	var dry := out.slice(0, n)
	var a := _coef(lp)
	var l1 := 0.0
	var l2 := 0.0
	for i in n:
		l1 += a * (dry[i] - l1)
		l2 += a * (l1 - l2)
		dry[i] = l2
	for tap in taps:
		var offset := int(tap.x * RATE)
		for i in mini(n, out.size() - offset):
			out[offset + i] += dry[i] * tap.y


## Soft-clips the first `until` seconds so peaks come out `drive` times flatter. Quiet samples
## pass at unity (tanh(x*k)/k ~ x), so there is no level jump where clipping stops.
static func _saturate(out: PackedFloat32Array, until: float, drive: float) -> void:
	var n := mini(out.size(), int(until * RATE))
	var peak := 0.0
	for i in n:
		peak = maxf(peak, absf(out[i]))
	if peak <= 0.0:
		return
	var k := drive / peak
	for i in n:
		out[i] = tanh(out[i] * k) / k


## Shared white noise. Layers read it from a random offset, which is cheaper than calling
## randf() per sample and still deterministic per sound (the offset comes from its RNG).
static func _white_noise() -> PackedFloat32Array:
	if _white.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = 1
		_white.resize(NOISE_SIZE)
		for i in NOISE_SIZE:
			_white[i] = rng.randf() * 2.0 - 1.0
	return _white


## One-pole lowpass coefficient for a cutoff in Hz (0 = closed, 1 = fully open).
static func _coef(hz: float) -> float:
	return clampf(1.0 - exp(-TAU * hz / RATE), 0.0, 1.0)


## Coefficient that makes an envelope follow its target with time constant `seconds`.
static func _smoothing(seconds: float) -> float:
	return 1.0 if seconds <= 0.0 else 1.0 - exp(-1.0 / (seconds * RATE))


## Makes `gain` mean roughly the same loudness whatever the filter: narrow bands of noise
## carry less energy, so they are boosted by the square root of the bandwidth ratio.
static func _band_gain(lp: float, hp: float) -> float:
	return sqrt(NYQUIST / clampf(minf(lp, NYQUIST) - hp, 100.0, NYQUIST))


static func _to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var n := samples.size()
	var fade := mini(n, int(0.01 * RATE))
	for i in fade:
		samples[n - 1 - i] *= float(i) / fade
	# DC blocker (~17 Hz): decaying sines leave a small offset.
	var x_prev := 0.0
	var y := 0.0
	var peak := 0.0
	for i in n:
		var x := samples[i]
		y = x - x_prev + 0.995 * y
		x_prev = x
		samples[i] = y
		peak = maxf(peak, absf(y))
	var scale := PEAK * 32767.0 / peak if peak > 0.0 else 0.0
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		bytes.encode_s16(i * 2, int(samples[i] * scale))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	return wav
