using System.Collections;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

namespace __NAMESPACE__.Tests.PlayMode
{
    // Day-one smoke test so the GameCI PlayMode job has something to run.
    // Replace with real scene / MonoBehaviour tests as the project grows.
    public class SmokeTests
    {
        [UnityTest]
        public IEnumerator FrameAdvancesInPlayMode()
        {
            int startFrame = Time.frameCount;

            yield return null;

            Assert.Greater(Time.frameCount, startFrame);
        }
    }
}
