extends Node
## Sound effects, music and haptics, gated by the settings toggles. Autoloaded as `Feedback`.
## Sound names are listed in SFX below and documented in CLAUDE.md; files live in res://audio/
## (made by tools/gen_audio.py, licence in audio/CREDITS.md).

const SFX_DIR := "res://audio/sfx/"
const MUSIC_DIR := "res://audio/music/"
const POOL_SIZE := 8
const MUSIC_DB := -9.0
const FADE := 0.8

## name -> [file, volume_db, pitch_jitter]. Jitter keeps repeated sounds from feeling machine-gunned.
const SFX := {
	"tap": ["tap", -4.0, 0.06],
	"select": ["select", -4.0, 0.04],
	"place": ["place", -3.0, 0.08],
	"pour": ["pour", -4.0, 0.05],
	"pop": ["pop", -4.0, 0.10],
	"merge": ["merge", -3.0, 0.06],
	"clear": ["clear", -3.0, 0.03],
	"star": ["star", -3.0, 0.0],
	"win": ["win", -2.0, 0.0],
	"fail": ["fail", -3.0, 0.0],
	"button": ["button", -4.0, 0.04],
	"back": ["back", -4.0, 0.04],
	"locked": ["locked", -4.0, 0.03],
	"unlock": ["unlock", -3.0, 0.0],
	"swoosh": ["swoosh", -6.0, 0.05],
}
## Old names still used in existing code.
const ALIASES := {"lose": "fail"}

var _players: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}
var _next := 0
var _music: Array[AudioStreamPlayer] = []  # two players, crossfaded
var _music_front := 0
var _track := ""  # track that should be playing when music is on ("" = none)
var _warned: Dictionary = {}


func _ready() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.volume_db = -80.0
		add_child(m)
		_music.append(m)
	Save.settings_changed.connect(_on_setting_changed)


## Plays a named effect (see SFX). Silent when the sound toggle is off.
## pitch scales the playback rate, e.g. rising notes for a run of stars.
func sfx(sfx_name: String, pitch := 1.0) -> void:
	if not Save.get_setting("sound"):
		return
	sfx_name = ALIASES.get(sfx_name, sfx_name)
	if not SFX.has(sfx_name):
		if not _warned.has(sfx_name):
			_warned[sfx_name] = true
			push_warning("Feedback.sfx: unknown sound '%s'" % sfx_name)
		return
	var def: Array = SFX[sfx_name]
	var stream := _stream(SFX_DIR, def[0])
	if stream == null:
		return
	var p := _players[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = stream
	p.volume_db = def[1]
	p.pitch_scale = pitch * (1.0 + randf_range(-def[2], def[2]))
	p.play()


## Loops a music track ("menu" or "game") with a crossfade. Safe to call repeatedly with the same track.
func play_music(track: String) -> void:
	if track == _track:
		return
	_track = track
	_apply_music()


func stop_music() -> void:
	play_music("")


func vibrate(ms: int = 30) -> void:
	if Save.get_setting("vibration"):
		Input.vibrate_handheld(ms)


func _on_setting_changed(key: String, _value: Variant) -> void:
	if key == "music":
		_apply_music()


func _apply_music() -> void:
	var want := _track if _track != "" and Save.get_setting("music") else ""
	var old := _music[_music_front]
	var stream: AudioStream = _stream(MUSIC_DIR, want, true) if want != "" else null
	if stream == old.stream and old.playing:
		return
	if want != "" and stream == null:
		want = ""
	_fade(old, -80.0, true)
	if want == "":
		return
	_music_front = 1 - _music_front
	var m := _music[_music_front]
	m.stream = stream
	m.volume_db = -80.0
	m.play()
	_fade(m, MUSIC_DB, false)


func _fade(p: AudioStreamPlayer, db: float, stop_after: bool) -> void:
	var tw := create_tween()
	tw.tween_property(p, "volume_db", db, FADE).set_trans(Tween.TRANS_SINE)
	if stop_after:
		tw.tween_callback(func():
			# Only stop if it was not brought back to the front in the meantime.
			if p != _music[_music_front] or _track == "" or not Save.get_setting("music"):
				p.stop())


func _stream(dir: String, file: String, loop := false) -> AudioStream:
	var path := "%s%s.ogg" % [dir, file]
	if not _streams.has(path):
		var s: AudioStream = load(path) if ResourceLoader.exists(path) else null
		if s is AudioStreamOggVorbis:
			s.loop = loop
		_streams[path] = s
	return _streams[path]
