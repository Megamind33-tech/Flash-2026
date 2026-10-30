using Gridline.Core;
using Gridline.Track;
using RVP;
using UnityEngine;

namespace Gridline.Race
{
    /// <summary>Per-competitor race state: identity, lap tracking, track limits and stuck recovery.</summary>
    [DisallowMultipleComponent]
    public class RaceCar : MonoBehaviour
    {
        public string racerId;
        public string displayName;
        public bool isPlayer;
        public int gridSlot;
        public DriverProfile profile;

        [Header("Track limits")]
        public float offTrackMargin = 1.5f;
        public float offTrackGainAllowance = 25f;
        public int warningsBeforePenalty = 3;
        public float penaltyPerOffence = 5f;

        [Header("Recovery")]
        public float stuckSpeed = 1.5f;
        public float stuckSeconds = 5f;
        public float rolledSeconds = 3f;
        public float lostLateral = 40f;

        public LapTracker Laps { get; private set; }
        public VehicleParent Vehicle { get; private set; }
        public Rigidbody Body { get; private set; }
        public float TrackDistance { get; private set; }
        public float Lateral { get; private set; }
        public int Position { get; set; }
        public float PenaltySeconds { get; private set; }
        public int TrackLimitWarnings { get; private set; }
        public int Recoveries { get; private set; }
        public float SpeedKmh { get { return Body != null ? Body.linearVelocity.magnitude * 3.6f : 0f; } }

        public System.Action<RaceCar, string> Notice;

        TrackPath track;
        RaceDirector director;
        int segmentHint = -1;
        float stuckTimer, rolledTimer;
        bool offTrack;
        float offTrackStartProgress;

        public void Initialise(RaceDirector owner, TrackPath path, int totalLaps)
        {
            director = owner;
            track = path;
            Vehicle = GetComponent<VehicleParent>();
            Body = GetComponent<Rigidbody>();
            Laps = new LapTracker(track.Length, totalLaps);
            TrackDistance = track.Project(transform.position, ref segmentHint, out float lateral);
            Lateral = lateral;
            Laps.Initialise(TrackDistance);
        }

        void FixedUpdate()
        {
            if (Laps == null) return;
            TrackDistance = track.Project(transform.position, ref segmentHint, out float lateral);
            Lateral = lateral;
            if (!director.ClockRunning) return;
            Laps.Update(TrackDistance, director.RaceTime);
            if (Laps.Finished) return;
            CheckTrackLimits();
            CheckRecovery();
        }

        void CheckTrackLimits()
        {
            bool outside = Mathf.Abs(Lateral) > track.halfWidth + offTrackMargin;
            if (outside && !offTrack)
            {
                offTrack = true;
                offTrackStartProgress = Laps.Progress;
            }
            else if (!outside && offTrack)
            {
                offTrack = false;
                // Gaining a lot of ground while fully off the circuit counts as cutting.
                if (Laps.Progress - offTrackStartProgress > offTrackGainAllowance)
                {
                    TrackLimitWarnings++;
                    if (TrackLimitWarnings >= warningsBeforePenalty)
                    {
                        TrackLimitWarnings = 0;
                        PenaltySeconds += penaltyPerOffence;
                        Notice?.Invoke(this, "+" + penaltyPerOffence.ToString("0") + "s PENALTY — TRACK LIMITS");
                    }
                    else
                    {
                        Notice?.Invoke(this, "TRACK LIMITS WARNING " + TrackLimitWarnings + "/" + warningsBeforePenalty);
                    }
                }
            }
        }

        void CheckRecovery()
        {
            float dt = Time.fixedDeltaTime;
            bool rolled = Vehicle != null && Vehicle.upDot < 0.3f;
            rolledTimer = rolled ? rolledTimer + dt : 0f;
            stuckTimer = Body != null && Body.linearVelocity.magnitude < stuckSpeed ? stuckTimer + dt : 0f;
            bool lost = Mathf.Abs(Lateral) > lostLateral || transform.position.y < -20f;
            // The player is never auto-recovered for being slow; they can stop deliberately.
            bool stuck = !isPlayer && stuckTimer > stuckSeconds;
            if (rolledTimer > rolledSeconds || lost || stuck) Recover();
        }

        /// <summary>Places the car back on the centreline a few metres behind its last progress point.</summary>
        public void Recover()
        {
            float d = track.Wrap(TrackDistance - 8f);
            Vector3 pos = track.PositionAt(d);
            Vector3 fwd = track.TangentAt(d);
            if (Physics.Raycast(pos + Vector3.up * 50f, Vector3.down, out RaycastHit hit, 100f, GlobalControl.groundMaskStatic, QueryTriggerInteraction.Ignore))
                pos = hit.point;
            transform.SetPositionAndRotation(pos + Vector3.up * 0.8f, Quaternion.LookRotation(fwd, Vector3.up));
            if (Body != null)
            {
                Body.linearVelocity = Vector3.zero;
                Body.angularVelocity = Vector3.zero;
            }
            segmentHint = -1;
            TrackDistance = track.Project(transform.position, ref segmentHint, out float lateral);
            Lateral = lateral;
            Laps.Relocate(TrackDistance);
            stuckTimer = rolledTimer = 0f;
            offTrack = false;
            Recoveries++;
            if (isPlayer) Notice?.Invoke(this, "CAR RECOVERED");
        }

        public RacerSnapshot Snapshot()
        {
            return new RacerSnapshot
            {
                id = racerId,
                displayName = displayName,
                isPlayer = isPlayer,
                finished = Laps.Finished,
                finishTime = Laps.FinishTime,
                penaltySeconds = PenaltySeconds,
                progress = Laps.Progress,
                lapsCompleted = Laps.LapsCompleted,
                bestLapMs = Laps.BestLapMs,
                gridSlot = gridSlot,
            };
        }
    }
}
