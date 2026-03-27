<h1>React Preview Server</h1>

<p>A lightweight, standalone, and self-hosted tool to automatically deploy and serve preview environments for every branch of your React/Vite application.</p>

<p>Fully powered by Node.js and Express, this project replaces complex infrastructures with a simple "plug &amp; play" Docker container. Run it, provide a Git URL, and it handles the rest.</p>

<h2>🚀 Features</h2>
<ul>
    <li><strong>Automatic Deployment (Polling):</strong> Monitors the Git repository and automatically builds new branches or commits.</li>
    <li><strong>Built-in Web Server:</strong> Uses Express.js to serve static files efficiently, without relying on Nginx.</li>
    <li><strong>Native SPA Support:</strong> Automatic and smart redirection to <code>index.html</code> to perfectly support client-side routing (React Router, Vue Router).</li>
    <li><strong>Dynamic Dashboard:</strong> Generates a home page (<code>index.html</code>) listing all currently deployed and accessible branches.</li>
    <li><strong>Auto-cleanup:</strong> Detects deleted branches on the remote repository and automatically frees up disk space.</li>
    <li><strong>Persistent NPM Cache:</strong> Significantly speeds up build times by sharing a dependency cache across different branches.</li>
</ul>

<h2>🛠️ Prerequisites</h2>
<ul>
    <li>Docker installed on the host machine.</li>
    <li>A Git repository containing a web application (React, Vite, etc.) configured to be built via <code>npm run build</code> and outputting a <code>dist/</code> folder.</li>
</ul>

<h2>📦 Quick Deployment</h2>
<p>Build the local Docker image, then run the container injecting your environment variables.</p>

<h3>1. Image Build</h3>
<pre><code>docker build -t react-preview-node .</code></pre>

<h3>2. Run Container</h3>
<pre><code>docker run -d \
  -e REPO_URL="https://github.com/your-account/your-app.git" \
  -e PROJECT_NAME="myproject" \
  -p 8080:80 \
  --name react-preview \
  react-preview-node</code></pre>

<p>Your central dashboard grouping all compiled branches will be accessible at <code>http://localhost:8080/</code>.</p>

<h2>⚙️ Environment Variables</h2>
<table>
    <thead>
        <tr>
            <th>Variable</th>
            <th>Description</th>
            <th>Default</th>
            <th>Required</th>
        </tr>
    </thead>
    <tbody>
        <tr>
            <td><code>REPO_URL</code></td>
            <td>The HTTPS URL of your Git repository.</td>
            <td>-</td>
            <td><strong>Yes</strong></td>
        </tr>
        <tr>
            <td><code>PROJECT_NAME</code></td>
            <td>The project name. Used to isolate the project and generate paths (e.g., /PROJECT_NAME/branch).</td>
            <td>-</td>
            <td><strong>Yes</strong></td>
        </tr>
        <tr>
            <td><code>GIT_TOKEN</code></td>
            <td>A Personal Access Token (PAT) if your Git repository is private.</td>
            <td><code>""</code></td>
            <td>No</td>
        </tr>
        <tr>
            <td><code>INTERVAL_SECONDS</code></td>
            <td>The wait time (in seconds) between each check for updates on Git.</td>
            <td><code>120</code></td>
            <td>No</td>
        </tr>
    </tbody>
</table>

<h2>🏗️ How it works under the hood</h2>
<ol>
    <li>On startup, the script clones the repository into an isolated environment (<code>/tmp/workdir</code>).</li>
    <li>At regular intervals, it polls GitHub to fetch the commit identifiers (hashes) of all branches.</li>
    <li>If a new commit is detected, the manager installs dependencies (favoring offline mode via cache) and runs <code>npm run build</code>.</li>
    <li>The resulting static build is moved to the Web server's public folder (<code>/var/www/html/PROJECT_NAME/BRANCH</code>).</li>
    <li>The Express server intercepts web traffic. It directly serves physical folders when they exist. If it's a SPA (virtual) route, it seamlessly redirects the request to the corresponding branch's <code>index.html</code> file.</li>
</ol>

<h2>📝 URL Structure</h2>
<p>The application automatically injects the <code>VITE_BASE_PATH</code> and <code>PUBLIC_URL</code> variables during the build so that your React application's internal paths match the deployment structure:</p>

<pre><code>http://your-domain.com/[PROJECT_NAME]/[BRANCH_NAME]/</code></pre>