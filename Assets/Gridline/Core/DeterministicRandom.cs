using System;

namespace Gridline.Core
{
    /// <summary>Small seeded xorshift RNG so league simulations are reproducible across platforms and runs.</summary>
    [Serializable]
    public class DeterministicRandom
    {
        public uint state;

        public DeterministicRandom(uint seed)
        {
            state = seed == 0 ? 0x9E3779B9u : seed;
        }

        public uint NextUInt()
        {
            uint x = state;
            x ^= x << 13;
            x ^= x >> 17;
            x ^= x << 5;
            state = x;
            return x;
        }

        /// <summary>Uniform in [0, 1).</summary>
        public double NextDouble() { return NextUInt() / 4294967296.0; }

        public float Range(float min, float max) { return (float)(min + (max - min) * NextDouble()); }

        /// <summary>Approximately normal (Irwin–Hall, n = 4), mean 0, std dev ~1.</summary>
        public float Gaussian()
        {
            double s = NextDouble() + NextDouble() + NextDouble() + NextDouble();
            return (float)((s - 2.0) * Math.Sqrt(3.0));
        }
    }
}
