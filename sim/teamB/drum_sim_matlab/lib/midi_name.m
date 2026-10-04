function nm = midi_name(m)
% MIDI_NAME  MIDI 音符号 -> 音名（如 60 -> C4）
names = {'C','C#','D','D#','E','F','F#','G','G#','A','A#','B'};
oct = floor(m/12) - 1;
nm = sprintf('%s%d', names{mod(m,12)+1}, oct);
end
