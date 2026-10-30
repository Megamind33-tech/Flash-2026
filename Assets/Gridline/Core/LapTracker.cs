using System;
using System.Collections.Generic;

namespace Gridline.Core
{
    /// <summary>
    /// Engine-independent lap, sector and progress bookkeeping for one competitor.
    /// Feed it the car's projected distance along the closed track centreline every physics step.
    /// Progress is continuous: negative on the grid (behind the line), 0 at the start line, L after one lap.
    /// </summary>
    public class LapTracker
    {
        public readonly float TrackLength;
        public readonly int TotalLaps;
        public readonly int SectorCount;

        /// <summary>Largest believable single-step movement along the track; anything bigger is a cut or teleport and is ignored.</summary>
        public float MaxStepDistance = 60f;

        public float Progress { get; private set; }
        public float MaxProgress { get; private set; }
        public int LapsCompleted { get; private set; }
        public bool Finished { get; private set; }
        public double FinishTime { get; private set; }
        public int BestLapMs { get; private set; }
        public int LastLapMs { get; private set; }
        public readonly List<int> LapTimesMs = new List<int>();
        public readonly List<int> SectorTimesMs = new List<int>();
        public int RejectedSteps { get; private set; }

        float lastDistance;
        double lapStartTime;
        double sectorStartTime;
        int sectorsCompletedTotal;
        bool initialised;

        public event Action<int, int> LapCompleted;       // lap number (1-based), lap time ms
        public event Action<int, int> SectorCompleted;    // sector index within the lap (0-based), sector time ms
        public event Action Finish;

        public LapTracker(float trackLength, int totalLaps, int sectorCount = 3)
        {
            if (trackLength <= 0) throw new ArgumentOutOfRangeException(nameof(trackLength));
            if (totalLaps < 1) throw new ArgumentOutOfRangeException(nameof(totalLaps));
            TrackLength = trackLength;
            TotalLaps = totalLaps;
            SectorCount = Math.Max(1, sectorCount);
        }

        /// <summary>Place the competitor at a grid distance (0..L) before the race clock starts. Distances in the last half of the lap count as behind the line.</summary>
        public void Initialise(float distanceAlongTrack)
        {
            lastDistance = Wrap(distanceAlongTrack);
            Progress = lastDistance > TrackLength * 0.5f ? lastDistance - TrackLength : lastDistance;
            MaxProgress = Progress;
            initialised = true;
        }

        public void StartClock(double time)
        {
            lapStartTime = time;
            sectorStartTime = time;
        }

        /// <summary>Hard reset of position, e.g. after a recovery respawn. Does not award laps.</summary>
        public void Relocate(float distanceAlongTrack)
        {
            float d = Wrap(distanceAlongTrack);
            float delta = SignedDelta(lastDistance, d);
            lastDistance = d;
            Progress = Math.Min(Progress + delta, MaxProgress);
        }

        public void Update(float distanceAlongTrack, double time)
        {
            if (!initialised) Initialise(distanceAlongTrack);
            if (Finished) return;
            float d = Wrap(distanceAlongTrack);
            float delta = SignedDelta(lastDistance, d);
            lastDistance = d;
            if (Math.Abs(delta) > MaxStepDistance)
            {
                RejectedSteps++;
                return;
            }
            Progress += delta;
            if (Progress <= MaxProgress) return;
            MaxProgress = Progress;

            float sectorLength = TrackLength / SectorCount;
            int sectorsNow = (int)Math.Floor(MaxProgress / sectorLength);
            while (sectorsCompletedTotal < sectorsNow)
            {
                sectorsCompletedTotal++;
                int sectorIndex = (sectorsCompletedTotal - 1) % SectorCount;
                int sectorMs = ToMs(time - sectorStartTime);
                sectorStartTime = time;
                SectorTimesMs.Add(sectorMs);
                SectorCompleted?.Invoke(sectorIndex, sectorMs);

                if (sectorIndex == SectorCount - 1)
                {
                    LapsCompleted++;
                    int lapMs = ToMs(time - lapStartTime);
                    lapStartTime = time;
                    LastLapMs = lapMs;
                    LapTimesMs.Add(lapMs);
                    if (BestLapMs == 0 || lapMs < BestLapMs) BestLapMs = lapMs;
                    LapCompleted?.Invoke(LapsCompleted, lapMs);
                    if (LapsCompleted >= TotalLaps)
                    {
                        Finished = true;
                        FinishTime = time;
                        Finish?.Invoke();
                        return;
                    }
                }
            }
        }

        /// <summary>Current lap being driven (1-based), clamped to TotalLaps.</summary>
        public int CurrentLap { get { return Math.Min(TotalLaps, LapsCompleted + 1); } }

        public double CurrentLapElapsed(double time) { return Finished ? 0 : time - lapStartTime; }

        float Wrap(float d)
        {
            d %= TrackLength;
            return d < 0 ? d + TrackLength : d;
        }

        float SignedDelta(float from, float to)
        {
            float delta = to - from;
            if (delta > TrackLength * 0.5f) delta -= TrackLength;
            else if (delta < -TrackLength * 0.5f) delta += TrackLength;
            return delta;
        }

        static int ToMs(double seconds) { return (int)Math.Round(seconds * 1000.0); }
    }
}
