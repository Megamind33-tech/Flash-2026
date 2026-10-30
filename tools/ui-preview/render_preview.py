#!/usr/bin/env python3
"""
Browser approximation of GRIDLINE's UI Toolkit screens, for design review without a Unity licence.
Converts UXML -> HTML and USS -> CSS (flexbox maps 1:1; -unity-* properties are translated), injects sample data
the controllers would bind, and screenshots with headless Chromium (Playwright). NOT a Unity render: fonts, layout
and colours match closely; Unity-specific rendering details (text metrics, AA) can differ slightly.
Usage: NODE_PATH=$(npm root -g) python3 render_preview.py <repo-root> <out-dir>
"""
import math, os, re, sys, xml.etree.ElementTree as ET

ROOT, OUT = sys.argv[1], sys.argv[2]
UI = os.path.join(ROOT, "Assets/Gridline/UI")
os.makedirs(OUT, exist_ok=True)

def uss_to_css(uss):
    css = uss
    css = re.sub(r'-unity-font-definition:\s*url\("\.\./Fonts/([^".]+)\.ttf"\);', r'font-family: "\1";', css)
    # Icons: USS tints a white bitmap; in CSS use the bitmap as a mask over the tint colour.
    # Inline as data URIs: Chromium refuses file:// mask images (CORS).
    import base64
    def icon(m):
        data = base64.b64encode(open(os.path.join(UI, "Icons", m.group(2)), "rb").read()).decode()
        uri = "data:image/png;base64," + data
        return m.group(1) + '-webkit-mask-image: url("%s"); mask-image: url("%s");' % (uri, uri)
    css = re.sub(r'(\.ic-[\w-]+\s*\{\s*)background-image:\s*url\("\.\./Icons/([^"]+)"\);', icon, css)
    # Alpha-ramp textures tinted black approximate as CSS gradients.
    css = re.sub(r'background-image: url\("\.\./Textures/ramp_right\.png"\);\s*-unity-background-image-tint-color: ([^;]+);', r'background-image: linear-gradient(90deg, transparent, \1 60%);', css)
    css = re.sub(r'background-image: url\("\.\./Textures/ramp_down\.png"\);\s*-unity-background-image-tint-color: ([^;]+);', r'background-image: linear-gradient(180deg, transparent, \1);', css)
    css = css.replace("-unity-background-image-tint-color", "background-color")
    css = re.sub(r'-unity-background-scale-mode:[^;]+;', '-webkit-mask-size: contain; -webkit-mask-repeat: no-repeat; -webkit-mask-position: center;', css)
    css = re.sub(r'-unity-text-align:\s*middle-center;', 'text-align: center; justify-content: center;', css)
    css = re.sub(r'-unity-text-align:\s*middle-right;', 'text-align: right; justify-content: center;', css)
    return css

def font_faces():
    out = []
    for f in sorted(os.listdir(os.path.join(UI, "Fonts"))):
        if f.endswith(".ttf"):
            out.append('@font-face { font-family: "%s"; src: url("%s/Fonts/%s"); }' % (f[:-4], UI, f))
    return "\n".join(out)

BASE_CSS = """
head, style, script { display: none !important; }
body * { box-sizing: border-box; display: flex; flex-direction: column; flex-shrink: 1; margin: 0; padding: 0; position: relative; }
svg, svg * { display: inline; }
html, body { width: 1920px; height: 1080px; overflow: hidden; }
body { background: #0b0d12; }
.label { white-space: nowrap; display: block; }
.uxml-root { position: absolute; inset: 0; }
"""

def inline_urls(style):
    import base64
    def rep(m):
        path = os.path.normpath(os.path.join(UI, "Uxml", m.group(1)))
        if not os.path.exists(path): return "url('')"
        mime = "image/jpeg" if path.endswith(".jpg") else "image/png"
        return "url('data:%s;base64,%s'); background-size: cover; background-position: center" % (mime, base64.b64encode(open(path, "rb").read()).decode())
    return re.sub(r"url\('([^']+)'\)", rep, style)

def convert(node):
    tag = node.tag.split('}')[-1]
    if tag == "Style": return ""
    attrs = node.attrib
    cls = attrs.get("class", "")
    name = attrs.get("name", "")
    style = inline_urls(attrs.get("style", ""))
    kids = "".join(convert(c) for c in node)
    text = attrs.get("text", "")
    if tag == "Label":
        return '<div class="label %s" id="%s" style="%s">%s</div>' % (cls, name, style, text)
    if tag == "Button":
        inner = ('<div class="label">%s</div>' % text if text else "") + kids
        return '<div class="unity-button %s" id="%s" style="%s">%s</div>' % (cls, name, style, inner)
    if tag == "Slider":
        return ('<div class="%s" id="%s" style="%s"><div class="unity-base-slider__drag-container" style="justify-content:center">'
                '<div class="unity-base-slider__tracker" style="width:100%%"></div>'
                '<div class="unity-base-slider__dragger" style="position:absolute;left:40%%;top:35px"></div></div></div>') % (cls, name, style)
    return '<div class="%s" id="%s" style="%s">%s</div>' % (cls, name, style, kids)

def page(uxml, extra_js, backdrop):
    tree = ET.parse(os.path.join(UI, "Uxml", uxml))
    body = "".join(convert(c) for c in tree.getroot())
    css = uss_to_css(open(os.path.join(UI, "Styles/Gridline.uss")).read())
    return ("<html><head><style>%s\n%s\n%s</style></head><body style=\"%s\"><div class=\"uxml-root\">%s</div>"
            "<script>%s</script></body></html>") % (font_faces(), BASE_CSS, css, backdrop, body, extra_js)

def circuit_svg(w, h, cars=None):
    pts = [(0,0),(120,0),(240,0),(330,0),(385,-12),(405,-55),(385,-98),(340,-110),(280,-104),(232,-128),(214,-180),(236,-240),(292,-276),(362,-292),(432,-288),(482,-318),(494,-378),(456,-420),(385,-432),(250,-432),(120,-432),(0,-428),(-48,-412),(-66,-382),(-96,-368),(-136,-358),(-190,-330),(-222,-272),(-214,-205),(-178,-155),(-196,-95),(-184,-36),(-132,-4),(-60,0)]
    dense = []
    n = len(pts)
    for i in range(n):
        p0, p1, p2, p3 = pts[i-1], pts[i], pts[(i+1)%n], pts[(i+2)%n]
        for k in range(8):
            t = k/8; t2, t3 = t*t, t*t*t
            dense.append(tuple(0.5*((2*p1[j])+(-p0[j]+p2[j])*t+(2*p0[j]-5*p1[j]+4*p2[j]-p3[j])*t2+(-p0[j]+3*p1[j]-3*p2[j]+p3[j])*t3) for j in range(2)))
    xs = [p[0] for p in dense]; ys = [p[1] for p in dense]
    pad = 14; sx = (w-2*pad)/(max(xs)-min(xs)); sy = (h-2*pad)/(max(ys)-min(ys)); s = min(sx, sy)
    ox = (w-(max(xs)-min(xs))*s)/2; oy = (h-(max(ys)-min(ys))*s)/2
    m = lambda p: (ox+(p[0]-min(xs))*s, h-oy-(p[1]-min(ys))*s)
    path = " ".join("%.1f,%.1f" % m(p) for p in dense)
    dots = ""
    for frac, col in (cars or []):
        x, y = m(dense[int(frac*len(dense)) % len(dense)])
        dots += '<circle cx="%.1f" cy="%.1f" r="8" fill="%s"/>' % (x, y, col)
    sx0, sy0 = m(dense[0])
    return ('<svg width="%d" height="%d" xmlns="http://www.w3.org/2000/svg"><polygon points="%s" fill="none" stroke="rgba(255,255,255,0.85)" '
            'stroke-width="6" stroke-linejoin="round"/><circle cx="%.1f" cy="%.1f" r="7" fill="#e1101e"/>%s</svg>') % (w, h, path, sx0, sy0, dots)

def rpm_svg(value):
    w, h = 330, 250; cx, cy, r = w/2, w/2+8, w/2-16
    def arc(a, b, col):
        a0 = math.radians(150+240*a); a1 = math.radians(150+240*b)
        large = 1 if (b-a)*240 > 180 else 0
        return '<path d="M %.1f %.1f A %.1f %.1f 0 %d 1 %.1f %.1f" stroke="%s" stroke-width="14" fill="none" stroke-linecap="round"/>' % (
            cx+r*math.cos(a0), cy+r*math.sin(a0), r, r, large, cx+r*math.cos(a1), cy+r*math.sin(a1), col)
    return ('<svg width="%d" height="%d" style="position:absolute;left:0;top:0">%s%s%s</svg>' %
            (w, h, arc(0, 1, "rgba(255,255,255,0.12)"), arc(0.86, 1, "rgba(225,16,30,0.35)"), arc(0, value, "#f3f5f8")))

RENDERS = os.environ.get("GL_RENDERS", os.path.join(ROOT, "docs/renders"))
def bg(name, fallback):
    path = os.path.join(RENDERS, name + ".png")
    if os.path.exists(path):
        import base64
        return "background: #000 url('data:image/png;base64,%s') center/cover no-repeat;" % base64.b64encode(open(path, "rb").read()).decode()
    return fallback

MENU_JS = """
document.getElementById('event-map').innerHTML = `%s`;
const set = (id, t) => { const e = document.getElementById(id); if (e) e.textContent = t; };
set('status-money', '$9,550'); set('status-name', 'ROOKIE'); set('rep-rank', '1');
document.getElementById('rep-fill').style.width = '80%%';
set('race-fee', '$250'); set('nui-subtitle', 'THE RACING LEAGUE'); set('nui-counter', '3 ITEMS');
set('nui-desc-text', 'Ashford Club Sprint\\nAshford Airfield Circuit · 2.36 km · 3 laps · 5 cars\\nWin $3,000 · Personal best 1:14.982');
document.getElementById('nui-desc-text').style.whiteSpace = 'pre-line';
set('version', 'v0.1.4  ·  Unity 6000.3.27f1');
""" % circuit_svg(180, 130)

SETTINGS_JS = MENU_JS + """
document.getElementById('page-main').classList.add('hidden');
document.getElementById('page-settings').classList.remove('hidden');
document.getElementById('event-map').classList.add('hidden');
document.getElementById('opt-steering').classList.add('nui__item--selected');
set('nui-subtitle', 'SETTINGS'); set('nui-counter', '7 ITEMS');
set('nui-desc-text', "Tap an option to change it. Tilt steering uses the phone's motion sensor; a Bluetooth controller also works.");
"""

HUD_JS = """
const set = (id, t) => { const e = document.getElementById(id); if (e) e.textContent = t; };
const rows = [['1','REYES','#1F4E8C','LEADER',false],['2','LINDQVIST','#B3261E','+0.8s',false],['3','YOU','#F0C850','+1.9s',true],['4','OKAFOR','#E0A100','+3.4s',false],['5','BRANDT','#2E7D32','+6.1s',false]];
const host = document.getElementById('tower-rows');
for (const r of rows) {
  const row = document.createElement('div'); row.className = 'board__row' + (r[4] ? ' board__row--player' : '');
  row.innerHTML = `<div class="label board__pos">${r[0]}</div><div class="board__swatch" style="background-color:${r[2]}"></div><div class="label board__name">${r[1]}</div><div class="label board__gap">${r[3]}</div>`;
  host.appendChild(row);
}
set('position', '3/5'); set('lap', '2/3'); set('lap-time', '00:41.27'); set('best-lap', '01:15.20');
set('speed', '187'); set('gear', '5');
document.getElementById('rpm-fill').style.width = '78%%';
document.getElementById('progress-fill').style.width = '35%%';
const rpm = document.getElementById('rpm');
for (let i = 0; i < 22; i++) { const s = document.createElement('div'); s.className = 'rpm-seg' + (i < 17 ? (i >= 19 ? ' rpm-seg--red' : ' rpm-seg--on') : ''); rpm.appendChild(s); }
document.getElementById('hud-map').innerHTML = `%s`;
set('big-text', 'FINAL LAP'); document.getElementById('big-text').classList.add('big-message__text--show');
""" % circuit_svg(324, 224, [(0.62, '#1F4E8C'), (0.6, '#B3261E'), (0.54, '#E0A100'), (0.5, '#2E7D32'), (0.57, '#F0C850')])

LIGHTS_JS = HUD_JS.replace("set('big-text', 'FINAL LAP');", "set('big-text', '2');").replace("set('lap', '2/3')", "set('lap', '1/3')").replace("set('speed', '187')", "set('speed', '0')").replace("set('gear', '5')", "set('gear', '1')")

RESULTS_JS = HUD_JS + """
document.getElementById('big-text').classList.remove('big-message__text--show');
document.getElementById('controls').classList.add('hidden');
document.getElementById('results').classList.remove('hidden');
set('results-title', '2ND PLACE');
set('results-sub', 'ASHFORD CLUB SPRINT  ·  ASHFORD AIRFIELD CIRCUIT  ·  3 LAPS');
const res = [['1','Mateo Reyes','Halden Motorsport','03:47.91','1:14.770',false,false],['2','Rookie','Privateer','+1.204','1:14.512',true,true],['3','Elin Lindqvist','Corsair Racing','+2.880','1:15.031',false,false],['4','Daniel Okafor','Vantor Engineering','+6.415','1:15.840',false,false],['5','Jonas Brandt','Northline GP','+9.002','1:16.207',false,false]];
const t = document.getElementById('results-rows');
for (const r of res) {
  const row = document.createElement('div'); row.className = 'res-row' + (r[5] ? ' res-row--player' : '');
  row.innerHTML = `<div class="label res-cell res-pos">${r[0]}</div><div class="res-name"><div class="label res-cell">${r[1]}</div><div class="label res-team">${r[2]}</div></div><div class="label res-cell res-time">${r[3]}</div><div class="label res-cell res-best ${r[6]?'res-best--fastest':''}">${r[4]}</div>`;
  t.appendChild(row);
}
const lines = [['Prize · 2ND','+$1,800','t-money'],['Fastest lap','+$250','t-money'],['Entry fee','-$250','t-red'],['Reputation','+10 REP','t-blue'],['Championship','+18 PTS','t-gold']];
const l = document.getElementById('reward-lines');
for (const x of lines) { const d = document.createElement('div'); d.className='reward-line'; d.innerHTML = `<div class="label reward-line__label">${x[0]}</div><div class="label reward-line__amount ${x[2]}">${x[1]}</div>`; l.appendChild(d); }
set('reward-balance', '$11,350');
"""

PAUSE_JS = HUD_JS + """
document.getElementById('big-text').classList.remove('big-message__text--show');
document.getElementById('pause').classList.remove('hidden');
set('pause-info', 'ASHFORD AIRFIELD CIRCUIT');
"""

MENU_BG = bg("showroom", "background: radial-gradient(ellipse at 72% 60%, #3a4250 0%, #1a1e26 45%, #0b0d12 100%);")
HUD_BG = bg("chase", "background: linear-gradient(180deg, #8fa3b8 0%, #b9c6d2 38%, #4b5148 39%, #2b2e30 70%, #1d1f21 100%);")
GRID_BG = bg("grid-start", HUD_BG)

shots = [("menu", "MainMenu.uxml", MENU_JS, MENU_BG), ("settings", "MainMenu.uxml", SETTINGS_JS, MENU_BG),
         ("hud", "RaceHud.uxml", HUD_JS, HUD_BG), ("countdown", "RaceHud.uxml", LIGHTS_JS, GRID_BG),
         ("pause", "RaceHud.uxml", PAUSE_JS, HUD_BG), ("results", "RaceHud.uxml", RESULTS_JS, HUD_BG)]
for name, uxml, js, bg in shots:
    open(os.path.join(OUT, "_%s.html" % name), "w").write(page(uxml, js, bg))
# Screenshots via the preinstalled Node Playwright + Chromium (see shoot.js).
import subprocess
subprocess.run(["node", os.path.join(os.path.dirname(os.path.abspath(__file__)), "shoot.js"), OUT] + [n for n, *_ in shots], check=True)
for name, *_ in shots: os.remove(os.path.join(OUT, "_%s.html" % name))
