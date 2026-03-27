import express from 'express';
import fs from 'fs/promises';
import { existsSync } from 'fs';
import path from 'path';
import { exec } from 'child_process';
import util from 'util';

const execAsync = util.promisify(exec);

const REPO_URL = process.env.REPO_URL;
const PROJECT_NAME = process.env.PROJECT_NAME;
const GIT_TOKEN = process.env.GIT_TOKEN || '';
const INTERVAL_MS = (parseInt(process.env.INTERVAL_SECONDS) || 120) * 1000;
const HTTP_PORT = 80;

const BASE_WWW_DIR = '/var/www/html';
const WORK_DIR = `/tmp/workdir/${PROJECT_NAME}`;
const DEST_DIR = path.join(BASE_WWW_DIR, PROJECT_NAME);
const STATE_FILE = path.join(DEST_DIR, 'state.json');

if (!REPO_URL || !PROJECT_NAME) {
    console.error("[ERROR] REPO_URL and PROJECT_NAME environment variables are required.");
    process.exit(1);
}

const AUTH_REPO_URL = (GIT_TOKEN && REPO_URL.startsWith('https://'))
    ? REPO_URL.replace('https://', `https://${GIT_TOKEN}@`)
    : REPO_URL;

const app = express();

app.use(express.static(BASE_WWW_DIR));

app.use('/:project/:branch', (req, res, next) => {
    const { project, branch } = req.params;
    const branchDir = path.join(BASE_WWW_DIR, project, branch);
    const indexPath = path.join(branchDir, 'index.html');

    if (existsSync(branchDir) && existsSync(indexPath)) {
        // Send the branch's main entry point for SPA routing
        res.sendFile(indexPath);
    } else {
        next();
    }
});

app.use((req, res) => {
    res.status(404).send('404 - Not Found or Branch Not Deployed Yet');
});

app.listen(HTTP_PORT, () => {
    console.log(`[SERVER] Web server listening on port ${HTTP_PORT}`);
});


class DeployManager {
    log(message) {
        const time = new Date().toLocaleTimeString('en-US', { hour12: false });
        console.log(`[${PROJECT_NAME}] [${time}] ${message}`);
    }

    sanitizeBranchName(branchName) {
        return branchName.toLowerCase().replace(/[^a-z0-9]/g, '-').replace(/^-|-$/g, '');
    }

    async loadState() {
        try {
            if (existsSync(STATE_FILE)) {
                const data = await fs.readFile(STATE_FILE, 'utf-8');
                return JSON.parse(data);
            }
        } catch (error) {
            this.log(`Warning: Could not read state file, starting fresh.`);
        }
        return {};
    }

    async saveState(state) {
        await fs.writeFile(STATE_FILE, JSON.stringify(state, null, 2));
    }

    async initGit() {
        await fs.mkdir(WORK_DIR, { recursive: true });
        await fs.mkdir(DEST_DIR, { recursive: true });

        if (!existsSync(path.join(WORK_DIR, '.git'))) {
            this.log(`Performing initial git clone...`);
            await execAsync(`git clone "${AUTH_REPO_URL}" . --quiet`, { cwd: WORK_DIR });
        }
    }

    async getRemoteBranches() {
        await execAsync(`git fetch --all --prune --quiet`, { cwd: WORK_DIR });
        const { stdout } = await execAsync(`git branch -r | grep origin/ | grep -v HEAD`, { cwd: WORK_DIR });

        const branches = stdout.split('\n')
            .map(b => b.trim().replace('origin/', ''))
            .filter(b => b.length > 0);

        const branchHashes = {};
        for (const branch of branches) {
            const { stdout: hash } = await execAsync(`git rev-parse "origin/${branch}"`, { cwd: WORK_DIR });
            branchHashes[branch] = hash.trim();
        }
        return branchHashes;
    }

    async buildBranch(branch, safeBranch) {
        this.log(`Starting build for branch: ${branch}`);

        try {
            // Clean working directory and checkout target branch
            await execAsync(`git clean -fdx && git reset --hard && git checkout -B "${branch}" "origin/${branch}" --quiet`, { cwd: WORK_DIR });

            if (!existsSync(path.join(WORK_DIR, 'package.json'))) {
                this.log(`No package.json found in branch ${branch}, skipping.`);
                return false;
            }

            const hasPackageLock = existsSync(path.join(WORK_DIR, 'package-lock.json'));
            const installCmd = hasPackageLock ? 'npm ci --silent --prefer-offline' : 'npm install --silent --prefer-offline';

            this.log(`Installing dependencies for ${branch}...`);
            await execAsync(installCmd, { cwd: WORK_DIR });

            const basePath = `/${PROJECT_NAME}/${safeBranch}/`;
            const env = {
                ...process.env,
                VITE_BASE_PATH: basePath,
                PUBLIC_URL: basePath
            };

            this.log(`Compiling branch ${branch} with base path ${basePath}...`);
            await execAsync(`npm run build -- --base="${basePath}"`, { cwd: WORK_DIR, env });

            const branchDestPath = path.join(DEST_DIR, safeBranch);

            // Remove old deployment and copy new build directory
            await fs.rm(branchDestPath, { recursive: true, force: true });
            await fs.mkdir(branchDestPath, { recursive: true });
            await execAsync(`cp -a dist/* "${branchDestPath}/"`, { cwd: WORK_DIR });

            this.log(`Successfully deployed ${branch} to ${basePath}`);
            return true;
        } catch (error) {
            this.log(`Build failed for ${branch}. Error: ${error.message}`);
            return false;
        }
    }

    async cleanup(activeSafeBranches) {
        const dirs = await fs.readdir(DEST_DIR, { withFileTypes: true });
        for (const dirent of dirs) {
            if (dirent.isDirectory() && !activeSafeBranches.includes(dirent.name)) {
                this.log(`Removing deleted branch directory: ${dirent.name}`);
                await fs.rm(path.join(DEST_DIR, dirent.name), { recursive: true, force: true });
            }
        }
    }

    async generateDashboard(activeSafeBranches) {
        const indexPath = path.join(DEST_DIR, 'index.html');
        const jsonPath = path.join(DEST_DIR, 'branches.json');

        try {
            if (existsSync('/app/index.html')) {
                await fs.copyFile('/app/index.html', indexPath);
            }
        } catch (e) {
            this.log(`Warning: Could not copy dashboard index.html template.`);
        }

        const branchesData = {
            base_path: `/${PROJECT_NAME}`,
            last_update: new Date().toISOString().replace('T', ' ').substring(0, 19),
            branches: activeSafeBranches.map(branch => ({
                name: branch,
                link: `/${PROJECT_NAME}/${branch}/`
            }))
        };

        await fs.writeFile(jsonPath, JSON.stringify(branchesData, null, 2));
    }

    async sync() {
        try {
            await this.initGit();
            const remoteBranches = await this.getRemoteBranches();
            const localState = await this.loadState();

            let stateChanged = false;
            const activeSafeBranches = [];

            // 1. Process branches sequentially
            for (const [branch, remoteHash] of Object.entries(remoteBranches)) {
                const safeBranch = this.sanitizeBranchName(branch);
                activeSafeBranches.push(safeBranch);

                if (localState[safeBranch] !== remoteHash) {
                    this.log(`New commit detected on '${branch}' (${remoteHash})`);

                    // Immediately update state to avoid infinite build loops if the build crashes
                    localState[safeBranch] = remoteHash;
                    stateChanged = true;

                    await this.buildBranch(branch, safeBranch);
                }
            }

            // 2. Remove obsolete branches
            await this.cleanup(activeSafeBranches);

            // 3. Generate Dashboard /branches.json
            await this.generateDashboard(activeSafeBranches);

            // 4. Save new state
            if (stateChanged) {
                await this.saveState(localState);
            }

        } catch (error) {
            this.log(`Critical synchronization error: ${error.message}`);
        }
    }

    start() {
        this.log(`Deployment manager started. Checking git repository every ${INTERVAL_MS / 1000} seconds.`);
        this.sync();
        setInterval(() => this.sync(), INTERVAL_MS);
    }
}

const manager = new DeployManager();
manager.start();