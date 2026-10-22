extends Node
## Sound effects and haptics, gated by settings. Autoloaded as `Feedback`.
## Drop .ogg/.wav files in res://audio/ named after the sfx (e.g. "tap.ogg").

const AUDIO_DIR := "res://audio/"
const POOL_SIZE := 6

var _players: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}
var _next := 0


func _ready() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


func sfx(sfx_name: String) -> void:
	if not Save.get_setting("sound"):
		return
	var stream := _get_stream(sfx_name)
	if stream == null:
		return
	var p := _players[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = stream
	p.play()


func vibrate(ms: int = 30) -> void:
	if Save.get_setting("vibration"):
		Input.vibrate_handheld(ms)


func _get_stream(sfx_name: String) -> AudioStream:
	if not _streams.has(sfx_name):
		var stream: AudioStream = null
		for ext in ["ogg", "wav"]:
			var path := "%s%s.%s" % [AUDIO_DIR, sfx_name, ext]
			if ResourceLoader.exists(path):
				stream = load(path)
				break
		_streams[sfx_name] = stream
	return _streams[sfx_name]
