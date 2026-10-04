function v = voice_noteoff(v, note)
% VOICE_NOTEOF 对同音高的活跃声部发起 Release
for k = find([v.note] == note & [v.state] > 0)
    if v(k).state < 4, v(k).state = 4; end
end
end
