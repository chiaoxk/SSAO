using System.Collections;
using System.Collections.Generic;
using UnityEditor;
using UnityEngine;

[ImageEffectAllowedInSceneView]
[ExecuteInEditMode]
[RequireComponent(typeof(Camera))]
public class AO : MonoBehaviour
{
    public enum BlurMode
    {
        None,
        Gaussian,
        HighQualityBilateral,
    }
    public enum Pass
    {
        Clear = 0,
        GaussianBlur = 2,
        HightQualityBilateralBlur = 3,
        Composite = 4,
    }
    public Texture2D NoiseTexture;

    [Range(0.01f, 1.25f)]
    public float Radius = 0.12f;
    [Range(0f, 16f)]
    public float Intensity = 2.5f;
    [Range(0f, 10f)]
    public float Distance = 1f;
    [Range(0f, 1f)]
    public float Bias = 0.1f;
    [Range(1, 4)]
    public int DownSampling = 1;
    [Range(1f, 20f)]
    public float BlurBilateralThreshold = 10f;
    [Range(1, 4)]
    public int BlurPasses = 1;
    [ColorUsage(false)]
    public Color OcclusionColor = Color.black;
    [Range(0f, 1f)]
    public float LumContribution = 0.5f;

    public float CutoffDistance = 150f;
    public float CutoffFalloff = 50f;
    public BlurMode Blur = BlurMode.HighQualityBilateral;
    public bool BlurDownSampling = false;
    public bool DebugAO = false;
    protected Shader m_AOShader;
    protected Material m_Material;
    protected Camera m_Camera;

    public Material Material
    {
        get
        {

            if (m_Material == null)
            {
                m_Material = new Material(m_AOShader) { hideFlags = HideFlags.HideAndDontSave };
            }
            return m_Material;
        }
    }

    public Shader AOShader
    {
        get
        {
            if (m_AOShader == null)
            {
                m_AOShader = Shader.Find("MyTest/AO");
                Debug.Log(m_AOShader);
            }
            return m_AOShader;
        }
    }

    private void OnEnable()
    {
        m_Camera = GetComponent<Camera>();

#if UNITY_EDITOR
        if (BuildPipeline.isBuildingPlayer)//if player is being built
        {
#endif
            if (!SystemInfo.supportsImageEffects)
            {
                Debug.LogError("Image effect are't supported on this device");
                enabled = false;
                return;
            }
            if (AOShader == null)
            {
                Debug.LogError("Missing shader (SSAO)");
                enabled = false;
                return;
            }
            if (!AOShader.isSupported)
            {
                Debug.LogError("unsupported shader");
                enabled = false;
                return;
            }
            if (!SystemInfo.SupportsRenderTextureFormat(RenderTextureFormat.Default))
            {
                Debug.LogError("depth texture are't supported in this device");
                enabled = false;
                return;
            }
#if UNITY_EDITOR
        }
#endif
    }

    private void OnPreRender()
    {
        m_Camera.depthTextureMode |= DepthTextureMode.Depth | DepthTextureMode.DepthNormals;
    }

    private void OnDisable()
    {
        if (m_Material != null)
            DestroyImmediate(m_Material);
        m_Material = null;
    }

    [ImageEffectOpaque]                                       //backbuffer
    private void OnRenderImage(RenderTexture source, RenderTexture destination)
    {
        // Fail checks
        if (AOShader == null || Mathf.Approximately(Intensity, 0f))
        {
            Graphics.Blit(source, destination);
            return;
        }

        // SSAO pass ID
        int ssaoPass = 0;

        if (NoiseTexture != null)
            ssaoPass = 1;
        // Uniforms
        Material.SetMatrix("_InverseViewProject", (m_Camera.projectionMatrix * m_Camera.worldToCameraMatrix).inverse);
        Material.SetMatrix("_CameraModelView", m_Camera.cameraToWorldMatrix);
        Material.SetTexture("_NoiseTex", NoiseTexture);
        Material.SetVector("_Params1", new Vector4(NoiseTexture == null ? 0f : NoiseTexture.width, Radius, Intensity, Distance));
        Material.SetVector("_Params2", new Vector4(Bias, LumContribution, CutoffDistance, CutoffFalloff));
        Material.SetColor("_OcclusionColor", OcclusionColor);

        Debug.Log("Blur:" + Blur);

        // Pass ID
        Pass blurPass = (Blur == BlurMode.HighQualityBilateral)
            ? Pass.HightQualityBilateralBlur
            : Pass.GaussianBlur;

        // Prep work
        int d = BlurDownSampling ? DownSampling : 1;
        RenderTexture rt1 = RenderTexture.GetTemporary(source.width / d, source.height / d,
            0, RenderTextureFormat.ARGB32);
        RenderTexture rt2 = RenderTexture.GetTemporary(source.width / DownSampling,
            source.height / DownSampling, 0, RenderTextureFormat.ARGB32);
        Graphics.Blit(rt1, rt1, Material, (int)Pass.Clear);

        // SSAO
        Graphics.Blit(source, rt1, Material, ssaoPass); Debug.Log("ssaoPass:" + ssaoPass);

        Material.SetFloat("_BilateralThreshold", BlurBilateralThreshold * 5f);

        for (int i = 0; i < BlurPasses; i++)
        {
            // Horizontal blur
            Material.SetVector("_Direction", new Vector2(1f / source.width, 0f));
            Graphics.Blit(rt1, rt2, Material, (int)blurPass);
            rt1.DiscardContents();

            // Vertical blur
            Material.SetVector("_Direction", new Vector2(0f, 1f / source.height));
            Graphics.Blit(rt2, rt1, Material, (int)blurPass);
            rt2.DiscardContents();
        }

        if (!DebugAO)
        {
            Material.SetTexture("_SSAOTex", rt1);
            Graphics.Blit(source, destination, Material, (int)Pass.Composite);
        }
        else
        {
            Graphics.Blit(rt1, destination);
        }

        RenderTexture.ReleaseTemporary(rt1);
        RenderTexture.ReleaseTemporary(rt2);

    }

}
