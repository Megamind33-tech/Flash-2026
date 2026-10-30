using System.Collections.Generic;
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
    /// <summary>Main menu (MainMenu.uxml): NativeUI-style list pages, player status (money/reputation) and the showroom car.</summary>
    [RequireComponent(typeof(UIDocument))]
    public class MainMenuController : MonoBehaviour
    {
        public static readonly string[] RequiredElements =
        {
            "menu", "nui", "nui-banner", "nui-subtitle", "nui-counter", "page-main", "race-button", "race-fee", "career-button",
            "settings-button", "page-settings", "opt-steering", "opt-steering-value", "sens-down", "sens-up", "sensitivity-value",
            "opt-gearbox", "opt-gearbox-value", "opt-graphics", "opt-graphics-value", "opt-fps", "opt-fps-value", "reset-career",
            "settings-back", "page-career", "stat-races", "stat-wins", "stat-points", "stat-best", "history", "career-back",
            "page-confirm", "confirm-ok", "confirm-cancel", "nui-desc", "nui-desc-text", "event-map",
            "status-money", "status-name", "rep-fill", "rep-rank", "version",
        };

        static readonly string[] Pages = { "page-main", "page-settings", "page-career", "page-confirm" };
        const int RepPerRank = 25;

        public GameObject carPrefab;
        public Material playerLivery;
        public Transform showroomAnchor;
        public Camera menuCamera;
        public float orbitSpeed = 6f;

        VisualElement root;
        readonly Stack<string> pageStack = new Stack<string>();
        float orbit;

        void Start()
        {
            Time.timeScale = 1f;
            GameServices.ApplySettings();
            if (carPrefab != null && showroomAnchor != null) PlaceShowroomCar(VehicleSetup.CreateVisualClone(carPrefab, showroomAnchor, playerLivery));
            root = GetComponent<UIDocument>().rootVisualElement;
            ScreenNavigator.Validate(root, RequiredElements, nameof(MainMenuController));
            SafeArea.Apply(root.Q("menu"));
            Bind();
            ShowPage("page-main", false);
            Debug.Log("[GRIDLINE] Menu ready. Version " + Application.version);
        }

        void Bind()
        {
            Click("race-button", OnRace);
            Click("career-button", () => ShowPage("page-career"));
            Click("settings-button", () => ShowPage("page-settings"));
            Click("settings-back", Back);
            Click("career-back", Back);
            Click("opt-steering", () => Change(s => s.steeringMode = s.steeringMode == SteeringMode.Tilt ? SteeringMode.TouchButtons : SteeringMode.Tilt));
            Click("opt-gearbox", () => Change(s => s.transmission = s.transmission == TransmissionMode.Manual ? TransmissionMode.Automatic : TransmissionMode.Manual));
            Click("opt-graphics", () => Change(s => s.qualityLevel = (s.qualityLevel + 1) % 3));
            Click("opt-fps", () => Change(s => s.showFps = !s.showFps));
            Click("sens-down", () => Change(s => s.steeringSensitivity = Mathf.Clamp(Mathf.Round((s.steeringSensitivity - 0.1f) * 10f) / 10f, 0.3f, 2f)));
            Click("sens-up", () => Change(s => s.steeringSensitivity = Mathf.Clamp(Mathf.Round((s.steeringSensitivity + 0.1f) * 10f) / 10f, 0.3f, 2f)));
            Click("reset-career", () => ShowPage("page-confirm"));
            Click("confirm-cancel", Back);
            Click("confirm-ok", () =>
            {
                GameServices.ResetCareer();
                Back();
            });
            var map = root.Q("event-map");
            if (map != null) map.Add(new TrackMap(CircuitLayout.BuildCentreline(CircuitLayout.AshfordControlPoints, 6f)));
        }

        void Click(string name, System.Action action)
        {
            var b = root.Q<Button>(name);
            if (b != null) b.clicked += action;
        }

        void ShowPage(string page, bool push = true)
        {
            if (push && pageStack.Count > 0 && pageStack.Peek() == page) return;
            if (push) pageStack.Push(page);
            else
            {
                pageStack.Clear();
                pageStack.Push(page);
            }
            foreach (var p in Pages) ScreenNavigator.SetVisible(root.Q(p), p == page);
            Refresh();
        }

        void Back()
        {
            if (pageStack.Count <= 1) return;
            pageStack.Pop();
            string page = pageStack.Peek();
            foreach (var p in Pages) ScreenNavigator.SetVisible(root.Q(p), p == page);
            Refresh();
        }

        void Change(System.Action<GameSettings> edit)
        {
            edit(GameServices.Settings);
            GameServices.ApplySettings();
            GameServices.Persist();
            Refresh();
        }

        void Refresh()
        {
            var save = GameServices.Save;
            var c = save.career;
            var cfg = GameServices.Economy;
            string page = pageStack.Count > 0 ? pageStack.Peek() : "page-main";

            Set("status-money", "$" + c.money.ToString("N0"));
            Set("status-name", c.driverName.ToUpperInvariant());
            int rank = 1 + c.reputation / RepPerRank;
            Set("rep-rank", rank.ToString());
            var fill = root.Q("rep-fill");
            if (fill != null) fill.style.width = Length.Percent(100f * (c.reputation % RepPerRank) / RepPerRank);
            Set("version", "v" + Application.version + "  ·  Unity " + Application.unityVersion);

            bool sponsored = c.money < cfg.amateurEntryFee && cfg.sponsorCoversEntryWhenBroke;
            Set("race-fee", sponsored ? "SPONSORED" : "$" + cfg.amateurEntryFee.ToString("N0"));

            var s = save.settings;
            Set("opt-steering-value", s.steeringMode == SteeringMode.Tilt ? "Tilt" : "Touch");
            Set("sensitivity-value", s.steeringSensitivity.ToString("0.0"));
            Set("opt-gearbox-value", s.transmission == TransmissionMode.Manual ? "Manual" : "Automatic");
            Set("opt-graphics-value", new[] { "Low · 30 FPS", "Medium", "High" }[Mathf.Clamp(s.qualityLevel, 0, 2)]);
            Set("opt-fps-value", s.showFps ? "On" : "Off");

            Set("stat-races", c.racesEntered.ToString());
            Set("stat-wins", c.wins + " / " + c.podiums);
            Set("stat-points", c.championshipPoints.ToString());
            Set("stat-best", RaceClassification.FormatTime(c.GetBestLap(CircuitLayout.AshfordId)));

            string subtitle, desc;
            int count;
            switch (page)
            {
                case "page-settings":
                    subtitle = "SETTINGS"; count = 7;
                    desc = "Tap an option to change it. Tilt steering uses the phone's motion sensor; a Bluetooth controller also works.";
                    break;
                case "page-career":
                    subtitle = "CAREER"; count = 5;
                    desc = "Amateur driver · reputation " + c.reputation + " · rank " + rank + ". Win events to earn money and attract team offers.";
                    FillHistory();
                    break;
                case "page-confirm":
                    subtitle = "RESET CAREER?"; count = 2;
                    desc = "Your money, reputation, records and race history will be erased. Settings are kept.";
                    break;
                default:
                    subtitle = "THE RACING LEAGUE"; count = 3;
                    desc = RaceSession.EventName + "\n" + CircuitLayout.AshfordName + " · 2.36 km · " + RaceSession.Laps + " laps · " +
                           (RaceSession.AiOpponents + 1) + " cars\nWin $" + cfg.PrizeFor(1).ToString("N0") + " · Personal best " +
                           RaceClassification.FormatTime(c.GetBestLap(CircuitLayout.AshfordId));
                    break;
            }
            Set("nui-subtitle", subtitle);
            Set("nui-counter", count + " ITEMS");
            Set("nui-desc-text", desc);
            ScreenNavigator.SetVisible(root.Q("event-map"), page == "page-main");
        }

        void FillHistory()
        {
            var history = root.Q<ScrollView>("history");
            history.Clear();
            var h = GameServices.Save.history;
            for (int i = h.Count - 1; i >= 0 && i >= h.Count - 6; i--)
            {
                var e = h[i];
                var row = new VisualElement();
                row.AddToClassList("nui__item");
                row.AddToClassList("history-item");
                var l = new Label("Race " + e.raceIndex + " · P" + e.position + "/" + e.fieldSize + " · " + RaceClassification.FormatTime(e.bestLapMs));
                l.AddToClassList("nui__label");
                var m = new Label((e.moneyEarned >= 0 ? "+$" : "−$") + Mathf.Abs(e.moneyEarned).ToString("N0"));
                m.AddToClassList("nui__value");
                m.AddToClassList(e.moneyEarned >= 0 ? "t-money" : "t-red");
                row.Add(l);
                row.Add(m);
                history.Add(row);
            }
        }

        void Set(string name, string text)
        {
            var l = root.Q<Label>(name);
            if (l != null) l.text = text;
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
            // Android system back button walks back through the menu pages.
            if (UnityEngine.Input.GetKeyDown(KeyCode.Escape) && root != null) Back();
            if (menuCamera == null || showroomAnchor == null) return;
            orbit += orbitSpeed * Time.deltaTime;
            Vector3 focus = showroomAnchor.position + Vector3.up * 0.7f;
            Quaternion rot = Quaternion.Euler(0f, orbit + 210f, 0f);
            menuCamera.transform.position = focus + rot * new Vector3(0f, 1.1f, -6.2f);
            // Keep the car right of centre, clear of the menu list on the left.
            menuCamera.transform.rotation = Quaternion.LookRotation(focus - menuCamera.transform.position) * Quaternion.Euler(0f, -16f, 0f);
        }
    }
}
