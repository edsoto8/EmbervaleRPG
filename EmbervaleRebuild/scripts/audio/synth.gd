class_name Synth
extends RefCounted
## Every sound in the game, synthesised in code as 16-bit mono PCM. Each recipe is a static function
## returning an AudioStreamWAV. Recipes that use randomness take their own RandomNumberGenerator, so
## slow ones can render on worker threads (AudioManager.PRERENDERED) without sharing RNG state.

const RATE := 22050


## Renders a slow recipe by name (worker-thread entry point).
static func render(recipe: String, rng: RandomNumberGenerator) -> AudioStreamWAV:
	match recipe:
		"menu_theme":
			return menu_theme(rng)
		"island_theme":
			return island_theme(rng)
		"surf_loop":
			return surf_loop(rng)
		"birds_loop":
			return birds_loop(rng)
	return null


# --- helpers ----------------------------------------------------------------------------------------

static func to_stream(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = bytes
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = samples.size()
	return s


static func buffer(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	b.fill(0.0)
	return b


static func midi(note: float) -> float:
	return 440.0 * pow(2.0, (note - 69.0) / 12.0)


## Attack/decay envelope at time t (seconds).
static func env(t: float, attack: float, decay: float) -> float:
	if t < 0.0:
		return 0.0
	if t < attack:
		return t / attack
	return exp(-(t - attack) / decay)


## Scales a buffer so its peak is `peak`.
static func normalise(b: PackedFloat32Array, peak: float = 0.9) -> PackedFloat32Array:
	var m := 0.0
	for v in b:
		m = maxf(m, absf(v))
	if m > 0.0:
		var k := peak / m
		for i in b.size():
			b[i] *= k
	return b


## Adds a tone into a buffer at a start time. The inner loops are specialised per waveform and the
## envelope is stepped incrementally, because this runs per sample in GDScript.
static func add_tone(b: PackedFloat32Array, start: float, freq: float, length: float, amp: float,
		wave: String = "sine", attack: float = 0.005, decay: float = 0.15) -> void:
	var i0 := int(start * RATE)
	var n := mini(int(length * RATE), b.size() - i0)
	if n <= 0:
		return
	var step := freq / RATE
	var attack_n := maxi(int(attack * RATE), 1)
	var fall := exp(-1.0 / (decay * RATE))
	var tail_n := int(0.02 * RATE)
	var e := 0.0
	var phase := 0.0
	var w := TAU * step
	for k in n:
		if k < attack_n:
			e = float(k) / attack_n
		else:
			e *= fall
		var g := e * amp
		if k > n - tail_n:
			g *= float(n - k) / tail_n
		var v: float
		if wave == "sine":
			v = sin(w * k)
		elif wave == "triangle":
			v = 4.0 * absf(phase - 0.5) - 1.0
		elif wave == "square":
			v = 0.5 if phase < 0.5 else -0.5
		elif wave == "saw":
			v = phase - 0.5
		else:
			var t := float(k) / RATE
			v = sin(w * k) + (0.35 * sin(2.0 * w * k) * exp(-t * 6.0) + 0.15 * sin(3.0 * w * k) * exp(-t * 9.0) if t < 0.6 else 0.0)
		b[i0 + k] += v * g
		phase += step
		if phase >= 1.0:
			phase -= 1.0
		if e < 0.0005 and k > attack_n:
			break


## Adds filtered noise (one-pole low-pass with cutoff 0..1) shaped by an envelope.
static func add_noise(b: PackedFloat32Array, rng: RandomNumberGenerator, start: float, length: float, amp: float,
		cutoff: float, attack: float = 0.002, decay: float = 0.05) -> void:
	var i0 := int(start * RATE)
	var lp := 0.0
	for k in int(length * RATE):
		var i := i0 + k
		if i >= b.size():
			break
		var t := float(k) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * cutoff
		b[i] += lp * env(t, attack, decay) * amp


# --- one-shots ----------------------------------------------------------------------------------------

static func click() -> AudioStreamWAV:
	var b := buffer(0.06)
	add_tone(b, 0.0, 1650.0, 0.05, 0.5, "sine", 0.001, 0.012)
	add_tone(b, 0.0, 820.0, 0.05, 0.3, "triangle", 0.001, 0.015)
	return to_stream(normalise(b, 0.6))


static func footstep(surface: String, rng: RandomNumberGenerator) -> AudioStreamWAV:
	var b := buffer(0.14)
	match surface:
		"wood":
			add_tone(b, 0.0, 190.0 + rng.randf() * 30.0, 0.12, 0.6, "sine", 0.002, 0.03)
			add_noise(b, rng, 0.0, 0.1, 0.35, 0.35, 0.001, 0.02)
		"stone":
			add_noise(b, rng, 0.0, 0.1, 0.6, 0.55, 0.001, 0.018)
			add_tone(b, 0.0, 420.0, 0.05, 0.15, "triangle", 0.001, 0.01)
		"sand":
			add_noise(b, rng, 0.0, 0.13, 0.55, 0.12, 0.01, 0.05)
		_:
			add_noise(b, rng, 0.0, 0.12, 0.6, 0.2, 0.004, 0.035)
	return to_stream(normalise(b, 0.5))


static func chop(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var b := buffer(0.3)
	var i0 := 0
	var phase := 0.0
	for k in int(0.22 * RATE):
		var t := float(k) / RATE
		var f := 160.0 * exp(-t * 9.0) + 60.0
		phase += f / RATE
		b[i0 + k] += sin(TAU * phase) * env(t, 0.001, 0.06) * 0.8
	add_noise(b, rng, 0.0, 0.2, 0.7, 0.6, 0.0005, 0.025)
	add_noise(b, rng, 0.03, 0.2, 0.25, 0.15, 0.005, 0.06)
	return to_stream(normalise(b, 0.85))


static func pickup() -> AudioStreamWAV:
	var b := buffer(0.3)
	add_tone(b, 0.0, midi(76), 0.12, 0.5, "triangle", 0.003, 0.06)
	add_tone(b, 0.08, midi(83), 0.2, 0.5, "triangle", 0.003, 0.08)
	return to_stream(normalise(b, 0.6))


static func dialogue_blip() -> AudioStreamWAV:
	var b := buffer(0.08)
	add_tone(b, 0.0, midi(72), 0.07, 0.4, "sine", 0.004, 0.025)
	add_tone(b, 0.0, midi(79), 0.07, 0.15, "sine", 0.004, 0.02)
	return to_stream(normalise(b, 0.45))


static func inventory(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var b := buffer(0.25)
	add_noise(b, rng, 0.0, 0.22, 0.5, 0.25, 0.02, 0.06)
	add_noise(b, rng, 0.07, 0.15, 0.3, 0.3, 0.01, 0.04)
	return to_stream(normalise(b, 0.5))


static func jingle() -> AudioStreamWAV:
	var b := buffer(1.2)
	var notes := [72, 76, 79, 84]
	for i in notes.size():
		add_tone(b, i * 0.11, midi(notes[i]), 0.9 - i * 0.1, 0.45, "pluck", 0.003, 0.35)
	add_tone(b, 0.33, midi(60), 0.8, 0.25, "triangle", 0.01, 0.4)
	return to_stream(normalise(b, 0.75))


static func level_up() -> AudioStreamWAV:
	var b := buffer(1.6)
	var notes := [67, 71, 74, 79, 83]
	for i in notes.size():
		add_tone(b, i * 0.09, midi(notes[i]), 1.0, 0.4, "pluck", 0.003, 0.4)
	add_tone(b, 0.45, midi(86), 1.1, 0.35, "triangle", 0.02, 0.5)
	return to_stream(normalise(b, 0.75))


static func fanfare() -> AudioStreamWAV:
	var b := buffer(3.2)
	var melody := [[0.0, 67, 0.22], [0.24, 67, 0.12], [0.38, 72, 0.4], [0.82, 76, 0.22], [1.06, 74, 0.22],
			[1.3, 76, 0.22], [1.54, 79, 1.4]]
	for n in melody:
		add_tone(b, n[0], midi(n[1]), n[2] + 0.25, 0.32, "square", 0.02, 0.6)
		add_tone(b, n[0], midi(n[1] - 12), n[2] + 0.25, 0.18, "saw", 0.02, 0.6)
	for chord in [[0.0, [48, 55, 64]], [1.54, [48, 52, 55, 60]]]:
		for note in chord[1]:
			add_tone(b, chord[0], midi(note), 1.6, 0.14, "triangle", 0.05, 0.9)
	return to_stream(normalise(b, 0.8))


static func splash(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var b := buffer(0.5)
	add_noise(b, rng, 0.0, 0.45, 0.7, 0.4, 0.005, 0.12)
	add_tone(b, 0.0, 600.0, 0.15, 0.1, "sine", 0.002, 0.04)
	return to_stream(normalise(b, 0.6))


static func fire(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var b := buffer(0.9)
	add_noise(b, rng, 0.0, 0.8, 0.4, 0.15, 0.1, 0.4)
	for k in 6:
		add_noise(b, rng, rng.randf() * 0.7, 0.03, 0.6, 0.8, 0.0005, 0.006)
	return to_stream(normalise(b, 0.55))


static func eat(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var b := buffer(0.45)
	for k in 3:
		add_noise(b, rng, k * 0.13, 0.08, 0.6, 0.3, 0.003, 0.03)
	return to_stream(normalise(b, 0.5))


static func coins() -> AudioStreamWAV:
	var b := buffer(0.35)
	add_tone(b, 0.0, 2100.0, 0.2, 0.3, "sine", 0.001, 0.05)
	add_tone(b, 0.05, 2650.0, 0.25, 0.3, "sine", 0.001, 0.06)
	add_tone(b, 0.1, 3100.0, 0.25, 0.2, "sine", 0.001, 0.06)
	return to_stream(normalise(b, 0.5))


static func swing(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var b := buffer(0.25)
	add_noise(b, rng, 0.0, 0.22, 0.6, 0.08, 0.06, 0.06)
	return to_stream(normalise(b, 0.4))


static func hit(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var b := buffer(0.25)
	add_noise(b, rng, 0.0, 0.2, 0.8, 0.25, 0.001, 0.04)
	add_tone(b, 0.0, 110.0, 0.2, 0.5, "sine", 0.001, 0.05)
	return to_stream(normalise(b, 0.7))


# --- loops (slow: rendered on worker threads) ---------------------------------------------------------

## Breaking waves: low-passed noise with slow swells. Starts and ends silent-ish for a clean loop.
static func surf_loop(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var seconds := 8.0
	var b := buffer(seconds)
	var lp := 0.0
	var lp2 := 0.0
	var n := b.size()
	for i in n:
		var t := float(i) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.08
		lp2 += (lp - lp2) * 0.2
		var swell := 0.35 + 0.65 * pow(0.5 - 0.5 * cos(TAU * t / 4.0), 2.0)
		b[i] = lp2 * swell
	_crossfade_loop(b, int(0.25 * RATE))
	return to_stream(normalise(b, 0.7), true)


## Birdsong: occasional chirps over silence.
static func birds_loop(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var seconds := 10.0
	var b := buffer(seconds)
	var t := 0.3
	while t < seconds - 0.6:
		var base := rng.randf_range(2200.0, 3600.0)
		var count := rng.randi_range(2, 5)
		for k in count:
			var start := t + k * rng.randf_range(0.07, 0.12)
			var i0 := int(start * RATE)
			var dur := int(rng.randf_range(0.05, 0.09) * RATE)
			var phase := 0.0
			var bend := rng.randf_range(-0.5, 0.6)
			for j in dur:
				var u := float(j) / dur
				var f := base * (1.0 + bend * u)
				phase += f / RATE
				if i0 + j < b.size():
					b[i0 + j] += sin(TAU * phase) * sin(PI * u) * 0.35
		t += rng.randf_range(0.6, 1.8)
	return to_stream(normalise(b, 0.45), true)


## Main menu theme: D major, 84 bpm, 8 bars of pad, bass and a pentatonic melody.
static func menu_theme(rng: RandomNumberGenerator) -> AudioStreamWAV:
	return _theme(rng, 84.0, [[62, 66, 69], [59, 62, 66], [55, 59, 62], [57, 61, 64]], 50,
			[74, 76, 78, 81, 83, 86], 0.9)


## Island theme: gentler, G major, 92 bpm.
static func island_theme(rng: RandomNumberGenerator) -> AudioStreamWAV:
	return _theme(rng, 92.0, [[55, 59, 62], [52, 55, 59], [48, 52, 55], [50, 54, 57]], 43,
			[67, 69, 71, 74, 76, 79], 0.6)


static func _theme(rng: RandomNumberGenerator, bpm: float, chords: Array, bass_root: int, scale: Array,
		melody_level: float) -> AudioStreamWAV:
	var beat := 60.0 / bpm
	var bars := 8
	var seconds := bars * 4 * beat
	var b := buffer(seconds)
	for bar in bars:
		var chord: Array = chords[(bar / 2) % chords.size()]
		var t0 := bar * 4 * beat
		for note in chord:
			add_tone(b, t0, midi(note), 4 * beat, 0.07, "triangle", 0.4, 3.0)
			add_tone(b, t0, midi(note) * 1.004, 4 * beat, 0.04, "triangle", 0.4, 3.0)
		var root: int = chord[0] - 12
		add_tone(b, t0, midi(root), 1.8 * beat, 0.16, "sine", 0.01, 0.6)
		add_tone(b, t0 + 2 * beat, midi(root + 7), 1.8 * beat, 0.12, "sine", 0.01, 0.6)
		for k in 4:
			add_tone(b, t0 + k * beat + beat * 0.5, midi(chord[k % chord.size()] + 12), beat * 0.9, 0.05, "pluck", 0.003, 0.25)
		var steps := [0, 1, 2, 3]
		for s in steps:
			if rng.randf() < 0.75:
				var n: int = scale[rng.randi_range(0, scale.size() - 1)]
				var length := beat * (1.0 if rng.randf() < 0.7 else 2.0)
				add_tone(b, t0 + s * beat, midi(n), length, 0.11 * melody_level, "pluck", 0.004, 0.45)
	_crossfade_loop(b, int(0.4 * RATE))
	return to_stream(normalise(b, 0.7), true)


## Blends the tail into the head so the loop point is seamless.
static func _crossfade_loop(b: PackedFloat32Array, n: int) -> void:
	var size := b.size()
	for k in n:
		var w := float(k) / n
		b[k] = b[k] * w + b[size - n + k] * (1.0 - w)
	b.resize(size - n)
