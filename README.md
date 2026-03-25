# React Preview

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

The container is configured via mandatory environment variables:

| Variable | Description | Example |
| :--- | :--- | :--- |
| `REPO_URL` | Git repository URL (HTTPS) | `https://github.com/user/my-react-app.git` |
| `DOMAIN` | Domain name used (for logs/links) | `preview.my-site.com` |
| `BASE_PATH` | Base URL path prefix | `app` or `/` |

Optional variables:

| Variable | Description                                                                                                                                       | Default |
| :--- |:--------------------------------------------------------------------------------------------------------------------------------------------------| :--- |
| `BRANCH_REGEX` | Regex to filter branches to deploy (e.g., `^(master\|dev\|feature/.*)$` to deploy dev, master or feature/ branches) | (All branches) |

## 📦 Usage with Docker

The Docker image is available on Docker Hub as `ocelus/react-preview`.

### Run with Docker Run

```bash
docker run -d \
  -e REPO_URL="https://github.com/your-account/your-project.git" \
  -e DOMAIN="localhost" \
  -e BASE_PATH="preview" \
  -p 8080:80 \
  --name react-preview \
  ocelus/react-preview
```

### Docker Compose Example

```yaml
version: '3.8'

services:
  react-preview:
    image: ocelus/react-preview
    ports:
      - "8080:80"
    environment:
      - REPO_URL=https://github.com/my-org/my-react-project.git
      - DOMAIN=preview.mydomain.com
      - BASE_PATH=projects
      - BRANCH_REGEX=^(dev|master|features/) # Optional: dev, master and features/
    volumes:
      - preview_data:/var/www/html
    restart: always

volumes:
  preview_data:
```

## 📝 Project Structure

- `Dockerfile`: Based on Node 20 Alpine, installs Git, Nginx, and Gettext.
- `sync.sh`: Main script for synchronization, build, and cleanup.
- `nginx.conf.template`: Nginx template configured to support SPA routing on dynamic sub-paths.

## 🔗 Environment Access

Once deployed, branches are accessible via:
`https://${DOMAIN}/${BASE_PATH}/${branch-name}/`

*Note: Branch names are normalized (converted to lowercase, special characters replaced by dashes).*
