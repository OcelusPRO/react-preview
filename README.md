# React Preview
[![Docker Pulls](https://img.shields.io/docker/pulls/ocelus/react-preview?style=flat-square)](https://hub.docker.com/r/ocelus/react-preview)
[![Docker Stars](https://img.shields.io/docker/stars/ocelus/react-preview?style=flat-square)](https://hub.docker.com/r/ocelus/react-preview)
[![GitHub stars](https://img.shields.io/github/stars/OcelusPRO/react-preview?style=flat-square)](https://github.com/OcelusPRO/react-preview)

This project allows automatic deployment of preview environments for each branch of a Git repository containing a React application (designed with Vite). 

Each branch is compiled and served under a specific sub-directory, allowing simultaneous access to multiple versions of the application.

## 🚀 How it works

1. **Synchronization**: A script (`sync.sh`) monitors the configured Git repository every 120 seconds.
2. **Automatic Build**: For each branch (can be filtered by regex), the script:
   - Installs dependencies with `npm ci`.
   - Compiles the application with `npm run build` by injecting the correct `VITE_BASE_PATH`.
3. **Deployment**: Compiled files are placed in `/var/www/html/${BASE_PATH}/${branch_name}`.
4. **Web Service**: Nginx serves the files and handles SPA routing (History API) for each environment.
5. **Cleanup**: Environments corresponding to branches deleted from the remote repository are automatically removed from the server.

## 🛠️ Configuration

The container can be configured in two ways: via environment variables (for a single project) or via a JSON file (for multiple projects).

### Single Project Mode (Environment Variables)

| Variable | Description | Example                                    |
| :--- | :--- |:-------------------------------------------|
| `REPO_URL` | Git repository URL (HTTPS) | `https://github.com/user/my-react-app.git` |
| `DOMAIN` | Domain name (mandatory) | `preview.my-site.com`                      |
| `BASE_PATH` | Base URL path prefix | `app` or `/`                               |
| `BRANCH_REGEX` | (Optional) Regex to filter branches | `^(master\|dev)$`                          |

### Multiple Projects Mode (JSON File)

To manage multiple Git repositories simultaneously, mount a `projects.json` file at `/projects.json`.
The `DOMAIN` variable must still be defined in the environment.

Example `projects.json`:
```json
[
  {
    "REPO_URL": "https://github.com/user/project-1.git",
    "BASE_PATH": "app1",
    "BRANCH_REGEX": "^master$"
  },
  {
    "REPO_URL": "https://github.com/user/project-2.git",
    "BASE_PATH": "app2"
  }
]
```

## 📦 Usage with Docker

The Docker image is available on Docker Hub as `ocelus/react-preview`.

### Run with Docker Run (Single Project)

```bash
docker run -d \
  -e REPO_URL="https://github.com/your-account/your-project.git" \
  -e DOMAIN="localhost" \
  -e BASE_PATH="preview" \
  -p 8080:80 \
  --name react-preview \
  ocelus/react-preview
```

### Run with Docker Compose (Multiple Projects)

```yaml
version: '3.8'

services:
  react-preview:
    image: ocelus/react-preview
    ports:
      - "8080:80"
    environment:
      - DOMAIN=preview.mydomain.com
    volumes:
      - ./projects.json:/projects.json:ro
      - preview_data:/var/www/html
    restart: always

volumes:
  preview_data:
```

## 📝 Project Structure

- `Dockerfile`: Based on Node 20 Alpine, installs Git, Nginx, JQ and Gettext.
- `sync.sh`: Main script for synchronization, build, and index generation.
- `nginx.conf.template`: Nginx configuration supporting dynamic SPA routing.

## 🔗 Environment Access

Once deployed, branches are accessible via:
`https://${DOMAIN}/${BASE_PATH}/${branch-name}/`

An index page is automatically created at `https://${DOMAIN}/${BASE_PATH}/` listing all active deployments for that path.

*Note: Branch names are normalized (converted to lowercase, special characters replaced by dashes).*
