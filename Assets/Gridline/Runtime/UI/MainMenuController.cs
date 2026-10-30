using Gridline.Core;
using Gridline.Platform;
using Gridline.Race;
using Gridline.Track;
using Gridline.Vehicle;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.UIElements;

namespace Gridline.UI
{
    /// <summary>Main menu (MainMenu.uxml): career card, next event, settings sheet, career history and the showroom car.</summary>
    [RequireComponent(typeof(UIDocument))]
    public class MainMenuController : MonoBehaviour
    {
        public static readonly string[] RequiredElements =
        {
            "menu", "driver-name", "driver-rank", "stat-money", "stat-points", "stat-wins", "stat-podiums",
            "event-name", "event-track", "event-map", "event-laps", "event-entry", "event-prize", "event-best", "race-button",
            "career-button", "settings-button", "version", "settings-sheet", "settings-close", "steer-touch", "steer-tilt",
            "sensitivity", "sensitivity-value", "gear-auto", "gear-manual", "quality-0", "quality-1", "quality-2",
            "fps-off", "fps-on", "reset-career", "career-sheet", "career-close", "history", "ledger",
            "confirm", "confirm-cancel", "confirm-ok",
        };

        public GameObject carPrefab;
        public Material playerLivery;
        public Transform showroomAnchor;
        public Camera menuCamera;
        public float orbitSpeed = 6f;

        VisualElement root;
        ScreenNavigator nav;
        float orbit;

        void Start()
        {
            Time.timeScale = 1f;
            GameServices.ApplySettings();
            if (carPrefab != null && showroomAnchor != null) PlaceShowroomCar(VehicleSetup.CreateVisualClone(carPrefab, showroomAnchor, playerLivery));
            root = GetComponent<UIDocument>().rootVisualElement;
            ScreenNavigator.Validate(root, RequiredElements, nameof(MainMenuController));
            nav = new ScreenNavigator(root);
            SafeArea.Apply(root.Q("menu"));
            Bind();
            Refresh();
            Debug.Log("[GRIDLINE] Menu ready. Version " + Application.version);
        }

        void Bind()
        {
            Click("race-button", OnRace);
            Click("settings-button", () => nav.Open("settings-sheet"));
            Click("settings-close", () => nav.Close("settings-sheet"));
            Click("career-button", () => { FillCareer(); nav.Open("career-sheet"); });
            Click("career-close", () => nav.Close("career-sheet"));
            Click("steer-touch", () => Change(s => s.steeringMode = SteeringMode.TouchButtons));
            Click("steer-tilt", () => Change(s => s.steeringMode = SteeringMode.Tilt));
            Click("gear-auto", () => Change(s => s.transmission = TransmissionMode.Automatic));
            Click("gear-manual", () => Change(s => s.transmission = TransmissionMode.Manual));
            for (int i = 0; i < 3; i++)
            {
                int level = i;
                Click("quality-" + i, () => Change(s => s.qualityLevel = level));
            }
            Click("fps-off", () => Change(s => s.showFps = false));
            Click("fps-on", () => Change(s => s.showFps = true));
            Click("reset-career", () => nav.Open("confirm"));
            Click("confirm-cancel", () => nav.Close("confirm"));
            Click("confirm-ok", () =>
            {
                GameServices.ResetCareer();
                nav.Close("confirm");
                Refresh();
            });
            var slider = root.Q<Slider>("sensitivity");
            if (slider != null)
                slider.RegisterValueChangedCallback(e => Change(s => s.steeringSensitivity = Mathf.Round(e.newValue * 10f) / 10f, false));
            var map = root.Q("event-map");
            if (map != null) map.Add(new TrackMap(CircuitLayout.BuildCentreline(CircuitLayout.AshfordControlPoints, 6f)));
        }

        void Click(string name, System.Action action)
        {
            var b = root.Q<Button>(name);
            if (b != null) b.clicked += action;
        }

        void Change(System.Action<GameSettings> edit, bool refreshSlider = true)
        {
            edit(GameServices.Settings);
            GameServices.ApplySettings();
            GameServices.Persist();
            Refresh(refreshSlider);
        }

        void Refresh(bool refreshSlider = true)
        {
            var save = GameServices.Save;
            var c = save.career;
            var cfg = GameServices.Economy;
            Set("driver-name", c.driverName.ToUpperInvariant());
            Set("driver-rank", "AMATEUR  ·  REPUTATION " + c.reputation + "  ·  " + c.racesEntered + " RACES");
            Set("stat-money", "$" + c.money.ToString("N0"));
            Set("stat-points", c.championshipPoints.ToString());
            Set("stat-wins", c.wins.ToString());
            Set("stat-podiums", c.podiums.ToString());

            Set("event-name", RaceSession.EventName.ToUpperInvariant());
            Set("event-track", CircuitLayout.AshfordName + "  ·  2.36 km  ·  " + (RaceSession.AiOpponents + 1) + " cars");
            Set("event-laps", RaceSession.Laps + " LAPS");
            bool sponsored = c.money < cfg.amateurEntryFee && cfg.sponsorCoversEntryWhenBroke;
            Set("event-entry", sponsored ? "ENTRY SPONSORED" : "ENTRY $" + cfg.amateurEntryFee.ToString("N0"));
            Set("event-prize", "WIN $" + cfg.PrizeFor(1).ToString("N0"));
            Set("event-best", "PERSONAL BEST " + RaceClassification.FormatTime(c.GetBestLap(CircuitLayout.AshfordId)));
            Set("version", "v" + Application.version + "  ·  Unity " + Application.unityVersion);

            var s = save.settings;
            Segment("steer-touch", s.steeringMode == SteeringMode.TouchButtons);
            Segment("steer-tilt", s.steeringMode == SteeringMode.Tilt);
            Segment("gear-auto", s.transmission == TransmissionMode.Automatic);
            Segment("gear-manual", s.transmission == TransmissionMode.Manual);
            for (int i = 0; i < 3; i++) Segment("quality-" + i, s.qualityLevel == i);
            Segment("fps-off", !s.showFps);
            Segment("fps-on", s.showFps);
            Set("sensitivity-value", s.steeringSensitivity.ToString("0.0"));
            if (refreshSlider) root.Q<Slider>("sensitivity")?.SetValueWithoutNotify(s.steeringSensitivity);
        }

        void FillCareer()
        {
            var save = GameServices.Save;
            var history = root.Q<ScrollView>("history");
            history.Clear();
            if (save.history.Count == 0) history.Add(Row("—", "No races yet", "Enter your first event from the menu.", ""));
            for (int i = save.history.Count - 1; i >= 0; i--)
            {
                var h = save.history[i];
                history.Add(Row("P" + h.position, "Race " + h.raceIndex + "  ·  " + CircuitLayout.AshfordName,
                    "Best lap " + RaceClassification.FormatTime(h.bestLapMs) + "  ·  " + h.fieldSize + " starters",
                    (h.moneyEarned >= 0 ? "+$" : "−$") + Mathf.Abs(h.moneyEarned).ToString("N0")));
            }
            var ledger = root.Q<ScrollView>("ledger");
            ledger.Clear();
            var entries = save.career.ledger;
            for (int i = entries.Count - 1; i >= 0 && i >= entries.Count - 12; i--)
            {
                var e = entries[i];
                ledger.Add(Row("", e.reason, "Balance $" + e.balanceAfter.ToString("N0"), (e.amount >= 0 ? "+$" : "−$") + Mathf.Abs(e.amount).ToString("N0")));
            }
        }

        static VisualElement Row(string pos, string title, string detail, string money)
        {
            var row = new VisualElement();
            row.AddToClassList("history-row");
            var p = new Label(pos);
            p.AddToClassList("history-row__pos");
            var main = new VisualElement();
            main.AddToClassList("history-row__main");
            main.Add(new Label(title));
            var d = new Label(detail);
            d.AddToClassList("t-muted");
            d.AddToClassList("t-regular");
            main.Add(d);
            var m = new Label(money);
            m.AddToClassList("history-row__money");
            m.AddToClassList(money.StartsWith("+") ? "t-green" : "t-muted");
            row.Add(p);
            row.Add(main);
            row.Add(m);
            return row;
        }

        void Set(string name, string text)
        {
            var l = root.Q<Label>(name);
            if (l != null) l.text = text;
        }

        void Segment(string name, bool on)
        {
            root.Q(name)?.EnableInClassList("segment--on", on);
        }

        void OnRace()
        {
            RaceSession.AutopilotPlayer = false;
            RaceSession.AffectsCareer = true;
            RaceSession.EntryPaid = false;
            GameServices.Persist();
            SceneManager.LoadScene(RaceSession.RaceScene);
        }

        void PlaceShowroomCar(GameObject car)
        {
            // Rest the tyres on the floor whatever the prefab's pivot height is.
            var renderers = car.GetComponentsInChildren<Renderer>();
            if (renderers.Length == 0) return;
            var b = renderers[0].bounds;
            foreach (var r in renderers) b.Encapsulate(r.bounds);
            car.transform.position += new Vector3(showroomAnchor.position.x - b.center.x, showroomAnchor.position.y - b.min.y, showroomAnchor.position.z - b.center.z);
        }

        void Update()
        {
            // Android system back button closes the top sheet/modal.
            if (UnityEngine.Input.GetKeyDown(KeyCode.Escape) && nav != null) nav.Back();
            if (menuCamera == null || showroomAnchor == null) return;
            orbit += orbitSpeed * Time.deltaTime;
            Vector3 focus = showroomAnchor.position + Vector3.up * 0.7f;
            Quaternion rot = Quaternion.Euler(0f, orbit + 210f, 0f);
            menuCamera.transform.position = focus + rot * new Vector3(0f, 1.1f, -6.2f);
            // Keep the car right of centre, clear of the menu column on the left.
            menuCamera.transform.rotation = Quaternion.LookRotation(focus - menuCamera.transform.position) * Quaternion.Euler(0f, -16f, 0f);
        }
    }
}
