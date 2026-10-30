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

def convert(node):
    tag = node.tag.split('}')[-1]
    if tag == "Style": return ""
    attrs = node.attrib
    cls = attrs.get("class", "")
    name = attrs.get("name", "")
    style = attrs.get("style", "")
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

MENU_JS = """
document.getElementById('event-map').innerHTML = `%s`;
document.getElementById('driver-name').textContent = 'ROOKIE';
document.getElementById('driver-rank').textContent = 'AMATEUR  ·  REPUTATION 20  ·  3 RACES';
document.getElementById('stat-money').textContent = '$9,550';
document.getElementById('stat-points').textContent = '55';
document.getElementById('stat-wins').textContent = '1';
document.getElementById('stat-podiums').textContent = '2';
document.getElementById('event-best').textContent = 'PERSONAL BEST 1:14.982';
document.getElementById('version').textContent = 'v0.1.3  ·  Unity 6000.3.27f1';
for (const id of ['steer-touch','gear-auto','quality-1','fps-off']) document.getElementById(id).classList.add('segment--on');
""" % circuit_svg(230, 170)

HUD_JS = """
const rows = [['1','REY','#1F4E8C','LEADER',false],['2','LIN','#B3261E','+0.8',false],['3','YOU','#FFB800','+1.9',true],['4','OKA','#E0A100','+3.4',false],['5','BRA','#2E7D32','+6.1',false]];
const host = document.getElementById('tower-rows');
for (const r of rows) {
  const row = document.createElement('div'); row.className = 'tower__row' + (r[4] ? ' tower__row--player' : '');
  row.innerHTML = `<div class="label tower__pos">${r[0]}</div><div class="tower__swatch" style="background-color:${r[2]}"></div><div class="label tower__name">${r[1]}</div><div class="label tower__gap">${r[3]}</div>`;
  host.appendChild(row);
}
document.getElementById('lap').textContent = 'LAP 2/3';
document.getElementById('position').textContent = 'POSITION 3/5';
document.getElementById('lap-time').textContent = '0:41.276';
document.getElementById('best-lap').textContent = 'BEST 1:15.204';
document.getElementById('speed').textContent = '187';
document.getElementById('gear').textContent = '5';
document.getElementById('hud-map').innerHTML = `%s`;
document.getElementById('gauge').insertAdjacentHTML('afterbegin', `%s`);
document.getElementById('lights').classList.add('hidden');
document.getElementById('notice').textContent = 'FINAL LAP';
document.getElementById('notice').classList.add('notice__pill--show');
""" % (circuit_svg(270 - 56, 200 - 48, [(0.62, '#1F4E8C'), (0.6, '#B3261E'), (0.54, '#E0A100'), (0.5, '#2E7D32'), (0.57, '#FFB800')]), rpm_svg(0.78))

LIGHTS_JS = HUD_JS.replace("document.getElementById('lights').classList.add('hidden');", "for (const i of [0,1,2]) document.getElementById('light-'+i).classList.add('light--on');").replace("document.getElementById('notice').classList.add('notice__pill--show');", "")

RESULTS_JS = HUD_JS + """
document.getElementById('controls').classList.add('hidden');
document.getElementById('results').classList.remove('hidden');
document.getElementById('results-title').textContent = 'ASHFORD CLUB SPRINT';
document.getElementById('results-sub').textContent = 'RESULTS  ·  ASHFORD AIRFIELD CIRCUIT  ·  3 LAPS';
const res = [['1','MATEO REYES','HALDEN MOTORSPORT','3:47.912','1:14.770',false,false],['2','ROOKIE','PRIVATEER','+1.204','1:14.512',true,true],['3','ELIN LINDQVIST','CORSAIR RACING','+2.880','1:15.031',false,false],['4','DANIEL OKAFOR','VANTOR ENGINEERING','+6.415','1:15.840',false,false],['5','JONAS BRANDT','NORTHLINE GP','+9.002','1:16.207',false,false]];
const t = document.getElementById('results-rows');
for (const r of res) {
  const row = document.createElement('div'); row.className = 'res-row' + (r[5] ? ' res-row--player' : '');
  row.innerHTML = `<div class="label res-pos ${r[0]==='1'?'res-pos--p1':''}">${r[0]}</div><div class="grow"><div class="label res-name">${r[1]}</div><div class="label res-team">${r[2]}</div></div><div class="label res-time">${r[3]}</div><div class="res-best ${r[6]?'res-best--fastest':''}">${r[6]?'<div class="icon icon--sm ic-timer" style="background-color:#ab5aff;margin-right:8px"></div>':''}<div class="label">${r[4]}</div></div>`;
  t.appendChild(row);
}
const lines = [['Prize money · P2','+$1,800',true],['Fastest lap bonus','+$250',true],['Entry fee','−$250',false],['Reputation','+10',true],['Championship points','+18',true]];
const l = document.getElementById('reward-lines');
for (const x of lines) { const d = document.createElement('div'); d.className='reward__line'; d.innerHTML = `<div class="label t-muted">${x[0]}</div><div class="label reward__amount ${x[2]?'t-green':'t-red'}">${x[1]}</div>`; l.appendChild(d); }
document.getElementById('reward-balance').textContent = '$11,350';
document.getElementById('notice').classList.remove('notice__pill--show');
"""

SETTINGS_JS = MENU_JS + "document.getElementById('settings-sheet').classList.remove('hidden');"

MENU_BG = "background: radial-gradient(ellipse at 72% 60%, #3a4250 0%, #1a1e26 45%, #0b0d12 100%);"
HUD_BG = "background: linear-gradient(180deg, #8fa3b8 0%, #b9c6d2 38%, #4b5148 39%, #2b2e30 70%, #1d1f21 100%);"

shots = [("menu", "MainMenu.uxml", MENU_JS, MENU_BG), ("settings", "MainMenu.uxml", SETTINGS_JS, MENU_BG),
         ("hud", "RaceHud.uxml", HUD_JS, HUD_BG), ("start-lights", "RaceHud.uxml", LIGHTS_JS, HUD_BG),
         ("results", "RaceHud.uxml", RESULTS_JS, HUD_BG)]
for name, uxml, js, bg in shots:
    open(os.path.join(OUT, "_%s.html" % name), "w").write(page(uxml, js, bg))
# Screenshots via the preinstalled Node Playwright + Chromium (see shoot.js).
import subprocess
subprocess.run(["node", os.path.join(os.path.dirname(os.path.abspath(__file__)), "shoot.js"), OUT] + [n for n, *_ in shots], check=True)
for name, *_ in shots: os.remove(os.path.join(OUT, "_%s.html" % name))
