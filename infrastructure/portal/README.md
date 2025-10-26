# Macula Platform Portal

An elegant landing page for demo presentations that provides one-click access to all Macula Platform and CortexIQ services.

## Features

✨ **Professional Design**
- Modern, dark-themed interface
- Smooth animations and hover effects
- Responsive layout for any screen size
- Business-friendly presentation

🎯 **Easy Navigation**
- All services organized by category
- Click any card to open the service
- Visual status indicators
- Service descriptions for context

📱 **Demo-Ready**
- No need to type URLs during presentations
- Clear categorization (Platform vs Application)
- Professional branding
- Instant service access

## Quick Start

### Option 1: Using the included server script

```bash
# Start the portal server (default port 3000)
./infrastructure/portal/serve.sh

# Or specify a custom port
./infrastructure/portal/serve.sh 8000
```

Then open: **http://localhost:3000**

### Option 2: Using any HTTP server

```bash
# Python 3
cd infrastructure/portal
python3 -m http.server 3000

# Python 2
cd infrastructure/portal
python -m SimpleHTTPServer 3000

# Node.js (if you have http-server installed)
cd infrastructure/portal
npx http-server -p 3000

# PHP
cd infrastructure/portal
php -S localhost:3000
```

## Services Included

### Platform Infrastructure
- **Bondy Admin API** - WAMP router administration
- **Bondy Console** - Platform management console

### Platform Observability
- **Platform Telemetry** - Prometheus metrics (no tech stack exposure)
- **Platform Analytics** - Grafana dashboards (admin/macula123)

### CortexIQ Application
- **CortexIQ Dashboard** - Real-time energy trading simulation

## For Presentations

### Setup Before Demo

1. **Start the portal:**
   ```bash
   ./infrastructure/portal/serve.sh
   ```

2. **Open in browser:**
   ```
   http://localhost:3000
   ```

3. **Bookmark this URL** for quick access during demos

### During Demo

**Instead of typing URLs:**
- ❌ "Let me type http://telemetry.macula.local:8080..."
- ✅ Click the "Platform Telemetry" card

**Talking Points:**
1. **Portal Introduction** (10 seconds)
   - "Here's our platform portal with all services"
   - Shows organization and professionalism

2. **Platform Infrastructure** (30 seconds)
   - Click Bondy Admin/Console
   - "This is our WAMP routing layer"

3. **Platform Observability** (1 minute)
   - Click Telemetry → Show Prometheus metrics
   - Click Analytics → Show Grafana dashboards
   - "Notice we call it 'Telemetry' not 'Prometheus'"

4. **Application Demo** (3-5 minutes)
   - Click CortexIQ Dashboard
   - Main demo happens here

## Customization

### Change Colors

Edit `index.html` and modify the CSS variables:

```css
/* Primary blue */
#3b82f6 → your-color

/* Purple accent */
#8b5cf6 → your-color

/* Cyan/teal */
#06b6d4 → your-color
```

### Add New Services

Add a new card in the appropriate section:

```html
<a href="http://your-service.local:8080/" class="card" target="_blank">
    <div class="card-header">
        <div class="card-icon icon-platform">🎯</div>
        <div class="card-title">Your Service</div>
    </div>
    <div class="card-description">
        Description of your service
    </div>
    <div class="card-url">http://your-service.local:8080/</div>
    <div class="status">
        <span class="status-dot"></span>
        <span>Cluster Name</span>
    </div>
</a>
```

### Change Branding

1. **Logo/Title:** Edit `<div class="logo">` in index.html
2. **Subtitle:** Edit `<div class="subtitle">` in index.html
3. **Footer:** Edit `<footer>` section in index.html

## Browser Compatibility

Tested and works in:
- ✅ Chrome/Edge (latest)
- ✅ Firefox (latest)
- ✅ Safari (latest)
- ✅ Mobile browsers

## Tips for Presentations

1. **Full Screen Mode:**
   - Press F11 (Windows/Linux) or Cmd+Ctrl+F (Mac)
   - Hides browser UI for cleaner look

2. **Zoom Level:**
   - Set browser zoom to 90-100% for best fit
   - Cmd/Ctrl + 0 to reset zoom

3. **Tab Management:**
   - Keep portal in first tab
   - Services open in new tabs (target="_blank")
   - Easy to return to portal

4. **Projector Setup:**
   - Test on projector before demo
   - Ensure color contrast is visible
   - Check that text is readable from back of room

## Deployment to Production

For production demos, consider:

1. **Host on a web server:**
   ```bash
   # Copy to web root
   cp infrastructure/portal/index.html /var/www/html/

   # Access via
   http://your-domain.com/
   ```

2. **Deploy to CDN:**
   - Upload to S3 + CloudFront
   - Use Netlify/Vercel for instant deployment
   - Benefits: HTTPS, fast load times, global availability

3. **Kubernetes deployment:**
   - Create nginx deployment serving the HTML
   - Expose via Ingress (e.g., portal.macula.local)
   - Benefits: Part of the platform infrastructure

## Troubleshooting

**Services not loading:**
- Ensure `/etc/hosts` is configured (run `sudo infrastructure/scripts/setup-hosts.sh`)
- Verify nginx-ingress is running on port 8080
- Check that all services are deployed

**Portal won't start:**
- Ensure Python is installed (`python3 --version`)
- Try a different port if 3000 is in use
- Check file permissions on `serve.sh`

**Styling issues:**
- Hard refresh: Ctrl+Shift+R (Windows/Linux) or Cmd+Shift+R (Mac)
- Clear browser cache
- Try a different browser

## Kubernetes Deployment (Production)

The portal is deployed as part of the hub-01 cluster infrastructure:

```bash
# Deploy portal to hub-01 cluster
kubectl --context kind-macula-hub apply -k infrastructure/gitops/kind/clusters/hub-01/portal

# Setup DNS entry
sudo infrastructure/scripts/setup-hosts.sh

# Access portal
open http://portal.macula.local:8080/
```

**Kubernetes Resources**:
- ConfigMap: `portal-html` - Embedded HTML content
- Deployment: `portal` - nginx:1.25-alpine serving static HTML
- Service: `portal` - NodePort 30003
- Ingress: `portal` - Route portal.macula.local to nginx

**Benefits**:
- Part of platform infrastructure
- Consistent with other services
- No external dependencies needed
- Automatically included in GitOps deployments

---

**Questions?** Check the main documentation: `infrastructure/SIDECAR_IMPLEMENTATION.md`
