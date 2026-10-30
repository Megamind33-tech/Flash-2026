using Gridline.Core;
using Gridline.Race;
using Gridline.Track;
using RVP;
using UnityEngine;

namespace Gridline.AI
{
    /// <summary>
    /// Circuit-racing AI that drives an RVP vehicle through its public input API.
    /// Steering: pure pursuit on the precomputed racing line. Speed: track speed profile scaled by the driver's
    /// persistent attributes (skill, consistency, aggression), with traffic awareness for following and overtaking.
    /// </summary>
    [RequireComponent(typeof(VehicleParent))]
    [DisallowMultipleComponent]
    public class RacingAIDriver : MonoBehaviour
    {
        public float steerGain = 1.9f;
        public float minLookahead = 7f;
        public float maxLookahead = 30f;
        public float lookaheadPerMs = 0.55f;
        [Tooltip("Speed error (m/s) above which the AI brakes instead of lifting")]
        public float brakeThreshold = 1.2f;
        public float senseRange = 28f;
        public LayerMask vehicleMask = 1 << 9;

        public bool Driving { get; set; }

        VehicleParent vp;
        Rigidbody rb;
        RaceCar car;
        TrackPath track;
        DriverProfile profile;
        DeterministicRandom rng;
        float paceFactor = 0.94f;
        float lapPaceJitter;
        int lastLap = -1;
        float laneOffset;
        float targetLane;
        float laneTimer;

        public void Configure(TrackPath path, DriverProfile driver, uint seed)
        {
            track = path;
            profile = driver;
            rng = new DeterministicRandom(seed);
            if (profile != null) paceFactor = profile.PaceFactor;
        }

        void Awake()
        {
            vp = GetComponent<VehicleParent>();
            rb = GetComponent<Rigidbody>();
            car = GetComponent<RaceCar>();
        }

        void FixedUpdate()
        {
            if (track == null || vp == null) return;
            if (!Driving)
            {
                Hold();
                return;
            }

            if (car != null && car.Laps != null && car.Laps.CurrentLap != lastLap)
            {
                lastLap = car.Laps.CurrentLap;
                float noise = profile != null ? profile.PaceNoise : 0.01f;
                lapPaceJitter = rng != null ? Mathf.Clamp(rng.Gaussian() * noise, -2f * noise, 2f * noise) : 0f;
            }

            float d = car != null ? car.TrackDistance : 0f;
            float speed = Vector3.Dot(rb.linearVelocity, transform.forward);

            UpdateTraffic(d, speed, out float trafficSpeedCap);
            laneOffset = Mathf.MoveTowards(laneOffset, targetLane, 1.6f * Time.fixedDeltaTime);

            // Steering: pure pursuit on the racing line plus the current overtaking lane.
            float lookahead = Mathf.Clamp(minLookahead + Mathf.Max(0f, speed) * lookaheadPerMs, minLookahead, maxLookahead);
            float ahead = d + lookahead;
            float lateral = Mathf.Clamp(track.RacingLineOffsetAt(ahead) + laneOffset, -track.halfWidth + 1.4f, track.halfWidth - 1.4f);
            Vector3 target = track.PositionAt(ahead) + track.RightAt(ahead) * lateral;
            Vector3 local = transform.InverseTransformPoint(target);
            float angle = Mathf.Atan2(local.x, Mathf.Max(0.1f, local.z));
            vp.SetSteer(Mathf.Clamp(angle * steerGain, -1f, 1f));

            // Speed: look slightly ahead on the profile so braking starts before the corner, not in it.
            float profileSpeed = Mathf.Min(track.TargetSpeedAt(d + Mathf.Max(0f, speed) * 0.35f), track.TargetSpeedAt(d + 4f));
            float targetSpeed = Mathf.Min(profileSpeed * (paceFactor + lapPaceJitter), trafficSpeedCap);
            float error = targetSpeed - speed;

            if (error > 0f)
            {
                vp.SetAccel(Mathf.Clamp01(0.35f + error * 0.25f));
                vp.SetBrake(0f);
            }
            else if (error < -brakeThreshold && speed > 3f)
            {
                // Brake input reverses the car at low speed on RVP prefabs, so only brake while moving forward.
                vp.SetAccel(0f);
                vp.SetBrake(Mathf.Clamp01(-error * 0.12f));
            }
            else
            {
                vp.SetAccel(0.1f);
                vp.SetBrake(0f);
            }
            vp.SetEbrake(0f);
        }

        void Hold()
        {
            vp.SetAccel(0f);
            vp.SetBrake(0f);
            vp.SetSteer(0f);
            vp.SetEbrake(1f);
        }

        void UpdateTraffic(float d, float speed, out float speedCap)
        {
            speedCap = float.MaxValue;
            laneTimer -= Time.fixedDeltaTime;
            Vector3 origin = transform.position + Vector3.up * 0.6f;
            float range = senseRange + Mathf.Max(0f, speed) * 0.4f;
            if (Physics.SphereCast(origin, 1.1f, transform.forward, out RaycastHit hit, range, vehicleMask, QueryTriggerInteraction.Ignore)
                && hit.rigidbody != null && hit.rigidbody != rb)
            {
                float otherSpeed = Vector3.Dot(hit.rigidbody.linearVelocity, transform.forward);
                float closing = speed - otherSpeed;
                float aggression = profile != null ? profile.Aggression01 : 0.5f;
                if (closing > 0.5f && laneTimer <= 0f)
                {
                    // Pull out to the side with more room relative to the car ahead.
                    float otherLateral = Vector3.Dot(hit.rigidbody.position - track.PositionAt(d), track.RightAt(d));
                    float side = otherLateral > 0f ? -1f : 1f;
                    targetLane = side * Mathf.Lerp(2.2f, 3.6f, aggression);
                    laneTimer = Mathf.Lerp(2.5f, 1.2f, aggression);
                }
                // Keep a speed-dependent gap; aggressive drivers follow closer.
                float gap = Mathf.Lerp(9f, 5f, aggression) + Mathf.Max(0f, speed) * 0.15f;
                if (hit.distance < gap && Mathf.Abs(targetLane) < 0.5f) speedCap = Mathf.Max(0f, otherSpeed - 1f);
            }
            else if (laneTimer <= 0f)
            {
                targetLane = 0f;
            }
        }
    }
}
