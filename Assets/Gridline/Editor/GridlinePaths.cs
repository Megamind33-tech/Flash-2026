namespace Gridline.EditorTools
{
    public static class GridlinePaths
    {
        public const string Generated = "Assets/Gridline/Generated";
        public const string Materials = Generated + "/Materials";
        public const string Meshes = Generated + "/Meshes";
        public const string Textures = Generated + "/Textures";
        public const string Settings = Generated + "/Settings";
        public const string Scenes = "Assets/Gridline/Scenes";
        public const string MenuScene = Scenes + "/Menu.unity";
        public const string RaceScene = Scenes + "/Race.unity";
        public const string SurfaceTextures = "Assets/Gridline/Art/Textures/Surfaces";
        public const string LiveryTextures = "Assets/Gridline/Art/Textures/Liveries";
        public const string RvpRoot = "Assets/ThirdParty/RVP";
        public const string CarPrefab = RvpRoot + "/Prefabs/Mobile Vehicles/Muscle Car.prefab";
        public const string GlobalControlPrefab = RvpRoot + "/Prefabs/GlobalControl.prefab";
        public const string RvpBodyMaterial = RvpRoot + "/Materials/Vehicles/Muscle Car/Body.mat";

        public static void EnsureFolder(string path)
        {
            if (UnityEditor.AssetDatabase.IsValidFolder(path)) return;
            string parent = System.IO.Path.GetDirectoryName(path).Replace('\\', '/');
            EnsureFolder(parent);
            UnityEditor.AssetDatabase.CreateFolder(parent, System.IO.Path.GetFileName(path));
        }
    }
}
