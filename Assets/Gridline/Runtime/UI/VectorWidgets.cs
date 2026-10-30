using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UIElements;

namespace Gridline.UI
{
    /// <summary>Tachometer arc drawn with UI Toolkit's vector Painter2D (resolution independent).</summary>
    public class RpmGauge : VisualElement
    {
        float value;
        public Color trackColor = new Color(1f, 1f, 1f, 0.12f);
        public Color fillColor = new Color(0.95f, 0.96f, 0.97f, 1f);
        public Color redlineColor = new Color(0.88f, 0.06f, 0.12f, 1f);
        public float redline = 0.86f;
        const float StartDeg = 150f, SweepDeg = 240f;

        public RpmGauge()
        {
            pickingMode = PickingMode.Ignore;
            style.position = Position.Absolute;
            style.left = 0;
            style.right = 0;
            style.top = 0;
            style.bottom = 0;
            generateVisualContent += Draw;
        }

        public void SetValue(float v)
        {
            v = Mathf.Clamp01(v);
            if (Mathf.Abs(v - value) < 0.004f) return;
            value = v;
            MarkDirtyRepaint();
        }

        void Draw(MeshGenerationContext mgc)
        {
            Rect r = contentRect;
            if (r.width < 4f || r.height < 4f) return;
            var p = mgc.painter2D;
            Vector2 c = new Vector2(r.width * 0.5f, r.width * 0.5f + 8f);
            float radius = r.width * 0.5f - 16f;
            p.lineCap = LineCap.Round;
            p.lineWidth = 14f;
            Arc(p, c, radius, 0f, 1f, trackColor);
            Arc(p, c, radius, redline, 1f, new Color(redlineColor.r, redlineColor.g, redlineColor.b, 0.35f));
            if (value > 0.001f) Arc(p, c, radius, 0f, Mathf.Min(value, redline), fillColor);
            if (value > redline) Arc(p, c, radius, redline, value, redlineColor);
        }

        static void Arc(Painter2D p, Vector2 c, float radius, float from, float to, Color color)
        {
            p.strokeColor = color;
            p.BeginPath();
            p.Arc(c, radius, Angle.Degrees(StartDeg + SweepDeg * from), Angle.Degrees(StartDeg + SweepDeg * to), ArcDirection.Clockwise);
            p.Stroke();
        }
    }

    /// <summary>Circuit outline from the real centreline data, with optional live car markers.</summary>
    public class TrackMap : VisualElement
    {
        readonly List<Vector2> outline = new List<Vector2>();
        readonly List<Vector2> markers = new List<Vector2>();
        readonly List<Color> markerColors = new List<Color>();
        Vector2 min, size;
        public Color lineColor = new Color(1f, 1f, 1f, 0.85f);
        public Color startColor = new Color(0.88f, 0.06f, 0.12f, 1f);

        public TrackMap(IList<Vector3> centreline)
        {
            pickingMode = PickingMode.Ignore;
            style.flexGrow = 1;
            min = new Vector2(float.MaxValue, float.MaxValue);
            Vector2 max = new Vector2(float.MinValue, float.MinValue);
            int step = Mathf.Max(1, centreline.Count / 160);
            for (int i = 0; i < centreline.Count; i += step)
            {
                var v = new Vector2(centreline[i].x, centreline[i].z);
                outline.Add(v);
                min = Vector2.Min(min, v);
                max = Vector2.Max(max, v);
            }
            size = max - min;
            generateVisualContent += Draw;
        }

        public void SetMarkers(IList<Vector3> worldPositions, IList<Color> colors)
        {
            markers.Clear();
            markerColors.Clear();
            for (int i = 0; i < worldPositions.Count; i++)
            {
                markers.Add(new Vector2(worldPositions[i].x, worldPositions[i].z));
                markerColors.Add(colors[i]);
            }
            MarkDirtyRepaint();
        }

        Vector2 Map(Vector2 world, Rect r, float scale, Vector2 offset)
        {
            // World +z is up on the map.
            Vector2 local = (world - min) * scale;
            return new Vector2(offset.x + local.x, r.height - offset.y - local.y);
        }

        void Draw(MeshGenerationContext mgc)
        {
            Rect r = contentRect;
            if (outline.Count < 3 || r.width < 8f || size.x <= 0f || size.y <= 0f) return;
            const float pad = 14f;
            float scale = Mathf.Min((r.width - 2 * pad) / size.x, (r.height - 2 * pad) / size.y);
            Vector2 offset = new Vector2((r.width - size.x * scale) * 0.5f, (r.height - size.y * scale) * 0.5f);
            var p = mgc.painter2D;
            p.lineJoin = LineJoin.Round;
            p.lineCap = LineCap.Round;
            p.lineWidth = 6f;
            p.strokeColor = lineColor;
            p.BeginPath();
            p.MoveTo(Map(outline[0], r, scale, offset));
            for (int i = 1; i < outline.Count; i++) p.LineTo(Map(outline[i], r, scale, offset));
            p.ClosePath();
            p.Stroke();

            // Start/finish marker.
            Dot(p, Map(outline[0], r, scale, offset), 7f, startColor);
            for (int i = 0; i < markers.Count; i++) Dot(p, Map(markers[i], r, scale, offset), 8f, markerColors[i]);
        }

        static void Dot(Painter2D p, Vector2 c, float radius, Color color)
        {
            p.fillColor = color;
            p.BeginPath();
            p.Arc(c, radius, Angle.Degrees(0f), Angle.Degrees(360f));
            p.Fill();
        }
    }
}
