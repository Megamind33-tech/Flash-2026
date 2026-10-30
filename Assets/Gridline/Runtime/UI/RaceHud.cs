using System.Text;
using Gridline.Core;
using Gridline.Platform;
using Gridline.Race;
using Gridline.Vehicle;
using UnityEngine;
using UnityEngine.UI;

namespace Gridline.UI
{
    /// <summary>In-race HUD, countdown lights, notices, pause menu and results screen.</summary>
    public class RaceHud : MonoBehaviour
    {
        RaceDirector director;
        GameSettings settings;
        Canvas canvas;
        Text position, lap, lapTime, bestLap, speed, gear, notice, standings, fps, countdown;
        Image[] lights;
        RectTransform pausePanel, resultsPanel;
        float noticeTimer;
        PerformanceLogger perf;

        public void Build(RaceDirector owner, GameSettings gameSettings)
        {
            director = owner;
            settings = gameSettings;
            perf = owner.perfLogger;
            canvas = UiFactory.CreateCanvas("HUD", 20);
            canvas.transform.SetParent(transform, false);
            var root = canvas.transform;

            // Position + lap block, top-left.
            var info = UiFactory.Box(root, "Info", new Vector2(0, 1), new Vector2(0, 1), new Vector2(40, -36), new Vector2(380, 190));
            UiFactory.Panel(info, UiFactory.PanelColor);
            position = UiFactory.Label(Inset(info, 24, 16, 200, 100, true), "Position", "P-", 84, TextAnchor.UpperLeft, UiFactory.TextPrimary, FontStyle.Bold);
            lap = UiFactory.Label(Inset(info, 24, 116, 330, 50, true), "Lap", "LAP 1/3", 38, TextAnchor.UpperLeft, UiFactory.Accent, FontStyle.Bold);

            // Timing block, top-centre.
            var timing = UiFactory.Box(root, "Timing", new Vector2(0.5f, 1), new Vector2(0.5f, 1), new Vector2(0, -36), new Vector2(460, 130));
            UiFactory.Panel(timing, UiFactory.PanelColor);
            lapTime = UiFactory.Label(Inset(timing, 0, 12, 460, 64, true), "LapTime", "0:00.000", 56, TextAnchor.UpperCenter, UiFactory.TextPrimary, FontStyle.Bold);
            bestLap = UiFactory.Label(Inset(timing, 0, 80, 460, 40, true), "BestLap", "BEST --:--.---", 30, TextAnchor.UpperCenter, UiFactory.TextMuted);

            // Live standings, left side under the info block.
            var board = UiFactory.Box(root, "Standings", new Vector2(0, 1), new Vector2(0, 1), new Vector2(40, -246), new Vector2(380, 250));
            UiFactory.Panel(board, new Color(0.07f, 0.08f, 0.10f, 0.6f));
            standings = UiFactory.Label(Inset(board, 20, 14, 350, 230, true), "Rows", "", 28, TextAnchor.UpperLeft, UiFactory.TextPrimary);
            standings.supportRichText = true;

            // Speed + gear, bottom-centre (between the thumb zones).
            var dash = UiFactory.Box(root, "Dash", new Vector2(0.5f, 0), new Vector2(0.5f, 0), new Vector2(0, 40), new Vector2(380, 150));
            UiFactory.Panel(dash, UiFactory.PanelColor);
            speed = UiFactory.Label(Inset(dash, 20, 10, 250, 130, true), "Speed", "0", 92, TextAnchor.MiddleLeft, UiFactory.TextPrimary, FontStyle.Bold);
            UiFactory.Label(Inset(dash, 200, 70, 90, 60, true), "Unit", "km/h", 28, TextAnchor.MiddleLeft, UiFactory.TextMuted);
            gear = UiFactory.Label(Inset(dash, 290, 10, 80, 130, true), "Gear", "N", 80, TextAnchor.MiddleCenter, UiFactory.Accent, FontStyle.Bold);

            notice = UiFactory.Label(UiFactory.Box(root, "Notice", new Vector2(0.5f, 0.68f), new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(1400, 100)),
                "Text", "", 54, TextAnchor.MiddleCenter, UiFactory.Accent, FontStyle.Bold);
            fps = UiFactory.Label(UiFactory.Box(root, "Fps", new Vector2(1, 1), new Vector2(1, 1), new Vector2(-40, -200), new Vector2(300, 40)),
                "Text", "", 26, TextAnchor.UpperRight, UiFactory.TextMuted);

            // Countdown lights.
            var lightsRoot = UiFactory.Box(root, "Lights", new Vector2(0.5f, 0.62f), new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(560, 150));
            UiFactory.Panel(lightsRoot, new Color(0.03f, 0.03f, 0.04f, 0.9f));
            lights = new Image[3];
            for (int i = 0; i < 3; i++)
            {
                var l = UiFactory.Box(lightsRoot, "Light" + i, new Vector2(0, 0.5f), new Vector2(0, 0.5f), new Vector2(45 + i * 170, 0), new Vector2(130, 110));
                lights[i] = UiFactory.Panel(l, new Color(0.2f, 0.05f, 0.05f, 1f));
            }
            countdown = UiFactory.Label(lightsRoot, "Count", "", 40, TextAnchor.LowerCenter, UiFactory.TextPrimary, FontStyle.Bold);

            // Pause + camera buttons, top-right.
            UiFactory.Button(UiFactory.Box(root, "Pause", new Vector2(1, 1), new Vector2(1, 1), new Vector2(-40, -36), new Vector2(150, 120)), "II", () => SetPause(true), 48);
            UiFactory.Button(UiFactory.Box(root, "Camera", new Vector2(1, 1), new Vector2(1, 1), new Vector2(-210, -36), new Vector2(150, 120)), "CAM", () => director.CycleCamera(), 36);

            BuildPause(root);
            director.Notice += ShowNotice;
            director.ResultsReady += ShowResults;
        }

        static RectTransform Inset(RectTransform parent, float x, float y, float w, float h, bool fromTop)
        {
            return UiFactory.Box(parent, "Area", new Vector2(0, fromTop ? 1 : 0), new Vector2(0, fromTop ? 1 : 0), new Vector2(x, fromTop ? -y : y), new Vector2(w, h));
        }

        void BuildPause(Transform root)
        {
            pausePanel = UiFactory.Rect(root, "PauseMenu", Vector2.zero, Vector2.one, Vector2.zero, Vector2.zero);
            UiFactory.Panel(pausePanel, new Color(0, 0, 0, 0.7f), false);
            var box = UiFactory.Box(pausePanel, "Box", new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(620, 640));
            UiFactory.Panel(box, UiFactory.PanelColor);
            UiFactory.Label(Inset(box, 0, 30, 620, 80, true), "Title", "PAUSED", 60, TextAnchor.MiddleCenter, UiFactory.TextPrimary, FontStyle.Bold);
            UiFactory.Button(Inset(box, 60, 140, 500, 100, true), "RESUME", () => SetPause(false), 40, true);
            UiFactory.Button(Inset(box, 60, 260, 500, 100, true), "RESTART RACE", () => director.Restart(), 40);
            UiFactory.Button(Inset(box, 60, 380, 500, 100, true), "CHANGE CAMERA", () => director.CycleCamera(), 40);
            UiFactory.Button(Inset(box, 60, 500, 500, 100, true), "RETIRE TO MENU", () => director.QuitToMenu(), 40);
            pausePanel.gameObject.SetActive(false);
        }

        void SetPause(bool paused)
        {
            if (director.Phase == RacePhase.Results) return;
            pausePanel.gameObject.SetActive(paused);
            director.SetPaused(paused);
        }

        void OnApplicationPause(bool paused)
        {
            // Backgrounding the app mid-race pauses it, as players expect on mobile.
            if (paused && director != null && director.ClockRunning) SetPause(true);
        }

        void ShowNotice(string message)
        {
            notice.text = message;
            noticeTimer = 2.5f;
        }

        void Update()
        {
            if (director == null || director.Player == null) return;
            var p = director.Player;
            position.text = "P" + Mathf.Max(1, p.Position) + "<size=40>/" + director.Cars.Count + "</size>";
            position.supportRichText = true;
            lap.text = "LAP " + p.Laps.CurrentLap + "/" + director.TotalLaps;
            lapTime.text = director.ClockRunning && !p.Laps.Finished
                ? RaceClassification.FormatTime((int)(p.Laps.CurrentLapElapsed(director.RaceTime) * 1000))
                : RaceClassification.FormatTime(p.Laps.LastLapMs);
            bestLap.text = "BEST " + RaceClassification.FormatTime(p.Laps.BestLapMs) + (p.PenaltySeconds > 0 ? "   +" + p.PenaltySeconds.ToString("0") + "s" : "");
            speed.text = Mathf.RoundToInt(p.SpeedKmh).ToString();
            gear.text = VehicleSetup.GearLabel(p.Vehicle);
            UpdateStandings();
            UpdateLights();

            if (noticeTimer > 0f)
            {
                noticeTimer -= Time.unscaledDeltaTime;
                if (noticeTimer <= 0f) notice.text = "";
            }
            fps.text = settings != null && settings.showFps && perf != null ? perf.CurrentFps.ToString("0") + " FPS" : "";
        }

        void UpdateStandings()
        {
            var rows = director.Standings;
            if (rows == null) return;
            var sb = new StringBuilder();
            for (int i = 0; i < rows.Count; i++)
            {
                var r = rows[i];
                string name = r.displayName.Length > 16 ? r.displayName.Substring(0, 16) : r.displayName;
                string line = (i + 1) + "  " + name;
                sb.AppendLine(r.isPlayer ? "<color=#F2A800><b>" + line + "</b></color>" : line);
            }
            standings.text = sb.ToString();
        }

        void UpdateLights()
        {
            bool show = director.Phase == RacePhase.Countdown || director.Phase == RacePhase.Setup;
            lights[0].transform.parent.gameObject.SetActive(show);
            if (!show) return;
            float t = director.countdownSeconds - director.CountdownRemaining;
            for (int i = 0; i < lights.Length; i++)
                lights[i].color = director.Phase == RacePhase.Countdown && t >= i * (director.countdownSeconds / 3f)
                    ? new Color(0.95f, 0.12f, 0.1f, 1f) : new Color(0.2f, 0.05f, 0.05f, 1f);
            countdown.text = "";
        }

        void ShowResults()
        {
            pausePanel.gameObject.SetActive(false);
            resultsPanel = UiFactory.Rect(canvas.transform, "Results", Vector2.zero, Vector2.one, Vector2.zero, Vector2.zero);
            UiFactory.Panel(resultsPanel, new Color(0, 0, 0, 0.72f), false);
            var box = UiFactory.Box(resultsPanel, "Box", new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(1500, 900));
            UiFactory.Panel(box, UiFactory.PanelColor);
            UiFactory.Label(Inset(box, 60, 30, 1380, 80, true), "Title", RaceSession.EventName.ToUpperInvariant() + " — RESULTS", 52, TextAnchor.MiddleLeft, UiFactory.TextPrimary, FontStyle.Bold);

            float[] cols = { 0, 130, 760, 1080 };
            string[] heads = { "POS", "DRIVER", "TIME", "BEST LAP" };
            for (int c = 0; c < cols.Length; c++)
                UiFactory.Label(Inset(box, 60 + cols[c], 130, 300, 44, true), "Head" + c, heads[c], 28, TextAnchor.MiddleLeft, UiFactory.TextMuted, FontStyle.Bold);
            var rows = director.Standings;
            double winner = rows.Count > 0 && rows[0].finished ? rows[0].ClassifiedTime : 0;
            for (int i = 0; i < rows.Count; i++)
            {
                var r = rows[i];
                string time = r.finished
                    ? (i == 0 ? RaceClassification.FormatTime((int)(r.ClassifiedTime * 1000)) : "+" + (r.ClassifiedTime - winner).ToString("0.000") + "s")
                    : "DNF (" + r.lapsCompleted + " laps)";
                if (r.penaltySeconds > 0) time += "  (+" + r.penaltySeconds.ToString("0") + "s pen)";
                string best = RaceClassification.FormatTime(r.bestLapMs) + (r.id == director.FastestLapId ? "  FASTEST" : "");
                string[] cells = { "P" + (i + 1), r.displayName, time, best };
                Color color = r.isPlayer ? UiFactory.Accent : UiFactory.TextPrimary;
                for (int c = 0; c < cols.Length; c++)
                    UiFactory.Label(Inset(box, 60 + cols[c], 180 + i * 52, c == 1 ? 620 : 320, 48, true), "Cell", cells[c], 34, TextAnchor.MiddleLeft, color,
                        r.isPlayer ? FontStyle.Bold : FontStyle.Normal);
            }

            var reward = director.Reward;
            var career = GameServices.Save.career;
            string money = reward == null
                ? "Result not counted (test session)."
                : "Prize money  $" + reward.prizeMoney.ToString("N0") +
                  (reward.fastestLapBonus > 0 ? "     Fastest lap bonus  $" + reward.fastestLapBonus.ToString("N0") : "") +
                  (director.Entry != null && director.Entry.feeCharged > 0 ? "     Entry fee  -$" + director.Entry.feeCharged.ToString("N0") : "") +
                  (director.Entry != null && director.Entry.sponsorCovered ? "     Entry covered by sponsor" : "") +
                  "\nReputation  +" + reward.reputationGained + "     Points  +" + reward.championshipPoints +
                  (reward.newTrackRecord ? "     NEW PERSONAL BEST LAP" : "") +
                  "\nBalance  $" + career.money.ToString("N0");
            UiFactory.Label(Inset(box, 60, 530, 1380, 200, true), "Reward", money, 36, TextAnchor.UpperLeft, UiFactory.Positive);

            UiFactory.Button(Inset(box, 60, 770, 600, 100, true), "RACE AGAIN", () => director.Restart(), 40);
            UiFactory.Button(Inset(box, 840, 770, 600, 100, true), "CONTINUE", () => director.QuitToMenu(), 40, true);
        }
    }
}
