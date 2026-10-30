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
            "hud", "hud-map", "rpm-fill", "progress-fill", "fps", "position", "lap", "lap-time", "best-lap", "penalty-row", "penalty",
            "tower-rows", "camera-button", "pause-button", "big-text", "big-sub", "notice", "speed", "gear", "rpm",
            "controls", "pad-left", "pad-right", "pad-brake", "pad-throttle", "pad-up", "pad-down",
            "pause", "pause-info", "resume", "restart", "pause-camera", "retire",
            "results", "results-title", "results-sub", "results-rows", "reward-lines", "reward-balance", "continue", "race-again",
        };

        const int RpmSegments = 22;
        const float RedlineFraction = 0.86f;

        public TouchControls Touch { get; private set; }

        RaceDirector director;
        GameSettings settings;
        VisualElement root;
        Label lap, lapTime, bestLap, penalty, position, speed, gear, fps, notice, bigText, bigSub;
        VisualElement penaltyRow, rpmFill, progressFill;
        readonly List<VisualElement> rpmSegments = new List<VisualElement>();
        TrackMap map;
        readonly List<BoardRow> board = new List<BoardRow>();
        readonly Dictionary<string, Color> carColors = new Dictionary<string, Color>();
        readonly List<Vector3> markerPositions = new List<Vector3>();
        readonly List<Color> markerColors = new List<Color>();
        float noticeTimer, bigTimer, slowTimer;
        bool paused;
        int lastCount = -1;

        sealed class BoardRow
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
            penaltyRow = root.Q("penalty-row");
            position = root.Q<Label>("position");
            speed = root.Q<Label>("speed");
            gear = root.Q<Label>("gear");
            fps = root.Q<Label>("fps");
            notice = root.Q<Label>("notice");
            bigText = root.Q<Label>("big-text");
            bigSub = root.Q<Label>("big-sub");
            rpmFill = root.Q("rpm-fill");
            progressFill = root.Q("progress-fill");

            var rpm = root.Q("rpm");
            for (int i = 0; i < RpmSegments; i++)
            {
                var seg = new VisualElement();
                seg.AddToClassList("rpm-seg");
                seg.pickingMode = PickingMode.Ignore;
                rpm.Add(seg);
                rpmSegments.Add(seg);
            }
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

            BuildBoard();
            director.Notice += OnNotice;
            director.ResultsReady += ShowResults;
        }

        void Click(string name, System.Action action)
        {
            var b = root.Q<Button>(name);
            if (b != null) b.clicked += action;
        }

        void BuildBoard()
        {
            var rows = root.Q("tower-rows");
            var teams = GameServices.Save.teams;
            foreach (var car in director.Cars)
            {
                Color c = Color.white;
                if (!car.isPlayer && car.profile != null)
                    foreach (var t in teams)
                        if (t.id == car.profile.teamId && ColorUtility.TryParseHtmlString(t.primaryColorHex, out Color parsed)) c = parsed;
                carColors[car.racerId] = car.isPlayer ? new Color(0.94f, 0.78f, 0.31f) : c;

                var row = new BoardRow { Root = new VisualElement(), Pos = new Label(), Swatch = new VisualElement(), Name = new Label(), Gap = new Label() };
                row.Root.AddToClassList("board__row");
                row.Pos.AddToClassList("board__pos");
                row.Swatch.AddToClassList("board__swatch");
                row.Name.AddToClassList("board__name");
                row.Gap.AddToClassList("board__gap");
                row.Root.Add(row.Pos);
                row.Root.Add(row.Swatch);
                row.Root.Add(row.Name);
                row.Root.Add(row.Gap);
                row.Root.pickingMode = PickingMode.Ignore;
                rows.Add(row.Root);
                board.Add(row);
            }
        }

        static string Code(RacerSnapshot r)
        {
            if (r.isPlayer) return "YOU";
            string[] parts = r.displayName.Split(' ');
            return parts[parts.Length - 1].ToUpperInvariant();
        }

        void OnNotice(string message)
        {
            // Race-defining moments get the big centre treatment; everything else goes to the help box.
            if (message == "GO!") Big("GO", "", "big-message__text--go", 1.0f);
            else if (message == "FINAL LAP") Big("FINAL LAP", "", null, 2.0f);
            else if (message.StartsWith("FINISH")) Big(OrdinalPosition(director.Player.Position), "FINISHED", "big-message__text--gold", 3.0f);
            else
            {
                notice.text = message;
                notice.AddToClassList("help--show");
                noticeTimer = 3f;
            }
        }

        void Big(string text, string sub, string extraClass, float seconds)
        {
            bigText.text = text;
            bigSub.text = sub;
            bigText.RemoveFromClassList("big-message__text--go");
            bigText.RemoveFromClassList("big-message__text--gold");
            if (extraClass != null) bigText.AddToClassList(extraClass);
            bigText.AddToClassList("big-message__text--show");
            bigTimer = seconds;
        }

        static string OrdinalPosition(int p)
        {
            string suffix = p % 100 >= 11 && p % 100 <= 13 ? "TH" : (p % 10 == 1 ? "ST" : p % 10 == 2 ? "ND" : p % 10 == 3 ? "RD" : "TH");
            return p + suffix;
        }

        static string Clock(double seconds)
        {
            if (seconds <= 0) return "--:--.--";
            int cs = (int)(seconds * 100);
            return (cs / 6000).ToString("00") + ":" + (cs / 100 % 60).ToString("00") + "." + (cs % 100).ToString("00");
        }

        void SetPause(bool on)
        {
            if (director.Phase == RacePhase.Results) return;
            paused = on;
            ScreenNavigator.SetVisible(root.Q("pause"), on);
            root.Q<Label>("pause-info").text = director.track.displayName.ToUpperInvariant();
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
            position.text = Mathf.Max(1, p.Position) + "/" + director.Cars.Count;
            lap.text = p.Laps.CurrentLap + "/" + director.TotalLaps;
            lapTime.text = director.ClockRunning && !p.Laps.Finished ? Clock(p.Laps.CurrentLapElapsed(director.RaceTime)) : Clock(p.Laps.LastLapMs / 1000.0);
            bestLap.text = Clock(p.Laps.BestLapMs / 1000.0);
            ScreenNavigator.SetVisible(penaltyRow, p.PenaltySeconds > 0f);
            penalty.text = "+" + p.PenaltySeconds.ToString("0") + "S";
            speed.text = Mathf.RoundToInt(p.SpeedKmh).ToString();
            gear.text = VehicleSetup.GearLabel(p.Vehicle);

            float rpm = VehicleSetup.RpmFraction(p.Vehicle);
            int lit = Mathf.RoundToInt(rpm * RpmSegments);
            for (int i = 0; i < rpmSegments.Count; i++)
            {
                bool red = i >= RpmSegments * RedlineFraction;
                rpmSegments[i].EnableInClassList("rpm-seg--on", i < lit && !red);
                rpmSegments[i].EnableInClassList("rpm-seg--red", i < lit && red);
            }
            rpmFill.style.width = Length.Percent(rpm * 100f);
            rpmFill.EnableInClassList("radar__fill--rpm-high", rpm > RedlineFraction);
            float lapFraction = Mathf.Repeat(p.Laps.Progress, director.track.Length) / director.track.Length;
            progressFill.style.width = Length.Percent(p.Laps.Progress < 0f ? 0f : lapFraction * 100f);

            UpdateCountdown();
            if (bigTimer > 0f)
            {
                bigTimer -= Time.unscaledDeltaTime;
                if (bigTimer <= 0f) bigText.RemoveFromClassList("big-message__text--show");
            }
            if (noticeTimer > 0f)
            {
                noticeTimer -= Time.unscaledDeltaTime;
                if (noticeTimer <= 0f) notice.RemoveFromClassList("help--show");
            }

            slowTimer -= Time.unscaledDeltaTime;
            if (slowTimer > 0f) return;
            slowTimer = 0.2f;
            UpdateBoard();
            UpdateMap();
            var perf = director.perfLogger;
            fps.text = settings.showFps && perf != null ? perf.CurrentFps.ToString("0") + " FPS" : "";
        }

        void UpdateCountdown()
        {
            if (director.Phase != RacePhase.Countdown) return;
            int count = Mathf.CeilToInt(director.CountdownRemaining);
            if (count == lastCount || count <= 0) return;
            lastCount = count;
            Big(count.ToString(), "", null, 0.9f);
        }

        void UpdateBoard()
        {
            var rows = director.Standings;
            if (rows == null || rows.Count == 0) return;
            var leader = rows[0];
            float pace = director.RaceTime > 5.0 ? Mathf.Max(10f, leader.progress / (float)director.RaceTime) : 0f;
            for (int i = 0; i < board.Count && i < rows.Count; i++)
            {
                var r = rows[i];
                var row = board[i];
                row.Pos.text = (i + 1).ToString();
                row.Name.text = Code(r);
                row.Swatch.style.backgroundColor = carColors.TryGetValue(r.id, out Color c) ? c : Color.white;
                row.Root.EnableInClassList("board__row--player", r.isPlayer);
                if (r.finished) row.Gap.text = "FINISHED";
                else if (i == 0 || pace <= 0f) row.Gap.text = i == 0 ? "LEADER" : "";
                else row.Gap.text = "+" + ((leader.progress - r.progress) / pace).ToString("0.0") + "s";
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

        void ShowResults()
        {
            ScreenNavigator.SetVisible(root.Q("pause"), false);
            Touch.SetVisible(false);
            bigText.RemoveFromClassList("big-message__text--show");
            int pos = director.Player.Position;
            root.Q<Label>("results-title").text = pos == 1 ? "WINNER" : OrdinalPosition(pos) + " PLACE";
            root.Q<Label>("results-sub").text = RaceSession.EventName.ToUpperInvariant() + "  ·  " + director.track.displayName.ToUpperInvariant() + "  ·  " + director.TotalLaps + " LAPS";

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
                var posLabel = new Label((i + 1).ToString());
                posLabel.AddToClassList("res-cell");
                posLabel.AddToClassList("res-pos");
                var nameBox = new VisualElement();
                nameBox.AddToClassList("res-name");
                var name = new Label(r.displayName);
                name.AddToClassList("res-cell");
                var team = new Label(TeamName(r, teams));
                team.AddToClassList("res-team");
                nameBox.Add(name);
                nameBox.Add(team);
                string time = r.finished
                    ? (i == 0 ? Clock(r.ClassifiedTime) : "+" + (r.ClassifiedTime - winner).ToString("0.000"))
                    : "DNF  " + r.lapsCompleted + "L";
                if (r.penaltySeconds > 0f) time += " (+" + r.penaltySeconds.ToString("0") + "s)";
                var timeLabel = new Label(time);
                timeLabel.AddToClassList("res-cell");
                timeLabel.AddToClassList("res-time");
                var best = new Label(RaceClassification.FormatTime(r.bestLapMs));
                best.AddToClassList("res-cell");
                best.AddToClassList("res-best");
                if (r.id == director.FastestLapId) best.AddToClassList("res-best--fastest");
                row.Add(posLabel);
                row.Add(nameBox);
                row.Add(timeLabel);
                row.Add(best);
                table.Add(row);
            }

            var lines = root.Q("reward-lines");
            lines.Clear();
            var reward = director.Reward;
            if (reward == null) lines.Add(Line("Result not counted (test session)", "", "t-muted"));
            else
            {
                lines.Add(Line("Prize · " + OrdinalPosition(reward.position), "+$" + reward.prizeMoney.ToString("N0"), "t-money"));
                if (reward.fastestLapBonus > 0) lines.Add(Line("Fastest lap", "+$" + reward.fastestLapBonus.ToString("N0"), "t-money"));
                if (director.Entry != null && director.Entry.feeCharged > 0) lines.Add(Line("Entry fee", "-$" + director.Entry.feeCharged.ToString("N0"), "t-red"));
                if (director.Entry != null && director.Entry.sponsorCovered) lines.Add(Line("Entry fee", "SPONSORED", "t-gold"));
                lines.Add(Line("Reputation", "+" + reward.reputationGained + " REP", "t-blue"));
                lines.Add(Line("Championship", "+" + reward.championshipPoints + " PTS", "t-gold"));
                if (reward.newTrackRecord) lines.Add(Line("Personal best", RaceClassification.FormatTime(director.Player.Laps.BestLapMs), "t-purple"));
            }
            root.Q<Label>("reward-balance").text = "$" + GameServices.Save.career.money.ToString("N0");
            ScreenNavigator.SetVisible(root.Q("results"), true);
        }

        static string TeamName(RacerSnapshot r, List<TeamProfile> teams)
        {
            if (r.isPlayer) return "Privateer";
            foreach (var d in GameServices.Save.aiDrivers)
                if (d.id == r.id)
                    foreach (var t in teams)
                        if (t.id == d.teamId) return t.displayName;
            return "";
        }

        static VisualElement Line(string label, string amount, string colourClass)
        {
            var row = new VisualElement();
            row.AddToClassList("reward-line");
            var l = new Label(label);
            l.AddToClassList("reward-line__label");
            var a = new Label(amount);
            a.AddToClassList("reward-line__amount");
            a.AddToClassList(colourClass);
            row.Add(l);
            row.Add(a);
            return row;
        }
    }
}
