function export_mi(fname, data, width, radix)
% EXPORT_MI 导出高云 ROM 初始化 .mi 文件
%   fname  目标路径
%   data   整数数据（无符号或有符号）
%   width  数据位宽
%   radix  'HEX'（默认）
if nargin < 4, radix = 'HEX'; end
d = round(data(:));
if any(d < 0), d = d + 2^width; end          % 有符号转无符号
fid = fopen(fname,'w');
fprintf(fid, 'WIDTH = %d;\n', width);
fprintf(fid, 'DEPTH = %d;\n\n', length(d));
fprintf(fid, 'ADDRESS_RADIX = %s;\n', radix);
fprintf(fid, 'DATA_RADIX = %s;\n\n', radix);
fprintf(fid, 'CONTENT BEGIN\n');
ndig = ceil(width/4);
for i = 1:length(d)
    fprintf(fid, '@%X %0*X;\n', i-1, ndig, d(i));
end
fprintf(fid, 'END;\n');
fclose(fid);
end
