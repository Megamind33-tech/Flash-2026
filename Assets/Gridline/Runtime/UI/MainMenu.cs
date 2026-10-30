using Gridline.Core;
using Gridline.Platform;
using Gridline.Race;
using Gridline.Vehicle;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.UI;

namespace Gridline.UI
{
    /// <summary>Main menu: career summary, race entry, settings and a showroom view of the player's car.</summary>
    public class MainMenu : MonoBehaviour
    {
        public GameObject carPrefab;
        public Material playerLivery;
        public Transform showroomAnchor;
        public Camera menuCamera;
        public float orbitSpeed = 6f;

        Text careerText, raceButtonText;
        Button steeringBtn, transmissionBtn, qualityBtn, fpsBtn, resetBtn;
        Text sensitivityText;
        RectTransform settingsPanel;
        bool confirmReset;
        float orbit;

        void Start()
        {
            Time.timeScale = 1f;
            GameServices.ApplySettings();
            if (carPrefab != null && showroomAnchor != null) PlaceShowroomCar(VehicleSetup.CreateVisualClone(carPrefab, showroomAnchor, playerLivery));
            Build();
            Refresh();
            Debug.Log("[GRIDLINE] Menu ready. Version " + Application.version);
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

        void Build()
        {
            var canvas = UiFactory.CreateCanvas("MenuCanvas", 0);
            var root = canvas.transform;

            var title = UiFactory.Box(root, "Title", new Vector2(0, 1), new Vector2(0, 1), new Vector2(80, -60), new Vector2(900, 160));
            UiFactory.Label(title, "Text", "GRIDLINE", 110, TextAnchor.UpperLeft, UiFactory.TextPrimary, FontStyle.Bold);
            var sub = UiFactory.Box(root, "Subtitle", new Vector2(0, 1), new Vector2(0, 1), new Vector2(84, -185), new Vector2(900, 50));
            UiFactory.Label(sub, "Text", "THE RACING LEAGUE", 36, TextAnchor.UpperLeft, UiFactory.Accent, FontStyle.Bold);

            var card = UiFactory.Box(root, "Career", new Vector2(0, 0), new Vector2(0, 0), new Vector2(80, 330), new Vector2(760, 400));
            UiFactory.Panel(card, UiFactory.PanelColor);
            careerText = UiFactory.Label(UiFactory.Box(card, "Text", new Vector2(0, 1), new Vector2(0, 1), new Vector2(36, -28), new Vector2(700, 350)),
                "Body", "", 34, TextAnchor.UpperLeft, UiFactory.TextPrimary);
            careerText.supportRichText = true;

            var race = UiFactory.Box(root, "Race", new Vector2(0, 0), new Vector2(0, 0), new Vector2(80, 80), new Vector2(760, 210));
            var raceBtn = UiFactory.Button(race, "", OnRace, 40, true);
            raceButtonText = raceBtn.GetComponentInChildren<Text>();
            raceButtonText.supportRichText = true;

            var settingsBtn = UiFactory.Box(root, "SettingsButton", new Vector2(1, 1), new Vector2(1, 1), new Vector2(-60, -60), new Vector2(320, 110));
            UiFactory.Button(settingsBtn, "SETTINGS", () => settingsPanel.gameObject.SetActive(!settingsPanel.gameObject.activeSelf), 36);

            BuildSettings(root);
            var version = UiFactory.Box(root, "Version", new Vector2(1, 0), new Vector2(1, 0), new Vector2(-40, 24), new Vector2(600, 40));
            UiFactory.Label(version, "Text", "v" + Application.version + "  ·  Unity " + Application.unityVersion, 22, TextAnchor.LowerRight, UiFactory.TextMuted);
        }

        void BuildSettings(Transform root)
        {
            settingsPanel = UiFactory.Box(root, "Settings", new Vector2(1, 1), new Vector2(1, 1), new Vector2(-60, -190), new Vector2(720, 800));
            UiFactory.Panel(settingsPanel, UiFactory.PanelColor);
            float y = -30;
            steeringBtn = Row(settingsPanel, ref y, CycleSteering);
            transmissionBtn = Row(settingsPanel, ref y, CycleTransmission);

            var sens = UiFactory.Box(settingsPanel, "Sensitivity", new Vector2(0, 1), new Vector2(0, 1), new Vector2(30, y), new Vector2(660, 100));
            UiFactory.Button(UiFactory.Box(sens, "Minus", new Vector2(0, 0.5f), new Vector2(0, 0.5f), Vector2.zero, new Vector2(110, 100)), "−", () => AdjustSensitivity(-0.1f), 50);
            UiFactory.Button(UiFactory.Box(sens, "Plus", new Vector2(1, 0.5f), new Vector2(1, 0.5f), Vector2.zero, new Vector2(110, 100)), "+", () => AdjustSensitivity(0.1f), 50);
            sensitivityText = UiFactory.Label(sens, "Value", "", 32, TextAnchor.MiddleCenter, UiFactory.TextPrimary);
            y -= 120;

            qualityBtn = Row(settingsPanel, ref y, CycleQuality);
            fpsBtn = Row(settingsPanel, ref y, ToggleFps);
            resetBtn = Row(settingsPanel, ref y, ResetCareer);
            settingsPanel.gameObject.SetActive(false);
        }

        static Button Row(RectTransform panel, ref float y, UnityEngine.Events.UnityAction action)
        {
            var rt = UiFactory.Box(panel, "Row", new Vector2(0, 1), new Vector2(0, 1), new Vector2(30, y), new Vector2(660, 100));
            y -= 120;
            return UiFactory.Button(rt, "", action, 32);
        }

        void Refresh()
        {
            var save = GameServices.Save;
            var c = save.career;
            var cfg = GameServices.Economy;
            int best = c.GetBestLap(Track.CircuitLayout.AshfordId);
            careerText.text =
                "<b>" + c.driverName.ToUpperInvariant() + "</b>   <color=#A8AFBB>Amateur driver</color>\n" +
                "Balance            <b>$" + c.money.ToString("N0") + "</b>\n" +
                "Reputation         " + c.reputation + "\n" +
                "Races / Wins / Podiums   " + c.racesEntered + " / " + c.wins + " / " + c.podiums + "\n" +
                "Points             " + c.championshipPoints + "\n" +
                "Best lap (Ashford)  " + RaceClassification.FormatTime(best);
            bool sponsored = c.money < cfg.amateurEntryFee && cfg.sponsorCoversEntryWhenBroke;
            raceButtonText.text = "ENTER RACE\n<size=28>" + RaceSession.EventName + " · " + RaceSession.Laps + " laps · " +
                                  (sponsored ? "entry covered by sponsor" : "entry $" + cfg.amateurEntryFee) + "</size>";

            var s = save.settings;
            UiFactory.SetButtonLabel(steeringBtn, "STEERING: " + (s.steeringMode == SteeringMode.Tilt ? "TILT" : "TOUCH BUTTONS"));
            UiFactory.SetButtonLabel(transmissionBtn, "GEARBOX: " + (s.transmission == TransmissionMode.Manual ? "MANUAL" : "AUTOMATIC"));
            sensitivityText.text = "STEERING SENSITIVITY  " + s.steeringSensitivity.ToString("0.0");
            string[] q = { "LOW (30 FPS)", "MEDIUM", "HIGH" };
            UiFactory.SetButtonLabel(qualityBtn, "GRAPHICS: " + q[Mathf.Clamp(s.qualityLevel, 0, 2)]);
            UiFactory.SetButtonLabel(fpsBtn, "SHOW FPS: " + (s.showFps ? "ON" : "OFF"));
            UiFactory.SetButtonLabel(resetBtn, confirmReset ? "TAP AGAIN TO RESET CAREER" : "RESET CAREER");
        }

        void OnRace()
        {
            RaceSession.AutopilotPlayer = false;
            RaceSession.AffectsCareer = true;
            RaceSession.EntryPaid = false;
            GameServices.Persist();
            SceneManager.LoadScene(RaceSession.RaceScene);
        }

        void CycleSteering()
        {
            var s = GameServices.Settings;
            s.steeringMode = s.steeringMode == SteeringMode.Tilt ? SteeringMode.TouchButtons : SteeringMode.Tilt;
            SaveSettings();
        }

        void CycleTransmission()
        {
            var s = GameServices.Settings;
            s.transmission = s.transmission == TransmissionMode.Manual ? TransmissionMode.Automatic : TransmissionMode.Manual;
            SaveSettings();
        }

        void AdjustSensitivity(float delta)
        {
            var s = GameServices.Settings;
            s.steeringSensitivity = Mathf.Clamp(Mathf.Round((s.steeringSensitivity + delta) * 10f) / 10f, 0.3f, 2f);
            SaveSettings();
        }

        void CycleQuality()
        {
            var s = GameServices.Settings;
            s.qualityLevel = (s.qualityLevel + 1) % 3;
            SaveSettings();
        }

        void ToggleFps()
        {
            GameServices.Settings.showFps = !GameServices.Settings.showFps;
            SaveSettings();
        }

        void ResetCareer()
        {
            if (!confirmReset)
            {
                confirmReset = true;
                Refresh();
                return;
            }
            confirmReset = false;
            GameServices.ResetCareer();
            Refresh();
        }

        void SaveSettings()
        {
            confirmReset = false;
            GameServices.ApplySettings();
            GameServices.Persist();
            Refresh();
        }

        void Update()
        {
            if (menuCamera == null || showroomAnchor == null) return;
            orbit += orbitSpeed * Time.deltaTime;
            Vector3 focus = showroomAnchor.position + Vector3.up * 0.7f;
            Quaternion rot = Quaternion.Euler(0f, orbit + 210f, 0f);
            menuCamera.transform.position = focus + rot * new Vector3(0f, 1.1f, -6.2f);
            // Frame the car on the right so the menu panels on the left stay clear.
            menuCamera.transform.rotation = Quaternion.LookRotation(focus - menuCamera.transform.position) * Quaternion.Euler(0f, -14f, 0f);
        }
    }
}
