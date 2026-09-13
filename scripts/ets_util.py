"""剥掉 .ets 源码里的注释，供静态检查使用。

两个必须注意的点：

1. **不能误伤字符串。** 朴素写法 `line.split('//')[0]` 会在遇到字符串里的 `//` 时
   误删后面的代码（`if (this.sourceUri.startsWith('file://')) {` 的 `{` 会被一起删掉），
   导致大括号计数整体偏移、struct 主体被提前截断。真实踩过。

2. **保留换行。** 注释内容替换成空格而不是删掉，这样**字符偏移与行号都和原文件一致**，
   检查脚本报出来的行号可以直接拿去定位。早先直接删除注释，报的行号全是对不上的。
"""


def strip_comments(text):
    out = list(text)
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        nxt = text[i + 1] if i + 1 < n else ''
        if c == '/' and nxt == '*':
            end = text.find('*/', i + 2)
            end = n if end < 0 else end + 2
            for k in range(i, end):
                if out[k] != '\n':
                    out[k] = ' '
            i = end
            continue
        if c == '/' and nxt == '/':
            end = text.find('\n', i)
            end = n if end < 0 else end
            for k in range(i, end):
                out[k] = ' '
            i = end
            continue
        if c in ('"', "'", '`'):
            q = c
            i += 1
            while i < n:
                if text[i] == '\\':
                    i += 2
                    continue
                if text[i] == q:
                    i += 1
                    break
                i += 1
            continue
        i += 1
    return ''.join(out)
