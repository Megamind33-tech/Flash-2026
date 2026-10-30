using Gridline.Core;
using UnityEngine;

namespace Gridline.CameraRig
{
    /// <summary>
    /// Stabilised chase camera: follows yaw only (pitch and roll of the car are filtered out), with damped position,
    /// speed-dependent field of view, and a hood view. Modes cycle Chase -> ChaseNear -> Hood.
    /// </summary>
    [RequireComponent(typeof(Camera))]
    public class RaceCamera : MonoBehaviour
    {
        public Transform target;
        public Rigidbody targetBody;
        public CameraMode mode = CameraMode.Chase;

        public float positionDamping = 0.12f;
        public float yawDamping = 0.18f;
        public float baseFov = 58f;
        public float maxFovBoost = 10f;

        Camera cam;
        Vector3 velocity;
        float yaw, yawVelocity;
        bool snapped;

        void Awake()
        {
            cam = GetComponent<Camera>();
        }

        public void SetTarget(Transform t, Rigidbody body)
        {
            target = t;
            targetBody = body;
            snapped = false;
        }

        public CameraMode Cycle()
        {
            mode = (CameraMode)(((int)mode + 1) % 3);
            snapped = false;
            return mode;
        }

        void LateUpdate()
        {
            if (target == null) return;
            Vector3 flatFwd = target.forward;
            flatFwd.y = 0f;
            if (flatFwd.sqrMagnitude < 1e-4f) flatFwd = transform.forward;
            float targetYaw = Mathf.Atan2(flatFwd.x, flatFwd.z) * Mathf.Rad2Deg;
            float speed = targetBody != null ? targetBody.linearVelocity.magnitude : 0f;

            if (!snapped)
            {
                yaw = targetYaw;
                yawVelocity = 0f;
                velocity = Vector3.zero;
            }
            yaw = Mathf.SmoothDampAngle(yaw, targetYaw, ref yawVelocity, mode == CameraMode.Hood ? 0.02f : yawDamping);
            Quaternion yawRot = Quaternion.Euler(0f, yaw, 0f);

            if (mode == CameraMode.Hood)
            {
                transform.position = target.TransformPoint(new Vector3(0f, 1.25f, 0.35f));
                // Keep some of the car's pitch so crests read, but never roll the horizon.
                transform.rotation = Quaternion.LookRotation(target.forward, Vector3.up);
            }
            else
            {
                float dist = mode == CameraMode.Chase ? 6.6f : 4.9f;
                float height = mode == CameraMode.Chase ? 2.3f : 1.7f;
                Vector3 desired = target.position + yawRot * new Vector3(0f, height, -dist);
                transform.position = snapped ? Vector3.SmoothDamp(transform.position, desired, ref velocity, positionDamping) : desired;
                Vector3 look = target.position + Vector3.up * 1.0f + yawRot * Vector3.forward * 3f;
                transform.rotation = Quaternion.LookRotation(look - transform.position, Vector3.up);
            }
            cam.fieldOfView = Mathf.Lerp(cam.fieldOfView, baseFov + maxFovBoost * Mathf.Clamp01(speed / 60f), 3f * Time.deltaTime);
            snapped = true;
        }
    }
}
