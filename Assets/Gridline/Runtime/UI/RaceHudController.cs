using System.Collections.Generic;
using Gridline.Core;
using Gridline.Input;
using Gridline.Platform;
using Gridline.Race;
using Gridline.Vehicle;
using UnityEngine;
using UnityEngine.UIElements;

namespace Gridline.UI
{
    /// <summary>Race HUD (RaceHud.uxml): timing tower, lap timer, start lights, tacho, live map, touch pads, pause and results.</summary>
    [RequireComponent(typeof(UIDocument))]
    [RequireComponent(typeof(TouchControls))]
    public class RaceHudController : MonoBehaviour
    {
        public static readonly string[] RequiredElements =
        {
            "hud", "lap", "tower-rows", "position", "lap-time", "best-lap", "penalty", "hud-map", "camera-button", "pause-button",
            "fps", "notice", "lights", "light-0", "light-1", "light-2", "light-3", "light-4", "gauge", "gear", "speed",
            "controls", "pad-left", "pad-right", "pad-brake", "pad-throttle", "pad-up", "pad-down",
            "pause", "resume", "restart", "pause-camera", "retire",
            "results", "results-title", "results-sub", "results-rows", "reward-lines", "reward-balance", "continue", "race-again",
        };

        public TouchControls Touch { get; private set; }

        RaceDirector director;
        GameSettings settings;
        VisualElement root;
        Label lap, lapTime, bestLap, penalty, position, speed, gear, fps, notice;
        VisualElement[] lights;
        VisualElement lightsRoot;
        RpmGauge rpm;
        TrackMap map;
        readonly List<TowerRow> tower = new List<TowerRow>();
        readonly Dictionary<string, Color> carColors = new Dictionary<string, Color>();
        readonly List<Vector3> markerPositions = new List<Vector3>();
        readonly List<Color> markerColors = new List<Color>();
        float noticeTimer, slowTimer, goTimer;
        bool paused, wasCountdown;

        sealed class TowerRow
        {
            public VisualElement Root, Swatch;
            public Label Pos, Name, Gap;
        }

        public void Bind(RaceDirector owner, GameSettings gameSettings)
        {
            director = owner;
            settings = gameSettings;
            root = GetComponent<UIDocument>().rootVisualElement;
            ScreenNavigator.Validate(root, RequiredElements, nameof(RaceHudController));
            SafeArea.Apply(root.Q("hud"));

            lap = root.Q<Label>("lap");
            lapTime = root.Q<Label>("lap-time");
            bestLap = root.Q<Label>("best-lap");
            penalty = root.Q<Label>("penalty");
            position = root.Q<Label>("position");
            speed = root.Q<Label>("speed");
            gear = root.Q<Label>("gear");
            fps = root.Q<Label>("fps");
            notice = root.Q<Label>("notice");
            lightsRoot = root.Q("lights");
            lights = new VisualElement[5];
            for (int i = 0; i < 5; i++) lights[i] = root.Q("light-" + i);

            rpm = new RpmGauge();
            root.Q("gauge").Insert(0, rpm);
            map = new TrackMap(director.track.points);
            root.Q("hud-map").Add(map);

            Touch = GetComponent<TouchControls>();
            Touch.Bind(root, settings.steeringMode == SteeringMode.TouchButtons, settings.transmission == TransmissionMode.Manual);

            Click("pause-button", () => SetPause(true));
            Click("camera-button", () => director.CycleCamera());
            Click("resume", () => SetPause(false));
            Click("restart", () => director.Restart());
            Click("pause-camera", () => director.CycleCamera());
            Click("retire", () => director.QuitToMenu());
            Click("continue", () => director.QuitToMenu());
            Click("race-again", () => director.Restart());

            BuildTower();
            director.Notice += ShowNotice;
            director.ResultsReady += ShowResults;
        }

        void Click(string name, System.Action action)
        {
            var b = root.Q<Button>(name);
            if (b != null) b.clicked += action;
        }

        void BuildTower()
        {
            var rows = root.Q("tower-rows");
            var teams = GameServices.Save.teams;
            foreach (var car in director.Cars)
            {
                Color c = Color.white;
                if (!car.isPlayer && car.profile != null)
                    foreach (var t in teams)
                        if (t.id == car.profile.teamId && ColorUtility.TryParseHtmlString(t.primaryColorHex, out Color parsed)) c = parsed;
                carColors[car.racerId] = car.isPlayer ? new Color(1f, 0.72f, 0f) : c;

                var row = new TowerRow { Root = new VisualElement(), Pos = new Label(), Swatch = new VisualElement(), Name = new Label(), Gap = new Label() };
                row.Root.AddToClassList("tower__row");
                row.Pos.AddToClassList("tower__pos");
                row.Swatch.AddToClassList("tower__swatch");
                row.Name.AddToClassList("tower__name");
                row.Gap.AddToClassList("tower__gap");
                row.Root.Add(row.Pos);
                row.Root.Add(row.Swatch);
                row.Root.Add(row.Name);
                row.Root.Add(row.Gap);
                row.Root.pickingMode = PickingMode.Ignore;
                rows.Add(row.Root);
                tower.Add(row);
            }
        }

        static string Code(RacerSnapshot r)
        {
            if (r.isPlayer) return "YOU";
            string[] parts = r.displayName.Split(' ');
            string last = parts[parts.Length - 1].ToUpperInvariant();
            return last.Length > 3 ? last.Substring(0, 3) : last;
        }

        void ShowNotice(string message)
        {
            notice.text = message;
            notice.AddToClassList("notice__pill--show");
            noticeTimer = 2.4f;
        }

        void SetPause(bool on)
        {
            if (director.Phase == RacePhase.Results) return;
            paused = on;
            ScreenNavigator.SetVisible(root.Q("pause"), on);
            director.SetPaused(on);
        }

        void OnApplicationPause(bool appPaused)
        {
            // Backgrounding mid-race pauses the race, as mobile players expect.
            if (appPaused && director != null && director.ClockRunning) SetPause(true);
        }

        void Update()
        {
            if (director == null || director.Player == null) return;
            if (UnityEngine.Input.GetKeyDown(KeyCode.Escape) && director.Phase != RacePhase.Results) SetPause(!paused); // Android back button

            var p = director.Player;
            lap.text = "LAP " + p.Laps.CurrentLap + "/" + director.TotalLaps;
            position.text = "POSITION " + Mathf.Max(1, p.Position) + "/" + director.Cars.Count;
            lapTime.text = director.ClockRunning && !p.Laps.Finished
                ? RaceClassification.FormatTime((int)(p.Laps.CurrentLapElapsed(director.RaceTime) * 1000))
                : RaceClassification.FormatTime(p.Laps.LastLapMs);
            bestLap.text = "BEST " + RaceClassification.FormatTime(p.Laps.BestLapMs);
            penalty.text = p.PenaltySeconds > 0f ? "+" + p.PenaltySeconds.ToString("0") + "s PEN" : "";
            speed.text = Mathf.RoundToInt(p.SpeedKmh).ToString();
            gear.text = VehicleSetup.GearLabel(p.Vehicle);
            rpm.SetValue(VehicleSetup.RpmFraction(p.Vehicle));
            UpdateLights();

            if (noticeTimer > 0f)
            {
                noticeTimer -= Time.unscaledDeltaTime;
                if (noticeTimer <= 0f) notice.RemoveFromClassList("notice__pill--show");
            }

            slowTimer -= Time.unscaledDeltaTime;
            if (slowTimer > 0f) return;
            slowTimer = 0.2f;
            UpdateTower();
            UpdateMap();
            var perf = director.perfLogger;
            fps.text = settings.showFps && perf != null ? perf.CurrentFps.ToString("0") + " FPS" : "";
        }

        void UpdateTower()
        {
            var rows = director.Standings;
            if (rows == null || rows.Count == 0) return;
            var leader = rows[0];
            float pace = director.RaceTime > 5.0 ? Mathf.Max(10f, leader.progress / (float)director.RaceTime) : 0f;
            for (int i = 0; i < tower.Count && i < rows.Count; i++)
            {
                var r = rows[i];
                var row = tower[i];
                row.Pos.text = (i + 1).ToString();
                row.Name.text = Code(r);
                row.Swatch.style.backgroundColor = carColors.TryGetValue(r.id, out Color c) ? c : Color.white;
                row.Root.EnableInClassList("tower__row--player", r.isPlayer);
                if (r.finished) row.Gap.text = "FIN";
                else if (i == 0 || pace <= 0f) row.Gap.text = i == 0 ? "LEADER" : "";
                else row.Gap.text = "+" + ((leader.progress - r.progress) / pace).ToString("0.0");
            }
        }

        void UpdateMap()
        {
            markerPositions.Clear();
            markerColors.Clear();
            // Draw the player last so it sits on top.
            foreach (var car in director.Cars)
            {
                if (car.isPlayer) continue;
                markerPositions.Add(car.transform.position);
                markerColors.Add(carColors[car.racerId]);
            }
            markerPositions.Add(director.Player.transform.position);
            markerColors.Add(carColors[director.Player.racerId]);
            map.SetMarkers(markerPositions, markerColors);
        }

        void UpdateLights()
        {
            bool countdown = director.Phase == RacePhase.Countdown || director.Phase == RacePhase.Setup;
            if (wasCountdown && !countdown) goTimer = 0.8f;
            wasCountdown = countdown;
            if (goTimer > 0f) goTimer -= Time.deltaTime;
            bool show = countdown || goTimer > 0f;
            ScreenNavigator.SetVisible(lightsRoot, show);
            if (!show) return;
            float elapsed = director.countdownSeconds - director.CountdownRemaining;
            for (int i = 0; i < lights.Length; i++)
            {
                bool on = director.Phase == RacePhase.Countdown && elapsed >= (i + 1) * director.countdownSeconds / (lights.Length + 1);
                lights[i].EnableInClassList("light--on", on && goTimer <= 0f);
                lights[i].EnableInClassList("light--go", goTimer > 0f);
            }
        }

        void ShowResults()
        {
            ScreenNavigator.SetVisible(root.Q("pause"), false);
            Touch.SetVisible(false);
            root.Q<Label>("results-title").text = RaceSession.EventName.ToUpperInvariant();
            root.Q<Label>("results-sub").text = "RESULTS  ·  " + director.track.displayName.ToUpperInvariant() + "  ·  " + director.TotalLaps + " LAPS";

            var table = root.Q("results-rows");
            table.Clear();
            var rows = director.Standings;
            double winner = rows.Count > 0 && rows[0].finished ? rows[0].ClassifiedTime : 0;
            var teams = GameServices.Save.teams;
            for (int i = 0; i < rows.Count; i++)
            {
                var r = rows[i];
                var row = new VisualElement();
                row.AddToClassList("res-row");
                if (r.isPlayer) row.AddToClassList("res-row--player");
                var pos = new Label((i + 1).ToString());
                pos.AddToClassList("res-pos");
                if (i == 0) pos.AddToClassList("res-pos--p1");
                var nameBox = new VisualElement();
                nameBox.AddToClassList("grow");
                var name = new Label(r.displayName.ToUpperInvariant());
                name.AddToClassList("res-name");
                var team = new Label(TeamName(r, teams));
                team.AddToClassList("res-team");
                nameBox.Add(name);
                nameBox.Add(team);
                string time = r.finished
                    ? (i == 0 ? RaceClassification.FormatTime((int)(r.ClassifiedTime * 1000)) : "+" + (r.ClassifiedTime - winner).ToString("0.000"))
                    : "DNF  " + r.lapsCompleted + " L";
                if (r.penaltySeconds > 0f) time += "  (+" + r.penaltySeconds.ToString("0") + "s)";
                var timeLabel = new Label(time);
                timeLabel.AddToClassList("res-time");
                var best = new VisualElement();
                best.AddToClassList("res-best");
                if (r.id == director.FastestLapId)
                {
                    best.AddToClassList("res-best--fastest");
                    var star = new VisualElement();
                    star.AddToClassList("icon");
                    star.AddToClassList("icon--sm");
                    star.AddToClassList("ic-timer");
                    star.style.unityBackgroundImageTintColor = new Color(0.67f, 0.35f, 1f);
                    star.style.marginRight = 8;
                    best.Add(star);
                }
                best.Add(new Label(RaceClassification.FormatTime(r.bestLapMs)));
                row.Add(pos);
                row.Add(nameBox);
                row.Add(timeLabel);
                row.Add(best);
                table.Add(row);
            }

            var lines = root.Q("reward-lines");
            lines.Clear();
            var reward = director.Reward;
            if (reward == null) lines.Add(Line("Result not counted (test session)", "", false));
            else
            {
                lines.Add(Line("Prize money · P" + reward.position, "+$" + reward.prizeMoney.ToString("N0"), true));
                if (reward.fastestLapBonus > 0) lines.Add(Line("Fastest lap bonus", "+$" + reward.fastestLapBonus.ToString("N0"), true));
                if (director.Entry != null && director.Entry.feeCharged > 0) lines.Add(Line("Entry fee", "−$" + director.Entry.feeCharged.ToString("N0"), false));
                if (director.Entry != null && director.Entry.sponsorCovered) lines.Add(Line("Entry fee", "Sponsored", true));
                lines.Add(Line("Reputation", "+" + reward.reputationGained, true));
                lines.Add(Line("Championship points", "+" + reward.championshipPoints, true));
                if (reward.newTrackRecord) lines.Add(Line("Personal best lap", RaceClassification.FormatTime(director.Player.Laps.BestLapMs), true));
            }
            root.Q<Label>("reward-balance").text = "$" + GameServices.Save.career.money.ToString("N0");
            ScreenNavigator.SetVisible(root.Q("results"), true);
        }

        static string TeamName(RacerSnapshot r, List<TeamProfile> teams)
        {
            if (r.isPlayer) return "PRIVATEER";
            foreach (var d in GameServices.Save.aiDrivers)
                if (d.id == r.id)
                    foreach (var t in teams)
                        if (t.id == d.teamId) return t.displayName.ToUpperInvariant();
            return "";
        }

        static VisualElement Line(string label, string amount, bool positive)
        {
            var row = new VisualElement();
            row.AddToClassList("reward__line");
            var l = new Label(label);
            l.AddToClassList("t-muted");
            var a = new Label(amount);
            a.AddToClassList("reward__amount");
            a.AddToClassList(positive ? "t-green" : "t-red");
            row.Add(l);
            row.Add(a);
            return row;
        }
    }
}
