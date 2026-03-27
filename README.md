<h1>React Preview Server</h1>

<p>A lightweight, standalone, and self-hosted tool to automatically deploy and serve preview environments for every branch of your React/Vite applications.</p>

<p>Fully powered by Node.js and Express, this project replaces complex infrastructures with a simple "plug &amp; play" Docker container. It natively supports multiple repositories through a JSON configuration file.</p>

<h2>🚀 Features</h2>
<ul>
    <li><strong>Multi-Project Support:</strong> Track and deploy multiple Git repositories simultaneously using a single <code>projects.json</code> configuration.</li>
    <li><strong>Automatic Deployment:</strong> Monitors Git repositories and builds new branches or commits via polling.</li>
    <li><strong>Built-in Web Server:</strong> Uses Express.js to serve static files efficiently.</li>
    <li><strong>Native SPA Support:</strong> Automatic redirection to <code>index.html</code> for client-side routing (React Router, Vue Router).</li>
    <li><strong>Dynamic Dashboard:</strong> Generates a home page listing all currently deployed branches per project.</li>
    <li><strong>Persistent Cache:</strong> Speeds up build times by sharing the NPM dependency cache.</li>
</ul>

<h2>🛠️ Prerequisites</h2>
<ul>
    <li>Docker installed on the host machine.</li>
    <li>Git repository(ies) configured to be built via <code>npm run build</code> and outputting a <code>dist/</code> folder.</li>
</ul>

<h2>⚙️ Configuration</h2>
<p>You can configure the server using environment variables for a <strong>single project</strong>, or a <code>projects.json</code> file for <strong>multiple projects</strong>.</p>

<h3>Option 1: Single Project (Environment Variables)</h3>
<table>
    <thead>
        <tr>
            <th>Variable</th>
            <th>Description</th>
            <th>Required</th>
        </tr>
    </thead>
    <tbody>
        <tr>
            <td><code>REPO_URL</code></td>
            <td>HTTPS URL of your Git repository.</td>
            <td><strong>Yes</strong></td>
        </tr>
        <tr>
            <td><code>GIT_TOKEN</code></td>
            <td>Personal Access Token (PAT) for private repositories.</td>
            <td>No</td>
        </tr>
        <tr>
            <td><code>BRANCH_REGEX</code></td>
            <td>Regex to filter branches (e.g., <code>^feature/</code>).</td>
            <td>No</td>
        </tr>
        <tr>
            <td><code>INTERVAL_SECONDS</code></td>
            <td>Polling interval in seconds (default: 120).</td>
            <td>No</td>
        </tr>
    </tbody>
</table>

<pre><code>docker run -d \
  -e REPO_URL="https://github.com/your-account/your-app.git" \
  -p 8080:80 \
  --name react-preview \
  react-preview-node</code></pre>

<h3>Option 2: Multiple Projects (projects.json)</h3>
<p>Create a <code>projects.json</code> file on your host machine to track multiple repositories.</p>

<pre><code>[
  {
    "REPO_URL": "https://github.com/your-account/app-one.git",
    "GIT_TOKEN": "your_token",
    "BRANCH_REGEX": "^(master|feature)"
  },
  {
    "REPO_URL": "https://github.com/your-account/app-two.git"
  }
]</code></pre>

<p>Run the container by mounting this file:</p>

<pre><code>docker run -d \
  -v $(pwd)/projects.json:/projects.json \
  -p 8080:80 \
  --name react-preview \
  react-preview-node</code></pre>

<h2>📝 URL Structure</h2>
<p>The application automatically routes projects based on the repository name extracted from the <code>REPO_URL</code>:</p>

<pre><code>http://your-domain.com/[PROJECT_NAME]/[BRANCH_NAME]/</code></pre>