namespace Gridline.Race
{
    /// <summary>Parameters carried from the menu (or a test) into the race scene.</summary>
    public static class RaceSession
    {
        public const string MenuScene = "Menu";
        public const string RaceScene = "Race";

        public static int Laps = 3;
        public static int AiOpponents = 4;
        public static string EventName = "Ashford Club Sprint";

        /// <summary>When true the player car is driven by the AI (automated smoke tests, attract mode).</summary>
        public static bool AutopilotPlayer;
        /// <summary>When false, the race result is not applied to the career or saved (automated tests).</summary>
        public static bool AffectsCareer = true;
        /// <summary>Set once the entry fee for the current event is paid, so a mid-race restart does not charge again.</summary>
        public static bool EntryPaid;

        public static void ResetForTests(int laps)
        {
            Laps = laps;
            AutopilotPlayer = true;
            AffectsCareer = false;
            EntryPaid = true;
        }
    }
}
