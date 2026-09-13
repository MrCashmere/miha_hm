#!/usr/bin/env python3
"""鸿米家 .ets 静态检查合集。

这些检查都是在真实排错中积累的，每一条都对应过至少一个编译错误或运行时崩溃：

  括号平衡       脚本批量改代码后必查
  正向导入       import 了不存在的成员
  反向导入       用了却没 import（编译期才报 Cannot find name）
  成员声明       this.X 未在 struct 里声明
  模块级初始化   加载期调用外部 API —— 低版本设备启动闪退的元凶
  组件参数       自定义组件的入参在组件里不存在

用法：
    python3 scripts/check_ets.py [仓库根目录]
"""
import re
import sys
import glob
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ets_util import strip_comments  # noqa: E402

ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
FILES = sorted(glob.glob('entry/src/main/ets/**/*.ets', recursive=True))
fails = []


def load(path):
    return open(path, encoding='utf-8').read()


def strip_imports(raw):
    # 必须整条 import 一起剥掉：多行 import 只删第一行的话，
    # 剩下的 `} from '../models/XiaomiAuthInfo';` 会把模块名当成成员名。
    return re.sub(r'^import\b[\s\S]*?from\s*[\'"][^\'"]*[\'"];?', '', raw, flags=re.M)


# ---- 1. 括号平衡 ----
unbalanced = [f for f in FILES if load(f).count('{') != load(f).count('}')]
print(f'  {"✓" if not unbalanced else "✗"} 括号平衡        {len(FILES)} 个文件，不平衡 {len(unbalanced)}')
if unbalanced:
    fails.append(('括号平衡', unbalanced))

# ---- 2. 导入双向检查 ----
exports = {}
for f in FILES:
    text = strip_comments(load(f))
    names = set(re.findall(
        r'^export\s+(?:const|let|function|class|interface|enum|type)\s+([A-Za-z_]\w*)', text, re.M))
    for grp in re.findall(r'^export\s*\{([^}]*)\}', text, re.M):
        names |= {x.strip().split(' as ')[-1].strip() for x in grp.split(',') if x.strip()}
    exports[os.path.basename(f)[:-4]] = names

missing_import = []
for f in FILES:
    raw = load(f)
    imported = set()
    for grp in re.findall(r'^import\s*\{([^}]*)\}\s*from', raw, re.M):
        imported |= {x.strip().split(' as ')[-1].strip() for x in grp.split(',') if x.strip()}
    body = strip_comments(strip_imports(raw))
    local = set(re.findall(
        r'\b(?:function|const|let|var|class|interface|enum|type|struct)\s+([A-Za-z_]\w*)', body))
    local |= set(re.findall(
        r'^\s*(?:private\s+|public\s+|static\s+|async\s+|readonly\s+)*([A-Za-z_]\w*)\s*[(:=]', body, re.M))
    for mod, names in exports.items():
        if os.path.basename(f)[:-4] == mod:
            continue
        for n in names:
            if n not in imported and n not in local and re.search(r'\b' + re.escape(n) + r'\b', body):
                missing_import.append(f'{f}: {n}（来自 {mod}）')

print(f'  {"✓" if not missing_import else "✗"} 反向导入        用了却没 import: {len(missing_import)}')
for x in missing_import[:5]:
    print(f'        {x}')
if missing_import:
    fails.append(('反向导入', missing_import))

# ---- 3. this.X 成员声明 ----
BUILTIN = {
    'getUIContext', 'aboutToAppear', 'aboutToDisappear', 'onPageShow', 'onPageHide',
    'onBackPress', 'onDidBuild', 'onWillApplyTheme', 'onLayout', 'onMeasure', 'onDraw',
    'onConfigurationUpdate', 'getUniqueId', 'queryNavDestinationInfo', 'getPreviewParams',
    'build', 'context',
}
member_bad = []


def structs(text):
    for m in re.finditer(r'(@Component\b[\s\S]{0,120}?)?struct\s+([A-Za-z_]\w*)\s*\{', text):
        start, depth, i = m.end(), 1, m.end()
        while i < len(text) and depth > 0:
            if text[i] == '{':
                depth += 1
            elif text[i] == '}':
                depth -= 1
            i += 1
        yield m.group(2), text[start:i - 1]


for f in FILES:
    for sname, body in structs(strip_comments(load(f))):
        declared, depth = set(), 0
        for line in body.split('\n'):
            if depth == 0:
                cleaned = re.sub(r'^(@\w+(\([^)]*\))?\s*)+', '', line.strip())
                m = re.match(
                    r'(?:private\s+|public\s+|static\s+|readonly\s+|async\s+)*([A-Za-z_]\w*)\s*[:(=]', cleaned)
                if m:
                    declared.add(m.group(1))
            depth += line.count('{') - line.count('}')
            if depth < 0:
                depth = 0
        for used in set(re.findall(r'\bthis\.([A-Za-z_]\w*)', body)):
            if used not in declared and used not in BUILTIN:
                member_bad.append(f'{f} [{sname}] this.{used}')

print(f'  {"✓" if not member_bad else "✗"} 成员声明        未声明的 this.X: {len(member_bad)}')
for x in member_bad[:5]:
    print(f'        {x}')
if member_bad:
    fails.append(('成员声明', member_bad))

# ---- 4. 模块级初始化（低版本设备闪退元凶）----
DECL = re.compile(r'^\s*(?:export\s+)?(?:const|let|var)\s+([A-Za-z_]\w*)\s*(?::[^=]+)?=\s*(.+)$')
SAFE = re.compile(r'^(?:[\'"`\d\[\{]|true$|false$|null$|undefined$)')
# ES 内建构造器：纯语言层，取不到任何平台 API，模块加载期调用不可能闪退。
# 只有这一类才放行；`uiMaterial.*` / `deviceInfo.*` 这种平台 API 必须继续拦。
BUILTIN_CTORS = frozenset((
    'Array', 'Object', 'String', 'Number', 'Boolean', 'Math', 'JSON',
    'Map', 'Set', 'WeakMap', 'WeakSet', 'Promise', 'RegExp', 'Error'
))
init_bad = []
for f in FILES:
    text = strip_comments(load(f))
    local = set(re.findall(r'\b(?:class|struct|interface|enum)\s+([A-Za-z_]\w*)', text))
    depth = 0
    for n, line in enumerate(text.split('\n'), 1):
        if depth == 0:
            m = DECL.match(line)
            if m and not SAFE.match(m.group(2).strip()):
                calls = [c for c in re.findall(
                    r'\b([A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)*)\s*\(', m.group(2))
                    if c not in BUILTIN_CTORS
                    and c not in local]
                if calls:
                    init_bad.append(f'{f}:{n}  {m.group(1)} = {m.group(2).strip()[:60]}  调用 {calls}')
        depth += line.count('{') - line.count('}')
        if depth < 0:
            depth = 0

print(f'  {"✓" if not init_bad else "✗"} 模块级初始化    加载期调用外部 API: {len(init_bad)}')
for x in init_bad[:5]:
    print(f'        {x}')
if init_bad:
    fails.append(('模块级初始化', init_bad))

# ---- 5. 组件参数 ----
prop_bad = []
for f in FILES:
    text = strip_comments(load(f))
    for m in re.finditer(r'(@Component\b[\s\S]{0,120}?)?struct\s+([A-Za-z_]\w*)\s*\{', text):
        name = m.group(2)
        start, depth, i = m.end(), 1, m.end()
        while i < len(text) and depth > 0:
            if text[i] == '{':
                depth += 1
            elif text[i] == '}':
                depth -= 1
            i += 1
        body = text[start:i - 1]
        props = set(re.findall(r'@Prop\s+([A-Za-z_]\w*)', body))
        props |= set(re.findall(
            r'^\s*(?:@\w+(?:\([^)]*\))?\s+)*([A-Za-z_]\w*)\s*:', body, re.M))
        exports.setdefault('__props__', set())
        exports['__props__'] = exports.get('__props__', set()) | props
        globals()['__struct_props__'] = globals().get('__struct_props__', {})
        globals()['__struct_props__'][name] = props

struct_props = globals().get('__struct_props__', {})
for f in FILES:
    raw = load(f)
    imported_structs = set()
    for grp in re.findall(r'^import\s*\{([^}]*)\}\s*from', raw, re.M):
        imported_structs |= {x.strip().split(' as ')[-1].strip() for x in grp.split(',') if x.strip()}
    text = strip_comments(raw)
    for m in re.finditer(r'([A-Za-z_]\w*)\s*\(\s*\{', text):
        comp = m.group(1)
        if comp not in struct_props or comp not in imported_structs:
            continue
        j, depth2 = m.end(), 1
        while j < len(text) and depth2 > 0:
            if text[j] == '{':
                depth2 += 1
            elif text[j] == '}':
                depth2 -= 1
            j += 1
        # 只取**顶层**键：嵌套对象里的键（如 cardMargin: { left: 4 } 的 left）
        # 不是组件入参，按正则一把梭会误报。
        args = set()
        depth3 = 0
        k = m.end()
        while k < j - 1:
            ch = text[k]
            if ch in '{[(':
                depth3 += 1
            elif ch in '}])':
                depth3 -= 1
            elif depth3 == 0 and (ch.isalpha() or ch == '_'):
                km = re.match(r'([A-Za-z_]\w*)\s*:', text[k:])
                if km:
                    # 前一个非空字符是 '.' 说明这是属性访问而不是键：
                    # `tint: x ? HwColor.online : HwColor.textSecondary` 里的 online
                    # 后面也跟冒号，不排除会误报成入参。
                    # 命中与否都要整体跳过这段，否则会从标识符第二个字符重新匹配，
                    # 报出 `nline` 这种半截名字。
                    if not text[:k].rstrip().endswith('.'):
                        args.add(km.group(1))
                    k += len(km.group(0))
                    continue
            k += 1
        for a in args:
            if a not in struct_props[comp]:
                line = text[:m.start()].count('\n') + 1
                prop_bad.append(f'{f}:{line}  {comp}({{ {a} }}) 组件里没有该成员')

print(f'  {"✓" if not prop_bad else "✗"} 组件参数        不存在的入参: {len(prop_bad)}')
for x in prop_bad[:5]:
    print(f'        {x}')
if prop_bad:
    fails.append(('组件参数', prop_bad))

print()
if fails:
    print(f'检查未通过：{len(fails)} 项')
    sys.exit(1)
print('全部检查通过 ✓')
