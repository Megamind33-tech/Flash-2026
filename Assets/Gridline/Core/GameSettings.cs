using System;

namespace Gridline.Core
{
    public enum SteeringMode { TouchButtons = 0, Tilt = 1 }
    public enum TransmissionMode { Automatic = 0, Manual = 1 }
    public enum CameraMode { Chase = 0, ChaseNear = 1, Hood = 2 }

    [Serializable]
    public class GameSettings
    {
        public SteeringMode steeringMode = SteeringMode.TouchButtons;
        public TransmissionMode transmission = TransmissionMode.Automatic;
        public CameraMode camera = CameraMode.Chase;
        /// <summary>0.25..2.0 multiplier on steering response.</summary>
        public float steeringSensitivity = 1f;
        /// <summary>Quality level index: 0 = Low (budget), 1 = Medium, 2 = High.</summary>
        public int qualityLevel = 1;
        public bool showFps;
        public float masterVolume = 0.8f;

        public void Sanitise()
        {
            if (steeringSensitivity < 0.25f || steeringSensitivity > 2f || float.IsNaN(steeringSensitivity)) steeringSensitivity = 1f;
            if (qualityLevel < 0 || qualityLevel > 2) qualityLevel = 1;
            if (masterVolume < 0f || masterVolume > 1f || float.IsNaN(masterVolume)) masterVolume = 0.8f;
            if (!Enum.IsDefined(typeof(SteeringMode), steeringMode)) steeringMode = SteeringMode.TouchButtons;
            if (!Enum.IsDefined(typeof(TransmissionMode), transmission)) transmission = TransmissionMode.Automatic;
            if (!Enum.IsDefined(typeof(CameraMode), camera)) camera = CameraMode.Chase;
        }
    }
}
