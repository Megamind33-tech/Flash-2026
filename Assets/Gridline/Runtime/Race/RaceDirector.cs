using System.Collections;
using System.Collections.Generic;
using Gridline.AI;
using Gridline.CameraRig;
using Gridline.Core;
using Gridline.Input;
using Gridline.Platform;
using Gridline.Track;
using Gridline.UI;
using Gridline.Vehicle;
using UnityEngine;
using UnityEngine.SceneManagement;

namespace Gridline.Race
{
    public enum RacePhase { Setup, Countdown, Racing, Finishing, Results }

    /// <summary>
    /// Owns one race: spawns the grid, runs the countdown and race clock, keeps live positions,
    /// classifies the result, pays the player and persists the outcome.
    /// </summary>
    public class RaceDirector : MonoBehaviour
    {
        [Header("Scene references (set by the track builder)")]
        public TrackPath track;
        public GameObject carPrefab;
        public Material[] liveries;
        public RaceCamera raceCamera;
        public PerformanceLogger perfLogger;

        [Header("Grid")]
        public float gridFirstSlotBehindLine = 12f;
        public float gridRowSpacing = 8f;
        public float gridLateral = 2.6f;
        public float countdownSeconds = 3f;
        [Tooltip("Seconds the remaining cars get to finish after the player crosses the line")]
        public float finishWindow = 25f;
        [Tooltip("Safety cap on total race time per lap")]
        public float maxSecondsPerLap = 300f;

        public RacePhase Phase { get; private set; }
        public bool ClockRunning { get { return Phase == RacePhase.Racing || Phase == RacePhase.Finishing; } }
        public double RaceTime { get; private set; }
        public float CountdownRemaining { get; private set; }
        public int TotalLaps { get; private set; }
        public RaceCar Player { get; private set; }
        public readonly List<RaceCar> Cars = new List<RaceCar>();
        public List<RacerSnapshot> Standings { get; private set; }
        public RaceReward Reward { get; private set; }
        public RaceEntryReceipt Entry { get; private set; }
        public string FastestLapId { get; private set; }

        public event System.Action<string> Notice;
        public event System.Action ResultsReady;

        RaceHud hud;
        TouchControls touch;
        float finishWindowTimer;
        float standingsTimer;

        void Start()
        {
            StartCoroutine(Run());
        }

        IEnumerator Run()
        {
            Phase = RacePhase.Setup;
            GameServices.ApplySettings();
            var save = GameServices.Save;
            TotalLaps = Mathf.Max(1, RaceSession.Laps);

            if (RaceSession.AffectsCareer && !RaceSession.EntryPaid)
            {
                Entry = CareerService.EnterRace(save.career, GameServices.Economy, RaceSession.EventName);
                RaceSession.EntryPaid = true;
                GameServices.Persist();
            }

            SpawnGrid(save);
            BuildInterface(save.settings);

            // Let suspensions settle before the lights.
            yield return new WaitForSeconds(0.75f);
            Phase = RacePhase.Countdown;
            CountdownRemaining = countdownSeconds;
            while (CountdownRemaining > 0f)
            {
                CountdownRemaining -= Time.deltaTime;
                yield return null;
            }
            CountdownRemaining = 0f;
            Phase = RacePhase.Racing;
            RaceTime = 0;
            foreach (var c in Cars)
            {
                c.Laps.StartClock(0);
                SetDriving(c, true);
            }
            RaiseNotice("GO!");
        }

        void SpawnGrid(SaveGame save)
        {
            var drivers = save.aiDrivers;
            int aiCount = Mathf.Clamp(RaceSession.AiOpponents, 0, drivers.Count);
            int field = aiCount + 1;
            bool manual = save.settings.transmission == TransmissionMode.Manual;
            for (int slot = 0; slot < field; slot++)
            {
                // A rookie starts from the back of the grid; AI drivers line up in roster order.
                bool isPlayer = slot == field - 1;
                DriverProfile profile = isPlayer ? null : drivers[slot];
                float d = track.Wrap(-(gridFirstSlotBehindLine + slot * gridRowSpacing));
                Vector3 pos = track.PositionAt(d) + track.RightAt(d) * (slot % 2 == 0 ? -gridLateral : gridLateral);
                if (Physics.Raycast(pos + Vector3.up * 30f, Vector3.down, out RaycastHit hit, 60f, ~0, QueryTriggerInteraction.Ignore)) pos = hit.point;
                Quaternion rot = Quaternion.LookRotation(track.TangentAt(d), Vector3.up);

                var go = Instantiate(carPrefab, pos + Vector3.up * 1.0f, rot);
                go.name = isPlayer ? "Car_Player" : "Car_" + profile.id;
                Material livery = liveries != null && liveries.Length > 0 ? liveries[(isPlayer ? 0 : slot + 1) % liveries.Length] : null;
                VehicleSetup.Prepare(go, livery, isPlayer && manual);

                var car = go.AddComponent<RaceCar>();
                car.racerId = isPlayer ? "player" : profile.id;
                car.displayName = isPlayer ? save.career.driverName : profile.displayName;
                car.isPlayer = isPlayer;
                car.gridSlot = slot;
                car.profile = profile;
                car.Initialise(this, track, TotalLaps);
                car.Notice = OnCarNotice;
                car.Laps.LapCompleted += (lap, ms) => OnLap(car, lap, ms);

                var ai = go.AddComponent<RacingAIDriver>();
                ai.Configure(track, profile ?? PlayerAutopilotProfile(), (uint)(1000 + slot * 7919 + save.career.racesEntered * 31));
                ai.enabled = !isPlayer || RaceSession.AutopilotPlayer;
                if (isPlayer)
                {
                    var input = go.AddComponent<PlayerCarInput>();
                    input.settings = save.settings;
                    input.enabled = !RaceSession.AutopilotPlayer;
                    Player = car;
                }
                Cars.Add(car);
            }
            Standings = Classify();
        }

        static DriverProfile PlayerAutopilotProfile()
        {
            return new DriverProfile { id = "player", displayName = "Autopilot", skill = 70, experience = 50, aggression = 40, consistency = 80 };
        }

        void BuildInterface(GameSettings settings)
        {
            if (raceCamera != null)
            {
                raceCamera.mode = settings.camera;
                raceCamera.SetTarget(Player.transform, Player.Body);
            }
            touch = new GameObject("TouchInput").AddComponent<TouchControls>();
            touch.Build(settings.steeringMode == SteeringMode.TouchButtons, settings.transmission == TransmissionMode.Manual);
            touch.SetVisible(!RaceSession.AutopilotPlayer);
            var input = Player.GetComponent<PlayerCarInput>();
            if (input != null) input.touch = touch;
            hud = new GameObject("RaceHud").AddComponent<RaceHud>();
            hud.Build(this, settings);
        }

        void SetDriving(RaceCar car, bool driving)
        {
            var ai = car.GetComponent<RacingAIDriver>();
            if (ai != null) ai.Driving = driving;
            var input = car.GetComponent<PlayerCarInput>();
            if (input != null) input.Driving = driving;
        }

        void FixedUpdate()
        {
            if (ClockRunning) RaceTime += Time.fixedDeltaTime;
        }

        void Update()
        {
            if (Phase == RacePhase.Setup || Phase == RacePhase.Results) return;
            standingsTimer -= Time.unscaledDeltaTime;
            if (standingsTimer <= 0f)
            {
                standingsTimer = 0.25f;
                Standings = Classify();
            }
            if (!ClockRunning) return;

            if (Phase == RacePhase.Racing && Player.Laps.Finished)
            {
                Phase = RacePhase.Finishing;
                finishWindowTimer = finishWindow;
                // Hand the player car to the AI for the slow-down lap.
                var ai = Player.GetComponent<RacingAIDriver>();
                var input = Player.GetComponent<PlayerCarInput>();
                if (input != null) input.enabled = false;
                if (ai != null)
                {
                    ai.enabled = true;
                    ai.Driving = true;
                }
                touch.SetVisible(false);
                RaiseNotice("FINISH — P" + Player.Position);
            }

            bool allDone = true;
            foreach (var c in Cars) allDone &= c.Laps.Finished;
            if (Phase == RacePhase.Finishing)
            {
                finishWindowTimer -= Time.deltaTime;
                if (allDone || finishWindowTimer <= 0f) CompleteRace();
            }
            else if (RaceTime > maxSecondsPerLap * TotalLaps)
            {
                CompleteRace();
            }
        }

        List<RacerSnapshot> Classify()
        {
            var snaps = new List<RacerSnapshot>(Cars.Count);
            foreach (var c in Cars) snaps.Add(c.Snapshot());
            var order = RaceClassification.Classify(snaps);
            for (int i = 0; i < order.Count; i++)
                foreach (var c in Cars)
                    if (c.racerId == order[i].id) c.Position = i + 1;
            return order;
        }

        void CompleteRace()
        {
            if (Phase == RacePhase.Results) return;
            Phase = RacePhase.Results;
            Standings = Classify();
            FastestLapId = RaceClassification.FastestLapHolder(Standings);
            foreach (var c in Cars) SetDriving(c, false);
            if (touch != null) touch.SetVisible(false);

            var save = GameServices.Save;
            int playerPos = Player.Position;
            if (RaceSession.AffectsCareer)
            {
                Reward = CareerService.ApplyResult(save.career, GameServices.Economy, RaceSession.EventName, track.trackId,
                    playerPos, Cars.Count, Player.Laps.BestLapMs, FastestLapId == Player.racerId);
                foreach (var c in Cars)
                    if (!c.isPlayer && c.profile != null) c.profile.RecordResult(c.Position);
                save.AddHistory(new RaceHistoryEntry
                {
                    raceIndex = save.career.racesEntered,
                    trackId = track.trackId,
                    position = playerPos,
                    fieldSize = Cars.Count,
                    bestLapMs = Player.Laps.BestLapMs,
                    moneyEarned = Reward.TotalMoney - (Entry != null ? Entry.feeCharged : 0),
                });
                RaceSession.EntryPaid = false;
                GameServices.Persist();
            }
            if (perfLogger != null) perfLogger.Flush();
            Debug.Log("[GRIDLINE] Race complete. Player P" + playerPos + "/" + Cars.Count + " best lap " +
                      RaceClassification.FormatTime(Player.Laps.BestLapMs) + " race time " + RaceTime.ToString("F1") + "s");
            ResultsReady?.Invoke();
        }

        void OnLap(RaceCar car, int lap, int ms)
        {
            if (!car.isPlayer) return;
            if (lap == TotalLaps - 1) RaiseNotice("FINAL LAP");
            else if (lap < TotalLaps && car.Laps.BestLapMs == ms) RaiseNotice("LAP " + lap + "  " + RaceClassification.FormatTime(ms));
        }

        void OnCarNotice(RaceCar car, string message)
        {
            if (car.isPlayer) RaiseNotice(message);
        }

        void RaiseNotice(string message)
        {
            Notice?.Invoke(message);
        }

        // ---- Commands used by the HUD / pause menu ----

        public void SetPaused(bool paused)
        {
            Time.timeScale = paused ? 0f : 1f;
            AudioListener.pause = paused;
        }

        public void Restart()
        {
            SetPaused(false);
            SceneManager.LoadScene(SceneManager.GetActiveScene().name);
        }

        public void QuitToMenu()
        {
            SetPaused(false);
            // Quitting forfeits the entry fee already paid.
            RaceSession.EntryPaid = false;
            if (perfLogger != null && Phase != RacePhase.Results) perfLogger.Flush();
            SceneManager.LoadScene(RaceSession.MenuScene);
        }

        public CameraMode CycleCamera()
        {
            if (raceCamera == null) return CameraMode.Chase;
            var mode = raceCamera.Cycle();
            GameServices.Settings.camera = mode;
            return mode;
        }

        void OnDestroy()
        {
            Time.timeScale = 1f;
            AudioListener.pause = false;
        }
    }
}
