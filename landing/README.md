# MyEduDrive landing page preview

This is a static MyEduDrive landing page. It can be previewed by itself or served by the project's custom landing image.

## Preview

Open `index.html` directly in a browser. Use the **عربي / English** control to switch languages and the sun/moon control to switch themes. The page follows your system theme on first visit, then remembers your selection. From a local file preview, the sign-in button asks for the Minikube address and opens its `/login` page. A typical address is `http://<MINIKUBE-IP>:30080/login`.

When this page is eventually served from the same origin as MyEduDrive, its sign-in links use `/login` directly.

## Integration status

The custom landing image serves this page at `/` and proxies `/login` and other application routes. The MyEduDrive server image carries its logo outside `/var/www/html` so the existing PVC does not hide it. The deployment script applies the supported server branding after the service is ready. See the project-root `DOCKER_HUB_AND_BRANDING_AR.md` for build and rollout steps.

The original supplied JPEG is retained. Transparent high-resolution assets are derived from it: `assets/myedudrive-logo-transparent-v2.png` for the full light wordmark, `assets/myedudrive-logo-dark-transparent-v2.png` for the dark theme, and `assets/myedudrive-symbol-transparent.png` for the cloud-folder mark. Header/footer pair the symbol with a text wordmark; the closing section switches between the full transparent variants.
